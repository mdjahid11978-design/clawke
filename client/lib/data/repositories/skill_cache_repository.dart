import 'package:client/data/database/app_database.dart';
import 'package:client/data/database/dao/skill_cache_dao.dart';
import 'package:client/models/managed_skill.dart';
import 'package:client/services/skills_api_service.dart';
import 'package:drift/drift.dart' as drift;

class SkillCacheRepository {
  SkillCacheRepository({
    required SkillCacheDao dao,
    required SkillsApiService api,
    required String userId,
  }) : _dao = dao,
       _api = api,
       _userId = userId;

  final SkillCacheDao _dao;
  final SkillsApiService _api;
  final String _userId;

  Stream<List<ManagedSkill>> watchSkills(String gatewayId, String locale) {
    return _dao.watchSkills(_userId, gatewayId, locale: locale).map(_fromRows);
  }

  Future<List<ManagedSkill>> getSkills(String gatewayId, String locale) async {
    return _fromRows(await _dao.getSkills(_userId, gatewayId, locale: locale));
  }

  Future<ManagedSkill?> getCachedSkill(
    String id,
    SkillScope scope,
    String locale,
  ) async {
    final gatewayId = _gatewayId(scope);
    final row = await _dao.getSkill(_userId, gatewayId, id, locale: locale);
    return row == null ? null : _fromRow(row);
  }

  Future<List<ManagedSkill>> syncGateway(
    SkillScope scope,
    String locale,
  ) async {
    final gatewayId = _gatewayId(scope);
    final skills = await _api.listSkills(scope: scope, locale: locale);
    for (final skill in skills) {
      await _upsertSkill(skill, gatewayId: gatewayId, locale: locale);
    }
    await _dao.deleteMissing(_userId, gatewayId, {
      for (final skill in skills) skill.id,
    });
    return getSkills(gatewayId, locale);
  }

  Future<ManagedSkill?> getDetail(
    String id,
    SkillScope scope,
    String locale,
  ) async {
    final skill = await _api.getSkill(id, scope: scope, locale: locale);
    await _upsertSkill(skill, gatewayId: _gatewayId(scope), locale: locale);
    return _fromRow(
      (await _dao.getSkill(_userId, _gatewayId(scope), id, locale: locale))!,
    );
  }

  Future<ManagedSkill> create(
    SkillDraft draft,
    SkillScope? scope,
    String locale,
  ) async {
    final skill = await _api.createSkill(draft, scope: scope, locale: locale);
    await _upsertSkill(skill, gatewayId: _gatewayId(scope), locale: locale);
    return _fromRow(
      (await _dao.getSkill(
        _userId,
        _gatewayId(scope),
        skill.id,
        locale: locale,
      ))!,
    );
  }

  Future<ManagedSkill> update(
    String id,
    SkillDraft draft,
    SkillScope? scope,
    String locale,
  ) async {
    final skill = await _api.updateSkill(
      id,
      draft,
      scope: scope,
      locale: locale,
    );
    final gatewayId = _gatewayId(scope);
    if (skill.id != id) {
      await _dao.deleteSkill(_userId, gatewayId, id);
    }
    await _upsertSkill(skill, gatewayId: gatewayId, locale: locale);
    return _fromRow(
      (await _dao.getSkill(_userId, gatewayId, skill.id, locale: locale))!,
    );
  }

  Future<void> delete(String id, SkillScope? scope) async {
    final gatewayId = _gatewayId(scope);
    await _api.deleteSkill(id, scope: scope);
    await _dao.deleteSkill(_userId, gatewayId, id);
  }

  Future<void> setEnabled(
    String id,
    bool enabled,
    SkillScope? scope,
    String locale,
  ) async {
    final gatewayId = _gatewayId(scope);
    await _api.setEnabled(id, enabled, scope: scope);
    final current = await _dao.getSkill(_userId, gatewayId, id, locale: locale);
    if (current == null) return;
    await _upsertSkill(
      _fromRow(current).copyWith(enabled: enabled),
      gatewayId: gatewayId,
      locale: locale,
    );
  }

  Future<void> _upsertSkill(
    ManagedSkill skill, {
    required String gatewayId,
    required String locale,
  }) async {
    await _dao.upsertSkill(_toCompanion(skill, gatewayId: gatewayId));
    final localization = _toLocalization(
      skill,
      gatewayId: gatewayId,
      locale: locale,
    );
    if (localization != null) {
      await _dao.upsertLocalization(localization);
    }
  }

  SkillCacheCompanion _toCompanion(
    ManagedSkill skill, {
    required String gatewayId,
  }) {
    return SkillCacheCompanion.insert(
      userId: _userId,
      gatewayId: gatewayId,
      skillId: skill.id,
      name: skill.name,
      description: skill.description,
      category: skill.category,
      enabled: skill.enabled,
      source: skill.source,
      sourceLabel: skill.sourceLabel,
      writable: skill.writable,
      deletable: skill.deletable,
      path: skill.path,
      root: skill.root,
      updatedAt: drift.Value(skill.updatedAt),
      hasConflict: drift.Value(skill.hasConflict),
      trigger: drift.Value(skill.trigger),
      body: drift.Value(skill.body),
      content: drift.Value(skill.content),
      sourceHash: drift.Value(skill.sourceHash ?? ''),
      detailFetchedAt: skill.body == null && skill.content == null
          ? const drift.Value.absent()
          : drift.Value(DateTime.now().millisecondsSinceEpoch),
      syncedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  SkillLocalizationsCompanion? _toLocalization(
    ManagedSkill skill, {
    required String gatewayId,
    required String locale,
  }) {
    final hasTranslation =
        skill.translatedName != null ||
        skill.translatedDescription != null ||
        skill.translatedTrigger != null ||
        skill.translatedBody != null;
    final status =
        skill.localizationStatus ?? (hasTranslation ? 'ready' : null);
    if (status == null) return null;
    return SkillLocalizationsCompanion.insert(
      userId: _userId,
      gatewayId: gatewayId,
      skillId: skill.id,
      locale: skill.localizationLocale ?? locale,
      sourceHash: skill.sourceHash ?? '',
      translatedName: drift.Value(skill.translatedName),
      translatedDescription: drift.Value(skill.translatedDescription),
      translatedTrigger: drift.Value(skill.translatedTrigger),
      translatedBody: drift.Value(skill.translatedBody),
      status: status,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  List<ManagedSkill> _fromRows(List<SkillWithLocalization> rows) {
    return rows.map(_fromRow).toList();
  }

  ManagedSkill _fromRow(SkillWithLocalization row) {
    return ManagedSkill(
      id: row.skillId,
      name: row.name,
      description: row.description,
      category: row.category,
      trigger: row.trigger,
      enabled: row.enabled,
      source: row.source,
      sourceLabel: row.sourceLabel,
      writable: row.writable,
      deletable: row.deletable,
      path: row.path,
      root: row.root,
      updatedAt: row.updatedAt,
      hasConflict: row.hasConflict,
      content: row.content,
      body: row.body,
      sourceHash: row.sourceHash,
      localizationLocale: row.localizationLocale,
      localizationStatus: row.localizationStatus,
      translatedName: row.translatedName,
      translatedDescription: row.translatedDescription,
      translatedTrigger: row.translatedTrigger,
      translatedBody: row.translatedBody,
    );
  }
}

String _gatewayId(SkillScope? scope) {
  final gatewayId = scope?.gatewayId;
  if (gatewayId != null && gatewayId.isNotEmpty) return gatewayId;
  return 'global';
}
