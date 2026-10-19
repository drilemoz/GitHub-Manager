class RepositoryProjectInfo {
  const RepositoryProjectInfo({
    required this.projectName,
    required this.version,
    required this.technologies,
    this.packageName,
    this.applicationId,
    this.versionCode,
    this.minSdk,
    this.targetSdk,
    this.compileSdk,
    this.versionSource,
    this.nameSource,
    this.metadataIssue,
  });

  final String projectName;
  final String? version;
  final List<String> technologies;
  final String? packageName;
  final String? applicationId;
  final int? versionCode;
  final int? minSdk;
  final int? targetSdk;
  final int? compileSdk;
  final String? versionSource;
  /// Fonte do nome exibido; quando ausente, foi usado o nome do GitHub.
  final String? nameSource;
  /// Falha de consulta distinta de metadados simplesmente ausentes.
  final String? metadataIssue;

  String? get versionLabel {
    final value = version?.trim();
    if (value == null || value.isEmpty) return null;
    if (versionCode == null || value.contains('+')) return value;
    return '$value+$versionCode';
  }

  String? get displayVersionLabel {
    final value = versionLabel;
    if (value == null) return null;
    final source = versionSource?.trim();
    return source == null || source.isEmpty ? value : '$value • $source';
  }


  String get sdkLabel {
    final parts = <String>[];
    if (targetSdk != null) parts.add('target $targetSdk');
    if (minSdk != null) parts.add('min $minSdk');
    if (compileSdk != null) parts.add('compile $compileSdk');
    return parts.isEmpty ? 'SDK não identificado' : parts.join(' • ');
  }

  String get technologiesLabel =>
      technologies.isEmpty ? 'Tecnologia não identificada' : technologies.join(' • ');
}
