import 'package:client/data/database/app_database.dart';
import 'package:client/data/database/dao/skill_cache_dao.dart';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late SkillCacheDao dao;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dao = SkillCacheDao(db);
  });

  tearDown(() async {
    await db.close();
  });

  test(
    'getSkills returns ready localization for matching source hash',
    () async {
      await dao.upsertSkill(_skill('web-search', sourceHash: 'sha256:a'));
      await dao.upsertLocalization(
        SkillLocalizationsCompanion.insert(
          userId: 'u1',
          gatewayId: 'hermes',
          skillId: 'general/web-search',
          locale: 'zh-CN',
          sourceHash: 'sha256:a',
          translatedName: const drift.Value('网页搜索'),
          translatedDescription: const drift.Value('搜索网页'),
          status: 'ready',
          updatedAt: 100,
        ),
      );

      final rows = await dao.getSkills('u1', 'hermes', locale: 'zh-CN');

      expect(rows, hasLength(1));
      expect(rows.single.name, 'web-search');
      expect(rows.single.translatedName, '网页搜索');
      expect(rows.single.translatedDescription, '搜索网页');
    },
  );

  test('getSkills ignores stale localization with old source hash', () async {
    await dao.upsertSkill(_skill('web-search', sourceHash: 'sha256:b'));
    await dao.upsertLocalization(
      SkillLocalizationsCompanion.insert(
        userId: 'u1',
        gatewayId: 'hermes',
        skillId: 'general/web-search',
        locale: 'zh-CN',
        sourceHash: 'sha256:a',
        translatedName: const drift.Value('旧网页搜索'),
        status: 'ready',
        updatedAt: 100,
      ),
    );

    final rows = await dao.getSkills('u1', 'hermes', locale: 'zh-CN');

    expect(rows.single.name, 'web-search');
    expect(rows.single.translatedName, isNull);
  });

  test('deleteMissing removes only the selected user and gateway', () async {
    await dao.upsertSkill(_skill('keep'));
    await dao.upsertSkill(_skill('delete_me'));
    await dao.upsertSkill(_skill('other_gateway', gatewayId: 'openclaw'));
    await dao.upsertSkill(_skill('other_user', userId: 'u2'));

    await dao.deleteMissing('u1', 'hermes', {'general/keep'});

    expect(
      (await dao.getSkills(
        'u1',
        'hermes',
        locale: 'zh-CN',
      )).map((row) => row.skillId),
      ['general/keep'],
    );
    expect(
      await dao.getSkills('u1', 'openclaw', locale: 'zh-CN'),
      hasLength(1),
    );
    expect(await dao.getSkills('u2', 'hermes', locale: 'zh-CN'), hasLength(1));
  });
}

SkillCacheCompanion _skill(
  String name, {
  String userId = 'u1',
  String gatewayId = 'hermes',
  String sourceHash = 'sha256:a',
}) {
  return SkillCacheCompanion.insert(
    userId: userId,
    gatewayId: gatewayId,
    skillId: 'general/$name',
    name: name,
    description: 'Search the web',
    category: 'general',
    enabled: true,
    source: 'managed',
    sourceLabel: 'Clawke managed',
    writable: true,
    deletable: true,
    path: 'general/$name/SKILL.md',
    root: '/tmp/skills',
    updatedAt: const drift.Value(0),
    sourceHash: drift.Value(sourceHash),
    syncedAt: 100,
  );
}
