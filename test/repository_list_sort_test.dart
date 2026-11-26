import 'package:flutter_test/flutter_test.dart';
import 'package:github_manager/features/repositories/domain/github_repository.dart';
import 'package:github_manager/features/repositories/domain/repository_list_sort.dart';

void main() {
  GitHubRepository repository({
    required int id,
    required String name,
    required int sizeKb,
    required DateTime updatedAt,
    DateTime? pushedAt,
  }) =>
      GitHubRepository(
        id: id,
        name: name,
        fullName: 'owner/$name',
        isPrivate: false,
        isArchived: false,
        defaultBranch: 'main',
        updatedAt: updatedAt,
        pushedAt: pushedAt,
        htmlUrl: 'https://github.com/owner/$name',
        sizeKb: sizeKb,
      );

  final alpha = repository(
    id: 1,
    name: 'alpha',
    sizeKb: 100,
    updatedAt: DateTime.utc(2026, 9, 10),
  );
  final beta = repository(
    id: 2,
    name: 'beta',
    sizeKb: 900,
    updatedAt: DateTime.utc(2026, 9, 12),
  );
  final gamma = repository(
    id: 3,
    name: 'gamma',
    sizeKb: 400,
    updatedAt: DateTime.utc(2026, 9, 11),
  );

  test('fixed repositories stay before normal sorting', () {
    final result = sortRepositories(
      [alpha, beta, gamma],
      sort: RepositorySort.sizeDesc,
      favoriteIds: {alpha.id},
    );

    expect(result.map((item) => item.id), [alpha.id, beta.id, gamma.id]);
  });

  test('push date wins over metadata changes while pins stay first', () {
    final olderPush = repository(
      id: 4, name: 'older-push', sizeKb: 1,
      updatedAt: DateTime.utc(2026, 11, 25),
      pushedAt: DateTime.utc(2026, 11, 20),
    );
    final newerPush = repository(
      id: 5, name: 'newer-push', sizeKb: 1,
      updatedAt: DateTime.utc(2026, 11, 21),
      pushedAt: DateTime.utc(2026, 11, 24),
    );
    final fallback = repository(
      id: 6, name: 'fallback', sizeKb: 1,
      updatedAt: DateTime.utc(2026, 11, 22),
    );
    final source = [olderPush, newerPush, alpha, fallback];
    expect(
      sortRepositories(source, sort: RepositorySort.updatedDesc,
          favoriteIds: {alpha.id}).map((item) => item.id),
      [1, 5, 6, 4],
    );
    expect(
      sortRepositories(source, sort: RepositorySort.updatedAsc,
          favoriteIds: {alpha.id}).map((item) => item.id),
      [1, 4, 6, 5],
    );
    expect(source.map((item) => item.id), [4, 5, 1, 6]);
  });

  test('size sorting works in both directions', () {
    expect(
      sortRepositories(
        [alpha, beta, gamma],
        sort: RepositorySort.sizeDesc,
      ).map((item) => item.id),
      [beta.id, gamma.id, alpha.id],
    );
    expect(
      sortRepositories(
        [alpha, beta, gamma],
        sort: RepositorySort.sizeAsc,
      ).map((item) => item.id),
      [alpha.id, gamma.id, beta.id],
    );
  });

  test('recent sorting keeps newest first', () {
    final result = sortRepositories(
      [alpha, beta, gamma],
      sort: RepositorySort.updatedDesc,
    );

    expect(result.map((item) => item.id), [beta.id, gamma.id, alpha.id]);
  });
}
