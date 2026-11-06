import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:github_manager/core/network/github_api_client.dart';
import 'package:github_manager/core/errors/app_exception.dart';
import 'package:github_manager/core/security/secure_storage_service.dart';
import 'package:github_manager/features/builds/data/actions_storage_service.dart';
import 'package:github_manager/features/builds/data/artifact_service.dart';
import 'package:github_manager/features/builds/domain/action_artifact.dart';

void main() {
  const apkArtifact = ActionArtifact(
    id: 11,
    name: 'android-apk',
    sizeBytes: 1024 * 1024,
    expired: false,
    createdAt: null,
    workflowRunId: 42,
  );
  const logsArtifact = ActionArtifact(
    id: 12,
    name: 'test-logs',
    sizeBytes: 32,
    expired: false,
    createdAt: null,
    workflowRunId: 42,
  );

  test('deletes only selected artifact and verifies by querying the API', () async {
    final client = _FakeClient();
    final artifacts = _FakeArtifacts(client)..items = [apkArtifact, logsArtifact];
    final progress = <int>[];
    final report = await ActionsStorageService(client, artifacts).deleteSelected(
      repository: 'owner/repo',
      artifactIds: [11, 11],
      onProgress: (done, _) => progress.add(done),
    );
    expect(report.verified, isTrue);
    expect(report.acceptedIds, {11});
    expect(report.absentIds, {11});
    expect(report.deletedIds, {11});
    expect(report.failedIds, isEmpty);
    expect(progress, [1]);
    expect(artifacts.items.map((a) => a.id).toList(), [12]);
    expect(artifacts.deleted, [11]);
  });

  test('does not assert verification if GitHub list fails after DELETE', () async {
    final client = _FakeClient();
    final artifacts = _FakeArtifacts(client)
      ..items = [apkArtifact]
      ..failListing = true;
    final report = await ActionsStorageService(client, artifacts).deleteSelected(
      repository: 'owner/repo',
      artifactIds: [11],
    );
    expect(report.verified, isFalse);
    expect(report.acceptedIds, {11});
    expect(report.absentIds, isEmpty); // Não inventa ausência sem consultar.
    expect(report.hasUnresolved, isTrue);
  });

  test('reports still-visible artifact as unresolved', () async {
    final client = _FakeClient();
    final artifacts = _FakeArtifacts(client)
      ..items = [apkArtifact]
      ..ignoreDelete = true;
    final report = await ActionsStorageService(client, artifacts).deleteSelected(
      repository: 'owner/repo',
      artifactIds: [11],
    );
    expect(report.verified, isTrue);
    expect(report.remainingIds, {11});
    expect(report.deletedIds, isEmpty);
    expect(report.hasUnresolved, isTrue);
  });

  test('HTTP 404 is already absent, not a successful DELETE', () async {
    final client = _FakeClient();
    final artifacts = _FakeArtifacts(client)..notFoundIds.add(11);
    final report = await ActionsStorageService(client, artifacts).deleteSelected(
      repository: 'owner/repo', artifactIds: [11],
    );
    expect(report.acceptedIds, isEmpty);
    expect(report.alreadyAbsentIds, {11});
    expect(report.absentIds, {11});
    expect(report.deletedIds, isEmpty);
    expect(report.hasUnresolved, isFalse);
  });

  test('failed DELETE remains unresolved while ID is still present', () async {
    final client = _FakeClient();
    final artifacts = _FakeArtifacts(client)
      ..items = [apkArtifact]
      ..permissionDenied = true;
    final report = await ActionsStorageService(client, artifacts).deleteSelected(
      repository: 'owner/repo', artifactIds: [11],
    );
    expect(report.verified, isTrue);
    expect(report.acceptedIds, isEmpty);
    expect(report.requestFailedIds, {11});
    expect(report.remainingIds, {11});
  });

  test('invalid IDs are skipped without sending a DELETE', () async {
    final client = _FakeClient();
    final artifacts = _FakeArtifacts(client);
    final report = await ActionsStorageService(client, artifacts).deleteSelected(
      repository: 'owner/repo', artifactIds: [-2, 0],
    );
    expect(report.requestedIds, isEmpty);
    expect(artifacts.deleted, isEmpty);
  });

  test('retries a stale listing once and then confirms absence', () async {
    final client = _FakeClient();
    final artifacts = _FakeArtifacts(client)
      ..items = [apkArtifact]
      ..staleReadAfterDelete = true;
    final report = await ActionsStorageService(client, artifacts).deleteSelected(
      repository: 'owner/repo', artifactIds: [11],
    );
    expect(report.verified, isTrue);
    expect(report.absentIds, {11});
    expect(artifacts.listCalls, 2);
  });

  test('reads billing usage as report without converting it to quota', () async {
    final client = _FakeClient();
    final items = await ActionsStorageService(client, _FakeArtifacts(client))
        .billingUsageThisMonth();
    expect(items, hasLength(1));
    expect(items.single.sku, 'actions_storage');
    expect(items.single.unit, 'GB-hours');
    expect(items.single.quantity, 18.5);
    expect(client.paths, contains('/user'));
    expect(client.paths.any((url) => url.contains('/settings/billing/usage/summary')), isTrue);
  });
}

class _FakeClient extends GitHubApiClient {
  _FakeClient() : super(SecureStorageService());
  final paths = <String>[];

  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
  }) async {
    paths.add(path);
    final result = path == '/user'
        ? <String, dynamic>{'login': 'owner'}
        : <String, dynamic>{
            'usageItems': [
              {'sku': 'actions_storage', 'unitType': 'GB-hours', 'grossQuantity': 18.5}
            ],
          };
    return Response<T>(
      data: result as T,
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
    );
  }
}

class _FakeArtifacts extends ArtifactService {
  _FakeArtifacts(GitHubApiClient client) : super(client);
  List<ActionArtifact> items = [];
  final deleted = <int>[];
  bool failListing = false;
  bool ignoreDelete = false;
  bool permissionDenied = false;
  bool staleReadAfterDelete = false;
  final Set<int> notFoundIds = <int>{};
  int listCalls = 0;
  List<ActionArtifact> staleSnapshot = [];

  @override
  Future<List<ActionArtifact>> listArtifacts(String repositoryFullName) async {
    if (failListing) throw StateError('sem conexão');
    listCalls++;
    if (staleReadAfterDelete && listCalls == 1) return staleSnapshot;
    return items.toList();
  }

  @override
  Future<void> deleteArtifact({
    required String repositoryFullName,
    required int artifactId,
  }) async {
    deleted.add(artifactId);
    if (notFoundIds.contains(artifactId)) {
      throw const GitHubNotFoundException(httpStatus: 404);
    }
    if (permissionDenied) {
      throw const GitHubPermissionException(httpStatus: 403);
    }
    if (staleReadAfterDelete) staleSnapshot = items.toList();
    if (!ignoreDelete) items.removeWhere((item) => item.id == artifactId);
  }
}
