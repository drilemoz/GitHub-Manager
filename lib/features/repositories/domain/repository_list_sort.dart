import 'package:github_manager/features/repositories/domain/github_repository.dart';

enum RepositorySort {
  updatedDesc('Mais recentes'),
  updatedAsc('Mais antigos'),
  nameAsc('Nome A–Z'),
  sizeDesc('Maiores'),
  sizeAsc('Menores');

  const RepositorySort(this.label);
  final String label;
}

List<GitHubRepository> sortRepositories(
  Iterable<GitHubRepository> source, {
  required RepositorySort sort,
  Set<int> favoriteIds = const <int>{},
}) {
  final items = source.toList(growable: false);
  items.sort((a, b) {
    final favoriteOrder = _favoriteOrder(a, b, favoriteIds);
    if (favoriteOrder != 0) return favoriteOrder;

    final result = switch (sort) {
      RepositorySort.updatedDesc => _compareCodeActivity(b, a),
      RepositorySort.updatedAsc => _compareCodeActivity(a, b),
      RepositorySort.nameAsc => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      RepositorySort.sizeDesc => b.sizeKb.compareTo(a.sizeKb),
      RepositorySort.sizeAsc => a.sizeKb.compareTo(b.sizeKb),
    };
    if (result != 0) return result;
    final nameOrder = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    if (nameOrder != 0) return nameOrder;
    return a.id.compareTo(b.id);
  });
  return items;
}

int _favoriteOrder(
  GitHubRepository a,
  GitHubRepository b,
  Set<int> favoriteIds,
) {
  final aFavorite = favoriteIds.contains(a.id);
  final bFavorite = favoriteIds.contains(b.id);
  if (aFavorite == bFavorite) return 0;
  return aFavorite ? -1 : 1;
}

int _compareCodeActivity(GitHubRepository a, GitHubRepository b) {
  final aValue = a.lastCodeActivityAt ?? DateTime.fromMillisecondsSinceEpoch(0);
  final bValue = b.lastCodeActivityAt ?? DateTime.fromMillisecondsSinceEpoch(0);
  return aValue.compareTo(bValue);
}
