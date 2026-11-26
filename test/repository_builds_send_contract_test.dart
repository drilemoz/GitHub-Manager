import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('builds reutiliza envio ZIP e branch atual, sem abrir central de envios', () {
    final screen = File('lib/features/repositories/presentation/repository_actions_screen.dart').readAsStringSync();
    final detail = File('lib/features/repositories/presentation/repository_detail_screen_actions.dart').readAsStringSync();
    final controls = File('lib/features/repositories/presentation/repository_actions_widgets.dart').readAsStringSync();
    expect(screen, contains('RepositoryProjectSendFlow<RepositoryActionsScreen>'));
    expect(screen, contains('if (widget.readOnly || _sendingProject) return;'));
    expect(screen, contains('await sendProject(repository, initialBranchName: branch)'));
    expect(screen, contains('onSend: _sendFromBuilds'));
    expect(detail, contains('mixin RepositoryProjectSendFlow'));
    expect(detail, contains('await _chooseUploadBranch(repository, initialBranchName: initialBranchName)'));
    expect(detail, contains('await _prepareUpload('));
    expect(detail, contains('await _confirmZip('));
    expect(controls, contains("ValueKey('repository-build-send')"));
    expect(controls, contains('Icons.cloud_upload_outlined'));
    expect(controls, contains('sending || starting ? null : onSend'));
  });

  test('menu compacto preserva ações e botões adaptam largura', () {
    final controls = File('lib/features/repositories/presentation/repository_actions_widgets.dart').readAsStringSync();
    for (final action in ['artifacts', 'diagnostics', 'permissions', 'storage', 'select']) {
      expect(controls, contains('case _BuildMenuAction.$action:'));
    }
    expect(controls, contains('constraints.maxWidth < 310'));
    expect(controls, contains('MediaQuery.textScalerOf(context)'));
  });
}
