import 'package:dio/dio.dart';
import 'package:github_manager/core/network/github_api_client.dart';

const selfUpdateRepository = 'drilemoz/GitHub-Manager';
const selfUpdatePackage = 'br.com.githubmanager.app';

class SelfUpdateRelease {
  const SelfUpdateRelease({required this.version, required this.code,
    required this.assetId, required this.fileName, required this.url,
    required this.authenticated});

  final String version;
  final int code;
  final int assetId;
  final String fileName;
  final String url;
  final bool authenticated;

  /// Somente releases estáveis com o APK universal oficial e tag correspondente.
  static SelfUpdateRelease? select(List<dynamic> releases, int installedCode,
      {required bool authenticated}) {
    SelfUpdateRelease? best;
    final pattern = RegExp(r'^GitHub-Manager-(\d+\.\d+\.\d+)-(\d+)-universal-release\.apk$');
    for (final release in releases) {
      if (release is! Map || release['draft'] != false ||
          release['prerelease'] != false || release['assets'] is! List) {
        continue;
      }
      for (final asset in release['assets'] as List) {
        if (asset is! Map || asset['state'] != 'uploaded') continue;
        final name = asset['name'];
        if (name is! String) continue;
        final match = pattern.firstMatch(name);
        if (match == null) continue;
        final version = match.group(1)!;
        final code = int.tryParse(match.group(2)!);
        final id = asset['id'];
        final url = asset['browser_download_url'];
        final expected = 'https://github.com/$selfUpdateRepository/releases/download/v$version/$name';
        if (code == null || code <= installedCode ||
            (best != null && code <= best.code) ||
            release['tag_name'] != 'v$version' || id is! int || id <= 0 ||
            asset['size'] is! num || (asset['size'] as num) <= 0 ||
            url is! String || url.toLowerCase() != expected.toLowerCase()) {
          continue;
        }
        best = SelfUpdateRelease(version: version, code: code, assetId: id,
          fileName: name, url: url, authenticated: authenticated);
      }
    }
    return best;
  }
}

class SelfUpdateService {
  SelfUpdateService(this._client);
  final GitHubApiClient _client;

  Future<SelfUpdateRelease?> check(int installedCode) async {
    const path = '/repos/$selfUpdateRepository/releases';
    const query = <String, dynamic>{'per_page': 100};
    final public = Dio(BaseOptions(
      baseUrl: 'https://api.github.com',
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 12),
      headers: const {'Accept': 'application/vnd.github+json'},
    ));
    try {
      final response = await public.get<List<dynamic>>(path, queryParameters: query);
      return SelfUpdateRelease.select(response.data ?? [], installedCode,
          authenticated: false);
    } on DioException {
      // Repositório privado ou limite público: reutiliza o token já salvo.
      final response = await _client.get<List<dynamic>>(path, queryParameters: query)
          .timeout(const Duration(seconds: 15));
      return SelfUpdateRelease.select(response.data ?? [], installedCode,
          authenticated: true);
    } finally {
      public.close();
    }
  }
}
