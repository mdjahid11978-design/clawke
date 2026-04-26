class ManagedSkill {
  final String id;
  final String name;
  final String description;
  final String category;
  final String? trigger;
  final bool enabled;
  final String source;
  final String sourceLabel;
  final bool writable;
  final bool deletable;
  final String path;
  final String absolutePath;
  final String root;
  final double updatedAt;
  final bool hasConflict;
  final String? content;
  final String? body;
  final String? sourceHash;
  final String? localizationLocale;
  final String? localizationStatus;
  final String? translatedName;
  final String? translatedDescription;
  final String? translatedTrigger;
  final String? translatedBody;

  const ManagedSkill({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    this.trigger,
    required this.enabled,
    required this.source,
    required this.sourceLabel,
    required this.writable,
    required this.deletable,
    required this.path,
    this.absolutePath = '',
    required this.root,
    required this.updatedAt,
    required this.hasConflict,
    this.content,
    this.body,
    this.sourceHash,
    this.localizationLocale,
    this.localizationStatus,
    this.translatedName,
    this.translatedDescription,
    this.translatedTrigger,
    this.translatedBody,
  });

  factory ManagedSkill.fromJson(Map<String, dynamic> json) {
    final localization = json['localization'] is Map
        ? Map<String, dynamic>.from(json['localization'] as Map)
        : null;
    return ManagedSkill(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      category: json['category'] as String? ?? 'general',
      trigger: json['trigger'] as String?,
      enabled: json['enabled'] != false,
      source: json['source'] as String? ?? 'external',
      sourceLabel: json['sourceLabel'] as String? ?? '',
      writable: json['writable'] == true,
      deletable: json['deletable'] == true,
      path: json['path'] as String? ?? '',
      absolutePath: json['absolutePath'] as String? ?? '',
      root: json['root'] as String? ?? '',
      updatedAt: (json['updatedAt'] as num?)?.toDouble() ?? 0,
      hasConflict: json['hasConflict'] == true,
      content: json['content'] as String?,
      body: json['body'] as String?,
      sourceHash:
          json['sourceHash'] as String? ?? json['source_hash'] as String?,
      localizationLocale:
          json['localizationLocale'] as String? ??
          localization?['locale'] as String?,
      localizationStatus:
          json['localizationStatus'] as String? ??
          localization?['status'] as String?,
      translatedName:
          json['translatedName'] as String? ?? localization?['name'] as String?,
      translatedDescription:
          json['translatedDescription'] as String? ??
          localization?['description'] as String?,
      translatedTrigger:
          json['translatedTrigger'] as String? ??
          localization?['trigger'] as String?,
      translatedBody:
          json['translatedBody'] as String? ?? localization?['body'] as String?,
    );
  }

  ManagedSkill copyWith({
    String? id,
    String? name,
    String? description,
    String? category,
    String? trigger,
    bool? enabled,
    String? source,
    String? sourceLabel,
    bool? writable,
    bool? deletable,
    String? path,
    String? absolutePath,
    String? root,
    double? updatedAt,
    bool? hasConflict,
    String? content,
    String? body,
    String? sourceHash,
    String? localizationLocale,
    String? localizationStatus,
    String? translatedName,
    String? translatedDescription,
    String? translatedTrigger,
    String? translatedBody,
  }) {
    return ManagedSkill(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      category: category ?? this.category,
      trigger: trigger ?? this.trigger,
      enabled: enabled ?? this.enabled,
      source: source ?? this.source,
      sourceLabel: sourceLabel ?? this.sourceLabel,
      writable: writable ?? this.writable,
      deletable: deletable ?? this.deletable,
      path: path ?? this.path,
      absolutePath: absolutePath ?? this.absolutePath,
      root: root ?? this.root,
      updatedAt: updatedAt ?? this.updatedAt,
      hasConflict: hasConflict ?? this.hasConflict,
      content: content ?? this.content,
      body: body ?? this.body,
      sourceHash: sourceHash ?? this.sourceHash,
      localizationLocale: localizationLocale ?? this.localizationLocale,
      localizationStatus: localizationStatus ?? this.localizationStatus,
      translatedName: translatedName ?? this.translatedName,
      translatedDescription:
          translatedDescription ?? this.translatedDescription,
      translatedTrigger: translatedTrigger ?? this.translatedTrigger,
      translatedBody: translatedBody ?? this.translatedBody,
    );
  }

  String get displayName => name;

  String get displayDescription => translatedDescription ?? description;

  String? get displayTrigger => translatedTrigger ?? trigger;

  String? get displayBody => translatedBody ?? body;

  String get displayPath {
    if (absolutePath.isNotEmpty) return absolutePath;
    if (path.isEmpty) return root;
    if (root.isEmpty || _isAbsolutePath(path)) return path;
    final separator = root.endsWith('/') || root.endsWith('\\') ? '' : '/';
    return '$root$separator$path';
  }

  static bool _isAbsolutePath(String value) {
    final normalized = value.replaceAll('\\', '/');
    return normalized.startsWith('/') ||
        RegExp(r'^[A-Za-z]:/').hasMatch(normalized);
  }
}

class SkillScope {
  final String id;
  final String type;
  final String label;
  final String description;
  final bool readonly;
  final String? gatewayId;

  const SkillScope({
    required this.id,
    required this.type,
    required this.label,
    required this.description,
    required this.readonly,
    this.gatewayId,
  });

  factory SkillScope.fromJson(Map<String, dynamic> json) {
    return SkillScope(
      id: json['id'] as String? ?? '',
      type: json['type'] as String? ?? '',
      label: json['label'] as String? ?? '',
      description: json['description'] as String? ?? '',
      readonly: json['readonly'] == true,
      gatewayId: json['gatewayId'] as String?,
    );
  }

  bool get isGateway => type == 'gateway';
}

class SkillDraft {
  final String name;
  final String category;
  final String description;
  final String? trigger;
  final String body;

  const SkillDraft({
    required this.name,
    required this.category,
    required this.description,
    this.trigger,
    required this.body,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'category': category,
      'description': description,
      if (trigger != null && trigger!.trim().isNotEmpty)
        'trigger': trigger!.trim(),
      'body': body,
    };
  }
}
