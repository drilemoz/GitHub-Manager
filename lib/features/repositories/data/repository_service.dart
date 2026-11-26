import 'package:github_manager/core/errors/app_exception.dart';
import 'package:github_manager/core/network/github_api_client.dart';
import 'package:github_manager/core/persistence/local_database.dart';
import 'package:github_manager/features/repositories/domain/github_repository.dart';
import 'package:github_manager/features/repositories/domain/repository_name_rules.dart';
import 'package:github_manager/features/repositories/domain/repository_list_sort.dart';

class RepositoryService {
  RepositoryService(this._client, this._database);

  static const _followedKey = 'followed.repositories';
  final GitHubApiClient _client;
  final LocalDatabase _database;
  Future<List<GitHubRepository>>? _repositoriesRefreshInFlight;
  Future<List<GitHubRepository>>? _followedRefreshInFlight;
  final Map<String, GitHubRepository> _repositoryCache = {};

  GitHubRepository? cachedRepository(String fullName) =>
      _repositoryCache[fullName.toLowerCase()];

  void _rememberRepository(GitHubRepository repository) {
    if (repository.fullName.isNotEmpty) {
      _repositoryCache[repository.fullName.toLowerCase()] = repository;
    }
  }

  // Deixe consultas anteriores ao push terminarem antes de invalidar as listas.
  Future<void> waitForPendingListRefreshes() async {
    final pending = [
      _repositoriesRefreshInFlight,
      _followedRefreshInFlight,
    ];
    for (final future in pending) {
      if (future == null) continue;
      try {
        await future;
      } catch (_) {
        // A próxima consulta fará uma nova tentativa.
      }
    }
  }

  Future<List<GitHubRepository>> listRepositories() => refreshRepositories();

  Future<List<GitHubRepository>> refreshRepositories() async {
    final running = _repositoriesRefreshInFlight;
    if (running != null) return running;
    final future = _fetchRepositoriesFromGitHub();
    _repositoriesRefreshInFlight = future;
    try {
      return await future;
    } finally {
      if (identical(_repositoriesRefreshInFlight, future)) {
        _repositoriesRefreshInFlight = null;
      }
    }
  }

  Future<List<GitHubRepository>> _fetchRepositoriesFromGitHub() async {
    final repositories = <GitHubRepository>[];
    for (var page = 1; page <= 10; page++) {
      final response = await _client.get<List<dynamic>>(
        '/user/repos',
        queryParameters: {
          'affiliation': 'owner,collaborator,organization_member',
          'sort': 'pushed',
          'direction': 'desc',
          'per_page': 100,
          'page': page,
        },
      );
      final pageItems = (response.data ?? const <dynamic>[])
          .whereType<Map>()
          .map((json) => GitHubRepository.fromJson(Map<String, dynamic>.from(json)))
          .toList(growable: false);
      repositories.addAll(pageItems);
      for (final repository in pageItems) {
        _rememberRepository(repository);
      }
      if (pageItems.length < 100) break;
    }
    try {
      await _database.reconcileFavoriteRepositories(
        repositories.map((repository) => repository.id).toSet(),
      );
    } catch (_) {
      // Fixados são estado local auxiliar. Uma falha no SQLite nunca pode
      // impedir a lista principal, que já foi carregada corretamente do GitHub.
    }
    return sortRepositories(repositories, sort: RepositorySort.updatedDesc);
  }

  Future<Set<int>> listFavoriteRepositoryIds() =>
      _database.readFavoriteRepositoryIds();

  Future<void> setRepositoryFavorite(
    GitHubRepository repository, {
    required bool favorite,
  }) =>
      _database.setFavoriteRepository(
        repositoryId: repository.id,
        fullName: repository.fullName,
        favorite: favorite,
      );

  Future<List<String>> _readFollowedNames() async {
    final stored = await _database.readJson(_followedKey);
    final source = stored is List
        ? stored.whereType<String>()
        : const Iterable<String>.empty();
    final names = <String>[];
    final seen = <String>{};
    for (final raw in source) {
      final name = raw.trim();
      if (name.isEmpty) continue;
      if (seen.add(name.toLowerCase())) names.add(name);
    }
    return names;
  }

  Future<List<GitHubRepository>> listFollowedRepositories() =>
      refreshFollowedRepositories();

  Future<List<GitHubRepository>> refreshFollowedRepositories() async {
    final running = _followedRefreshInFlight;
    if (running != null) return running;
    final future = _refreshFollowedRepositoriesNow();
    _followedRefreshInFlight = future;
    try {
      return await future;
    } finally {
      if (identical(_followedRefreshInFlight, future)) {
        _followedRefreshInFlight = null;
      }
    }
  }

  Future<List<GitHubRepository>> _refreshFollowedRepositoriesNow() async {
    var names = await _readFollowedNames();
    if (names.isEmpty) return const <GitHubRepository>[];

    final resolved = <GitHubRepository>[];
    final unavailable = <String>{};
    Object? firstFailure;
    await Future.wait(names.map((fullName) async {
      try {
        resolved.add(await getRepository(fullName));
      } on GitHubNotFoundException {
        unavailable.add(fullName.toLowerCase());
      } catch (error) {
        firstFailure ??= error;
      }
    }));

    if (unavailable.isNotEmpty) {
      names = names.where((name) => !unavailable.contains(name.toLowerCase())).toList(growable: false);
      await _database.putJson(_followedKey, names);
    }
    if (resolved.isEmpty && names.isNotEmpty && firstFailure != null) {
      throw firstFailure!;
    }
    return sortRepositories(resolved, sort: RepositorySort.updatedDesc);
  }

  Future<GitHubRepository?> getFollowedRepository(String fullName) async {
    final names = await _readFollowedNames();
    final followed = names.any((name) => name.toLowerCase() == fullName.toLowerCase());
    if (!followed) return null;
    return getRepository(fullName);
  }

  Future<GitHubRepository> followRepository(String input) async {
    final fullName = _normalizeRepositoryReference(input);
    final repository = await getRepository(fullName);
    final names = await _readFollowedNames();
    if (!names.any((name) => name.toLowerCase() == repository.fullName.toLowerCase())) {
      names.add(repository.fullName);
      await _database.putJson(_followedKey, names);
    }
    return repository;
  }

  Future<void> unfollowRepository(String fullName) async {
    final names = await _readFollowedNames();
    names.removeWhere((item) => item.toLowerCase() == fullName.toLowerCase());
    await _database.putJson(_followedKey, names);
  }

  static List<String> _referenceParts(String input) {
    var value = input.trim();
    if (value.isEmpty) return const <String>[];

    final uri = Uri.tryParse(value);
    if (uri != null && uri.hasScheme) {
      final host = uri.host.toLowerCase();
      if (host != 'github.com' && host != 'www.github.com') {
        throw const FormatException('Use um link válido do GitHub.');
      }
      value = uri.path;
    }

    value = value.split('?').first.split('#').first;
    value = value.replaceAll(RegExp(r'^/+|/+$'), '');
    if (value.endsWith('.git')) {
      value = value.substring(0, value.length - 4);
    }
    return value
        .split('/')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  static String _normalizeRepositoryReference(String input) {
    final parts = _referenceParts(input);
    if (parts.length != 2) {
      if (parts.length == 1) {
        throw const FormatException(
          'Este link é de um perfil do GitHub. Escolha um repositório dessa conta.',
        );
      }
      throw const FormatException(
        'Informe um repositório como github.com/owner/repo ou owner/repo.',
      );
    }
    return '${parts[0]}/${parts[1]}';
  }

  Future<List<GitHubRepository>> listOwnerRepositoriesFromReference(
    String input,
  ) async {
    final parts = _referenceParts(input);
    if (parts.length != 1) {
      throw const FormatException('Informe somente o perfil do GitHub, como github.com/owner.');
    }
    final owner = parts.single;
    final repositories = <GitHubRepository>[];
    for (var page = 1; page <= 5; page++) {
      final response = await _client.get<List<dynamic>>(
        '/users/$owner/repos',
        queryParameters: {
          'sort': 'pushed',
          'direction': 'desc',
          'per_page': 100,
          'page': page,
        },
      );
      final pageItems = (response.data ?? const <dynamic>[])
          .whereType<Map>()
          .map(
            (json) => GitHubRepository.fromJson(
              Map<String, dynamic>.from(json),
            ),
          )
          .toList(growable: false);
      repositories.addAll(pageItems);
      for (final repository in pageItems) {
        _rememberRepository(repository);
      }
      if (pageItems.length < 100) break;
    }
    return repositories;
  }

  Future<void> _replaceFollowedReference(
    String oldFullName,
    GitHubRepository repository,
  ) async {
    final names = await _readFollowedNames();
    var changed = false;
    for (var i = 0; i < names.length; i++) {
      if (names[i].toLowerCase() == oldFullName.toLowerCase()) {
        names[i] = repository.fullName;
        changed = true;
      }
    }
    if (changed) await _database.putJson(_followedKey, names);
  }

  Future<GitHubRepository> getRepository(String fullName) async {
    final response = await _client.get<Map<String, dynamic>>('/repos/$fullName');
    final repository =
        GitHubRepository.fromJson(response.data ?? const <String, dynamic>{});
    _rememberRepository(repository);
    return repository;
  }

  Future<GitHubRepository> forkRepository(String fullName) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/repos/$fullName/forks',
      data: const {'default_branch_only': false},
    );
    final repository =
        GitHubRepository.fromJson(response.data ?? const <String, dynamic>{});
    return repository;
  }

  static bool _isAmbiguousMutationError(Object error) =>
      error is NetworkRequiredException || error is UnexpectedAppException;

  Future<String?> _currentLogin() async {
    try {
      final response = await _client.get<Map<String, dynamic>>('/user');
      final login = response.data?['login']?.toString().trim();
      return login?.isNotEmpty == true ? login : null;
    } catch (_) {
      return null;
    }
  }

  Future<GitHubRepository?> _confirmRepositoryExists(
    String fullName, {
    int attempts = 4,
  }) async {
    for (var attempt = 0; attempt < attempts; attempt++) {
      try {
        return await getRepository(fullName);
      } on GitHubNotFoundException {
        if (attempt + 1 < attempts) {
          await Future<void>.delayed(const Duration(milliseconds: 700));
        }
      } catch (_) {
        if (attempt + 1 < attempts) {
          await Future<void>.delayed(const Duration(milliseconds: 700));
        }
      }
    }
    return null;
  }

  Future<bool> _confirmRepositoryMissing(
    String fullName, {
    int attempts = 4,
  }) async {
    for (var attempt = 0; attempt < attempts; attempt++) {
      try {
        await getRepository(fullName);
        return false;
      } on GitHubNotFoundException {
        return true;
      } catch (_) {
        if (attempt + 1 < attempts) {
          await Future<void>.delayed(const Duration(milliseconds: 700));
        }
      }
    }
    return false;
  }

  Future<GitHubRepository> createRepository({
    required String name,
    String? description,
    bool isPrivate = false,
    String? homepage,
  }) async {
    final cleanName = name.trim();
    try {
      final response = await _client.post<Map<String, dynamic>>(
        '/user/repos',
        data: {
          'name': cleanName,
          'description': description?.trim() ?? '',
          'private': isPrivate,
          'homepage': homepage?.trim() ?? '',
          'auto_init': true,
        },
      );
      final repository = GitHubRepository.fromJson(response.data ?? const {});
      _rememberRepository(repository);
      return repository;
    } catch (error) {
      if (_isAmbiguousMutationError(error)) {
        final login = await _currentLogin();
        if (login != null) {
          final confirmed = await _confirmRepositoryExists('$login/$cleanName');
          if (confirmed != null) {
            return confirmed;
          }
        }
      }
      rethrow;
    }
  }

  Future<GitHubRepository> updateRepository({
    required String fullName,
    required String name,
    required String description,
    required bool isPrivate,
    required bool isArchived,
    String? homepage,
  }) async {
    final cleanName = name.trim();
    final owner = fullName.split('/').first;
    final targetFullName = '$owner/$cleanName';
    try {
      final response = await _client.patch<Map<String, dynamic>>(
        '/repos/$fullName',
        data: {
          'name': cleanName,
          'description': description.trim(),
          'private': isPrivate,
          'archived': isArchived,
          'homepage': homepage?.trim() ?? '',
        },
      );
      final repository = GitHubRepository.fromJson(response.data ?? const {});
      if (repository.fullName.toLowerCase() != fullName.toLowerCase()) {
        await _replaceFollowedReference(fullName, repository);
      }
      await _database.updateFavoriteRepositoryName(
        repository.id,
        repository.fullName,
      );
      _repositoryCache.remove(fullName.toLowerCase());
      _rememberRepository(repository);
      return repository;
    } catch (error) {
      if (_isAmbiguousMutationError(error)) {
        final confirmed = await _confirmRepositoryExists(targetFullName);
        if (confirmed != null) {
          if (confirmed.fullName.toLowerCase() != fullName.toLowerCase()) {
            await _replaceFollowedReference(fullName, confirmed);
          }
          await _database.updateFavoriteRepositoryName(
            confirmed.id,
            confirmed.fullName,
          );
          return confirmed;
        }
      }
      rethrow;
    }
  }

  Future<GitHubRepository> renameRepository({
    required String fullName,
    required String newName,
  }) async {
    final cleanName = RepositoryNameRules.normalize(newName);
    final validationError = RepositoryNameRules.validate(cleanName);
    if (validationError != null) {
      throw FormatException(validationError);
    }
    final oldName = fullName.split('/').last;
    if (!RepositoryNameRules.isChanged(oldName, cleanName)) {
      throw const FormatException('Informe um nome diferente do atual.');
    }
    final owner = fullName.split('/').first;
    final targetFullName = '$owner/$cleanName';

    if (targetFullName.toLowerCase() != fullName.toLowerCase()) {
      try {
        await getRepository(targetFullName);
        throw const FormatException(
          'Já existe um repositório com esse nome nesta conta.',
        );
      } on GitHubNotFoundException {
        // O destino está disponível; prossegue com o rename.
      } on FormatException {
        rethrow;
      } catch (_) {
        // Falha ao verificar disponibilidade não bloqueia a tentativa real.
        // O PATCH do GitHub continua sendo a fonte final de verdade.
      }
    }
    try {
      final response = await _client.patch<Map<String, dynamic>>(
        '/repos/$fullName',
        data: {'name': cleanName},
      );
      final repository = GitHubRepository.fromJson(response.data ?? const {});
      await _replaceFollowedReference(fullName, repository);
      await _database.updateFavoriteRepositoryName(
        repository.id,
        repository.fullName,
      );
      _repositoryCache.remove(fullName.toLowerCase());
      _rememberRepository(repository);
      return repository;
    } catch (error) {
      if (_isAmbiguousMutationError(error)) {
        final confirmed = await _confirmRepositoryExists(targetFullName);
        if (confirmed != null) {
          await _replaceFollowedReference(fullName, confirmed);
          await _database.updateFavoriteRepositoryName(
            confirmed.id,
            confirmed.fullName,
          );
          return confirmed;
        }
      }
      rethrow;
    }
  }

  Future<void> deleteRepository(String fullName) async {
    try {
      await _client.delete<void>('/repos/$fullName');
    } on GitHubNotFoundException {
      // Estado final desejado já foi alcançado.
    } catch (error) {
      if (!_isAmbiguousMutationError(error) ||
          !await _confirmRepositoryMissing(fullName)) {
        rethrow;
      }
    }
    _repositoryCache.remove(fullName.toLowerCase());
    await unfollowRepository(fullName);
    await _database.removeFavoriteRepositoryByFullName(fullName);
  }


}
