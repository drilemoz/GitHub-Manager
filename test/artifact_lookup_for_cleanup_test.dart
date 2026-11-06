import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:github_manager/core/errors/app_exception.dart';
import 'package:github_manager/core/network/github_api_client.dart';
import 'package:github_manager/core/security/secure_storage_service.dart';
import 'package:github_manager/features/builds/data/artifact_service.dart';

void main() {
  test('single-artifact lookup uses GitHub endpoint and parses metadata', () async {
    final client = _LookupClient();
    final result = await ArtifactService(client).getArtifactById(
      repositoryFullName: 'owner/repo', artifactId: 123,
    );
    expect(result?.id, 123);
    expect(result?.name, 'android-apk');
    expect(client.paths, ['/repos/owner/repo/actions/artifacts/123']);
  });

  test('invalid artifact collection response is never treated as empty', () async {
    await expectLater(
      ArtifactService(_InvalidListingClient()).listArtifacts('owner/repo'),
      throwsFormatException,
    );
  });

  test('404 is treated as absent but 403 is not', () async {
    final client = _LookupClient()..notFound = true;
    expect(await ArtifactService(client).getArtifactById(
      repositoryFullName: 'owner/repo', artifactId: 12,
    ), isNull);
    client.notFound = false;
    client.permissionDenied = true;
    await expectLater(
      ArtifactService(client).getArtifactById(
        repositoryFullName: 'owner/repo', artifactId: 12,
      ),
      throwsA(isA<GitHubPermissionException>()),
    );
  });
}

class _LookupClient extends GitHubApiClient {
  _LookupClient() : super(SecureStorageService());
  final List<String> paths = [];
  bool notFound = false;
  bool permissionDenied = false;

  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
  }) async {
    paths.add(path);
    if (notFound) throw const GitHubNotFoundException(httpStatus: 404);
    if (permissionDenied) throw const GitHubPermissionException(httpStatus: 403);
    return Response<T>(
      statusCode: 200,
      requestOptions: RequestOptions(path: path),
      data: <String, dynamic>{
        'id': 123,
        'name': 'android-apk',
        'size_in_bytes': 2048,
        'expired': false,
        'workflow_run': {'id': 77},
      } as T,
    );
  }
}

// A listagem é usada para afirmar ausência após DELETE. Um JSON inválido
// nunca pode ser interpretado como uma lista vazia de artifacts.
class _InvalidListingClient extends GitHubApiClient {
  _InvalidListingClient() : super(SecureStorageService());

  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
  }) async => Response<T>(
    statusCode: 200,
    requestOptions: RequestOptions(path: path),
    data: <String, dynamic>{'unexpected': []} as T,
  );
}
