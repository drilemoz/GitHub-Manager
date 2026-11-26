import 'package:flutter_test/flutter_test.dart';
import 'package:github_manager/features/repositories/domain/github_repository.dart';

void main() {
  test('GitHubRepository parses core REST fields', () {
    final repository = GitHubRepository.fromJson({
      'id': 42,
      'name': 'github-manager',
      'full_name': 'owner/github-manager',
      'private': true,
      'archived': false,
      'default_branch': 'main',
      'language': 'Dart',
      'updated_at': '2026-08-26T08:00:00Z',
      'pushed_at': '2026-08-25T09:00:00Z',
      'html_url': 'https://github.com/owner/github-manager',
      'size': 18842,
    });

    expect(repository.id, 42);
    expect(repository.isPrivate, isTrue);
    expect(repository.defaultBranch, 'main');
    expect(repository.language, 'Dart');
    expect(repository.sizeKb, 18842);
    expect(repository.toJson()['size'], 18842);
    expect(repository.pushedAt, DateTime.utc(2026, 8, 25, 9));
    expect(repository.lastCodeActivityAt, repository.pushedAt);
    expect(GitHubRepository.fromJson(repository.toJson()), repository);
  });


  test('GitHubRepository uses value equality for provider/cache keys', () {
    final json = {
      'id': 42,
      'name': 'github-manager',
      'full_name': 'owner/github-manager',
      'description': 'Descrição atual',
      'private': false,
      'archived': false,
      'default_branch': 'main',
      'language': 'Dart',
      'updated_at': '2026-08-30T22:00:00Z',
      'html_url': 'https://github.com/owner/github-manager',
    };
    final first = GitHubRepository.fromJson(json);
    final second = GitHubRepository.fromJson(Map<String, dynamic>.from(json));
    final changed = GitHubRepository.fromJson({
      ...json,
      'description': 'Descrição nova',
      'updated_at': '2026-08-30T22:01:00Z',
    });

    expect(first, second);
    expect(first.hashCode, second.hashCode);
    expect(first == changed, isFalse);
    expect(first.lastCodeActivityAt, first.updatedAt);
    final pushed = GitHubRepository.fromJson({
      ...json,
      'pushed_at': '2026-08-31T00:00:00Z',
    });
    expect(pushed, isNot(first));
    expect(pushed.lastCodeActivityAt, DateTime.utc(2026, 8, 31));
  });

}
