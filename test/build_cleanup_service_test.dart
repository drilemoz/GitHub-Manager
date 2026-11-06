import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:github_manager/core/network/github_api_client.dart';
import 'package:github_manager/core/security/secure_storage_service.dart';
import 'package:github_manager/features/builds/data/artifact_service.dart';
import 'package:github_manager/features/builds/data/build_cleanup_service.dart';
import 'package:github_manager/features/builds/domain/action_artifact.dart';
import 'package:github_manager/features/builds/domain/release_asset.dart';
import 'package:github_manager/features/repositories/domain/repository_git_models.dart';

void main() {
  RepositoryWorkflowRun run({int id = 77}) => RepositoryWorkflowRun.fromJson({
        'id': id,
        'workflow_id': 10,
        'path': '.github/workflows/android-apk.yml',
        'name': 'Android APK',
        'display_title': 'Release v2.0.70',
        'status': 'completed',
        'conclusion': 'success',
        'head_branch': 'main',
        'head_sha': 'abc1234567890',
        'run_number': 70,
        'run_attempt': 1,
      });

  test('deleting build preserves Release APK even with same SHA', () async {
    final events = <String>[];
    final client = _FakeGitHubApiClient(events);
    final artifacts = _FakeArtifactService(client, events)
      ..runArtifacts = const [
        ActionArtifact(
          id: 501,
          name: 'android-apk-2.0.70',
          sizeBytes: 100,
          expired: false,
          createdAt: null,
          workflowRunId: 77,
          workflowRunHeadSha: 'abc1234567890',
        ),
      ]
      ..releaseApks = const [
        ReleaseAsset(
          id: 601,
          name: 'app-release.apk',
          sizeBytes: 200,
          downloadUrl: '',
          tagName: 'v2.0.70',
          publishedAt: null,
          releaseId: 701,
          releaseName: 'Version 2.0.70',
          targetCommitish: 'abc1234567890',
        ),
      ];

    final result = await BuildCleanupService(client, artifacts).deleteBuild(
      repositoryFullName: 'owner/repo',
      run: run(),
    );

    expect(result.artifactsRemoved, 1);
    expect(result.releaseApksRemoved, 0);
    expect(result.hasWarnings, isFalse);
    expect(events, contains('delete-run:77'));
    expect(events, isNot(contains('delete-release-asset:601')));
  });

  test('remaining artifact after run deletion is deleted explicitly', () async {
    final events = <String>[];
    final client = _FakeGitHubApiClient(events);
    const leftover = ActionArtifact(
      id: 999,
      name: 'android-apk-old',
      sizeBytes: 100,
      expired: false,
      createdAt: null,
      workflowRunId: 77,
    );
    final artifacts = _FakeArtifactService(client, events)
      ..runArtifacts = const [leftover]
      ..repositoryArtifactsAfterRunDelete = const [leftover];

    final result = await BuildCleanupService(client, artifacts).deleteBuild(
      repositoryFullName: 'owner/repo',
      run: run(),
    );

    expect(result.artifactsRemoved, 1);
    expect(events, contains('delete-artifact:999'));
  });

  test('verifies by ID without scanning the entire repository', () async {
    final events = <String>[];
    final client = _FakeGitHubApiClient(events);
    final artifacts = _FakeArtifactService(client, events)
      ..runArtifacts = const [
        ActionArtifact(id: 51, name: 'app-apk', sizeBytes: 44,
          expired: false, createdAt: null, workflowRunId: 77),
      ];
    final result = await BuildCleanupService(client, artifacts).deleteBuild(
      repositoryFullName: 'owner/repo', run: run(),
    );
    expect(result.artifactsRemoved, 1);
    expect(artifacts.repositoryScanCalls, 0);
    expect(events, contains('get-artifact:51'));
  });

  test('reports unverifiable artifacts when initial inventory fails', () async {
    final events = <String>[];
    final client = _FakeGitHubApiClient(events);
    final artifacts = _FakeArtifactService(client, events)..failInventory = true;
    final result = await BuildCleanupService(client, artifacts).deleteBuild(
      repositoryFullName: 'owner/repo', run: run(),
    );
    expect(events, contains('delete-run:77'));
    expect(result.artifactsRemoved, 0);
    expect(result.hasWarnings, isTrue);
    expect(artifacts.repositoryScanCalls, 0);
  });

  test('does not claim cleanup after verification failure', () async {
    final events = <String>[];
    final client = _FakeGitHubApiClient(events);
    final artifacts = _FakeArtifactService(client, events)
      ..runArtifacts = const [
        ActionArtifact(id: 52, name: 'apk', sizeBytes: 120,
          expired: false, createdAt: null, workflowRunId: 77),
      ]
      ..failVerification = true;
    final result = await BuildCleanupService(client, artifacts).deleteBuild(
      repositoryFullName: 'owner/repo', run: run(),
    );
    expect(result.artifactsRemoved, 0);
    expect(result.hasWarnings, isTrue);
  });

  test('bulk cleanup reports determinate progress from 0 to 100 percent', () async {
    final events = <String>[];
    final client = _FakeGitHubApiClient(events);
    final artifacts = _FakeArtifactService(client, events);
    final progress = <BuildCleanupProgress>[];

    final result = await BuildCleanupService(client, artifacts).deleteBuilds(
      repositoryFullName: 'owner/repo',
      runs: [run(id: 77), run(id: 78)],
      onProgress: progress.add,
    );

    expect(result.deletedCount, 2);
    expect(progress, isNotEmpty);
    expect(progress.first.percent, 0);
    expect(progress.last.percent, 100);
    expect(progress.last.current, 2);
    expect(progress.last.total, 2);
    expect(
      progress.map((item) => item.stage),
      contains(BuildCleanupStage.deletingRun),
    );
  });
}

class _FakeGitHubApiClient extends GitHubApiClient {
  _FakeGitHubApiClient(this.events) : super(SecureStorageService());

  final List<String> events;

  @override
  Future<Response<T>> delete<T>(
    String path, {
    Object? data,
    CancelToken? cancelToken,
  }) async {
    final match = RegExp(r'/actions/runs/(\d+)$').firstMatch(path);
    if (match != null) events.add('delete-run:${match.group(1)}');
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      statusCode: 204,
    );
  }
}

class _FakeArtifactService extends ArtifactService {
  _FakeArtifactService(GitHubApiClient client, this.events) : super(client);

  final List<String> events;
  List<ActionArtifact> runArtifacts = const [];
  List<ActionArtifact> repositoryArtifactsAfterRunDelete = const [];
  List<ReleaseAsset> releaseApks = const [];
  bool failInventory = false;
  bool failVerification = false;
  int repositoryScanCalls = 0;

  @override
  Future<List<ActionArtifact>> listArtifactsForRun({
    required String repositoryFullName,
    required int runId,
  }) async {
    if (failInventory) throw StateError('sem autorização para listar');
    return runArtifacts;
  }

  @override
  Future<ActionArtifact?> getArtifactById({
    required String repositoryFullName,
    required int artifactId,
  }) async {
    events.add('get-artifact:$artifactId');
    if (failVerification) throw StateError('conexão caiu');
    for (final artifact in repositoryArtifactsAfterRunDelete) {
      if (artifact.id == artifactId) return artifact;
    }
    return null;
  }

  @override
  Future<List<ActionArtifact>> listArtifacts(String repositoryFullName) async {
    repositoryScanCalls++;
    return repositoryArtifactsAfterRunDelete;
  }

  @override
  Future<List<ReleaseAsset>> findReleaseApksForBuild({
    required String repositoryFullName,
    required RepositoryWorkflowRun run,
  }) async =>
      releaseApks;

  @override
  Future<void> deleteArtifact({
    required String repositoryFullName,
    required int artifactId,
  }) async {
    events.add('delete-artifact:$artifactId');
    repositoryArtifactsAfterRunDelete = repositoryArtifactsAfterRunDelete
        .where((artifact) => artifact.id != artifactId)
        .toList(growable: false);
  }

  @override
  Future<void> deleteReleaseAsset({
    required String repositoryFullName,
    required int assetId,
  }) async {
    events.add('delete-release-asset:$assetId');
  }
}
