class GitHubRepository {
  const GitHubRepository({
    required this.id,
    required this.name,
    required this.fullName,
    required this.isPrivate,
    required this.isArchived,
    required this.defaultBranch,
    required this.updatedAt,
    this.pushedAt,
    required this.htmlUrl,
    this.sizeKb = 0,
    this.description,
    this.language,
    this.homepage,
  });

  final int id;
  final String name;
  final String fullName;
  final String? description;
  final bool isPrivate;
  final bool isArchived;
  final String defaultBranch;
  final String? language;
  final String? homepage;
  final DateTime? updatedAt;
  final DateTime? pushedAt;

  /// Último push; updatedAt é fallback para respostas antigas ou incompletas.
  DateTime? get lastCodeActivityAt => pushedAt ?? updatedAt;
  final String htmlUrl;
  /// Repository size reported by the GitHub REST API, in kilobytes.
  final int sizeKb;

  factory GitHubRepository.fromJson(Map<String, dynamic> json) => GitHubRepository(
        id: (json['id'] as num?)?.toInt() ?? 0,
        name: json['name'] as String? ?? '',
        fullName: json['full_name'] as String? ?? '',
        description: json['description'] as String?,
        isPrivate: json['private'] as bool? ?? false,
        isArchived: json['archived'] as bool? ?? false,
        defaultBranch: json['default_branch'] as String? ?? 'main',
        language: json['language'] as String?,
        homepage: json['homepage'] as String?,
        updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? ''),
        pushedAt: DateTime.tryParse(json['pushed_at'] as String? ?? ''),
        htmlUrl: json['html_url'] as String? ?? '',
        sizeKb: (json['size'] as num?)?.toInt() ?? 0,
      );


  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GitHubRepository &&
        other.id == id &&
        other.name == name &&
        other.fullName == fullName &&
        other.description == description &&
        other.isPrivate == isPrivate &&
        other.isArchived == isArchived &&
        other.defaultBranch == defaultBranch &&
        other.language == language &&
        other.homepage == homepage &&
        other.updatedAt == updatedAt &&
        other.pushedAt == pushedAt &&
        other.htmlUrl == htmlUrl &&
        other.sizeKb == sizeKb;
  }

  @override
  int get hashCode => Object.hash(
        id,
        name,
        fullName,
        description,
        isPrivate,
        isArchived,
        defaultBranch,
        language,
        homepage,
        updatedAt,
        pushedAt,
        htmlUrl,
        sizeKb,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'full_name': fullName,
        'description': description,
        'private': isPrivate,
        'archived': isArchived,
        'default_branch': defaultBranch,
        'language': language,
        'homepage': homepage,
        'updated_at': updatedAt?.toIso8601String(),
        'pushed_at': pushedAt?.toIso8601String(),
        'html_url': htmlUrl,
        'size': sizeKb,
      };
}
