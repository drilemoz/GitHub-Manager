import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:github_manager/features/repositories/domain/github_repository.dart';
import 'package:github_manager/features/repositories/presentation/repository_card.dart';
import 'package:github_manager/features/repositories/presentation/repository_providers.dart';

void main() {
  for (final isPrivate in [true, false]) {
    testWidgets('card mostra visibilidade privada=$isPrivate', (tester) async {
      final repository = GitHubRepository.fromJson({
        'id': 1,
        'name': 'Projeto',
        'full_name': 'owner/Projeto',
        'private': isPrivate,
        'size': 2048,
      });
      await tester.pumpWidget(ProviderScope(
        overrides: [
          showRepositoryDescriptionsProvider.overrideWith((ref) async => false),
        ],
        child: MaterialApp(
          home: Scaffold(body: RepositoryCard(repository: repository, readOnly: true)),
        ),
      ));
      await tester.pumpAndSettle();
      final title = tester.widget<RichText>(find.descendant(
        of: find.byType(RepositoryCard),
        matching: find.byWidgetPredicate((widget) =>
            widget is RichText && widget.text.toPlainText().startsWith('Projeto')),
      ));
      expect(title.text.toPlainText(),
          'Projeto  •  2 MB  •  ${isPrivate ? 'Privado' : 'Público'}');
    });
  }
}
