import 'package:client/data/database/app_database.dart';

class SkillCacheDao {
  final AppDatabase _db;
  SkillCacheDao(this._db);

  Stream<List<SkillWithLocalization>> watchSkills(
    String userId,
    String gatewayId, {
    required String locale,
  }) {
    return _db
        .watchSkills(locale, userId, gatewayId)
        .watch()
        .map((rows) => rows.map(SkillWithLocalization.fromWatch).toList());
  }

  Future<List<SkillWithLocalization>> getSkills(
    String userId,
    String gatewayId, {
    required String locale,
  }) async {
    final rows = await _db.getSkills(locale, userId, gatewayId).get();
    return rows.map(SkillWithLocalization.fromGet).toList();
  }

  Future<SkillWithLocalization?> getSkill(
    String userId,
    String gatewayId,
    String skillId, {
    required String locale,
  }) async {
    final row = await _db
        .getSkill(locale, userId, gatewayId, skillId)
        .getSingleOrNull();
    return row == null ? null : SkillWithLocalization.fromDetail(row);
  }

  Future<void> upsertSkill(SkillCacheCompanion skill) {
    return _db.into(_db.skillCache).insertOnConflictUpdate(skill);
  }

  Future<void> upsertLocalization(SkillLocalizationsCompanion localization) {
    return _db
        .into(_db.skillLocalizations)
        .insertOnConflictUpdate(localization);
  }

  Future<void> deleteSkill(String userId, String gatewayId, String skillId) {
    return _db.transaction(() async {
      await (_db.delete(_db.skillLocalizations)
            ..where((row) => row.userId.equals(userId))
            ..where((row) => row.gatewayId.equals(gatewayId))
            ..where((row) => row.skillId.equals(skillId)))
          .go();
      await (_db.delete(_db.skillCache)
            ..where((row) => row.userId.equals(userId))
            ..where((row) => row.gatewayId.equals(gatewayId))
            ..where((row) => row.skillId.equals(skillId)))
          .go();
    });
  }

  Future<void> deleteMissing(
    String userId,
    String gatewayId,
    Set<String> remoteIds,
  ) async {
    final existing = await getSkills(userId, gatewayId, locale: '');
    for (final skill in existing) {
      if (!remoteIds.contains(skill.skillId)) {
        await deleteSkill(userId, gatewayId, skill.skillId);
      }
    }
  }
}

class SkillWithLocalization {
  const SkillWithLocalization({
    required this.userId,
    required this.gatewayId,
    required this.skillId,
    required this.name,
    required this.description,
    required this.category,
    required this.enabled,
    required this.source,
    required this.sourceLabel,
    required this.writable,
    required this.deletable,
    required this.path,
    required this.root,
    required this.updatedAt,
    required this.hasConflict,
    this.trigger,
    this.body,
    this.content,
    required this.sourceHash,
    this.detailFetchedAt,
    required this.syncedAt,
    this.localizationLocale,
    this.localizationStatus,
    this.translatedName,
    this.translatedDescription,
    this.translatedTrigger,
    this.translatedBody,
  });

  factory SkillWithLocalization.fromWatch(WatchSkillsResult row) {
    return SkillWithLocalization(
      userId: row.userId,
      gatewayId: row.gatewayId,
      skillId: row.skillId,
      name: row.name,
      description: row.description,
      category: row.category,
      enabled: row.enabled,
      source: row.source,
      sourceLabel: row.sourceLabel,
      writable: row.writable,
      deletable: row.deletable,
      path: row.path,
      root: row.root,
      updatedAt: row.updatedAt,
      hasConflict: row.hasConflict,
      trigger: row.trigger,
      body: row.body,
      content: row.content,
      sourceHash: row.sourceHash,
      detailFetchedAt: row.detailFetchedAt,
      syncedAt: row.syncedAt,
      localizationLocale: row.localizationLocale,
      localizationStatus: row.localizationStatus,
      translatedName: row.translatedName,
      translatedDescription: row.translatedDescription,
      translatedTrigger: row.translatedTrigger,
      translatedBody: row.translatedBody,
    );
  }

  factory SkillWithLocalization.fromGet(GetSkillsResult row) {
    return SkillWithLocalization(
      userId: row.userId,
      gatewayId: row.gatewayId,
      skillId: row.skillId,
      name: row.name,
      description: row.description,
      category: row.category,
      enabled: row.enabled,
      source: row.source,
      sourceLabel: row.sourceLabel,
      writable: row.writable,
      deletable: row.deletable,
      path: row.path,
      root: row.root,
      updatedAt: row.updatedAt,
      hasConflict: row.hasConflict,
      trigger: row.trigger,
      body: row.body,
      content: row.content,
      sourceHash: row.sourceHash,
      detailFetchedAt: row.detailFetchedAt,
      syncedAt: row.syncedAt,
      localizationLocale: row.localizationLocale,
      localizationStatus: row.localizationStatus,
      translatedName: row.translatedName,
      translatedDescription: row.translatedDescription,
      translatedTrigger: row.translatedTrigger,
      translatedBody: row.translatedBody,
    );
  }

  factory SkillWithLocalization.fromDetail(GetSkillResult row) {
    return SkillWithLocalization(
      userId: row.userId,
      gatewayId: row.gatewayId,
      skillId: row.skillId,
      name: row.name,
      description: row.description,
      category: row.category,
      enabled: row.enabled,
      source: row.source,
      sourceLabel: row.sourceLabel,
      writable: row.writable,
      deletable: row.deletable,
      path: row.path,
      root: row.root,
      updatedAt: row.updatedAt,
      hasConflict: row.hasConflict,
      trigger: row.trigger,
      body: row.body,
      content: row.content,
      sourceHash: row.sourceHash,
      detailFetchedAt: row.detailFetchedAt,
      syncedAt: row.syncedAt,
      localizationLocale: row.localizationLocale,
      localizationStatus: row.localizationStatus,
      translatedName: row.translatedName,
      translatedDescription: row.translatedDescription,
      translatedTrigger: row.translatedTrigger,
      translatedBody: row.translatedBody,
    );
  }

  final String userId;
  final String gatewayId;
  final String skillId;
  final String name;
  final String description;
  final String category;
  final bool enabled;
  final String source;
  final String sourceLabel;
  final bool writable;
  final bool deletable;
  final String path;
  final String root;
  final double updatedAt;
  final bool hasConflict;
  final String? trigger;
  final String? body;
  final String? content;
  final String sourceHash;
  final int? detailFetchedAt;
  final int syncedAt;
  final String? localizationLocale;
  final String? localizationStatus;
  final String? translatedName;
  final String? translatedDescription;
  final String? translatedTrigger;
  final String? translatedBody;
}
