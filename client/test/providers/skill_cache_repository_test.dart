import 'dart:async';

import 'package:client/data/database/app_database.dart';
import 'package:client/data/database/dao/skill_cache_dao.dart';
import 'package:client/data/repositories/skill_cache_repository.dart';
import 'package:client/models/managed_skill.dart';
import 'package:client/services/skills_api_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSkillsApi extends SkillsApiService {
  List<ManagedSkill> skills = const [];
  SkillDraft? createdDraft;
  String? lastListLocale;
  String? lastCreateLocale;
  String? updatedId;
  SkillDraft? updatedDraft;
  ManagedSkill? updateResult;
  ManagedSkill? detailResult;
  final createCompleter = Completer<ManagedSkill>();
  int detailCalls = 0;

  @override
  Future<List<ManagedSkill>> listSkills({
    SkillScope? scope,
    String? locale,
  }) async {
    lastListLocale = locale;
    return skills;
  }

  @override
  Future<ManagedSkill> createSkill(
    SkillDraft draft, {
    SkillScope? scope,
    String? locale,
  }) {
    createdDraft = draft;
    lastCreateLocale = locale;
    return createCompleter.future;
  }

  @override
  Future<ManagedSkill> updateSkill(
    String id,
    SkillDraft draft, {
    SkillScope? scope,
    String? locale,
  }) async {
    updatedId = id;
    updatedDraft = draft;
    return updateResult!;
  }

  @override
  Future<ManagedSkill> getSkill(
    String id, {
    SkillScope? scope,
    String? locale,
  }) async {
    detailCalls += 1;
    return detailResult!;
  }
}

void main() {
  late AppDatabase db;
  late SkillCacheDao dao;
  late _FakeSkillsApi api;
  late SkillCacheRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dao = SkillCacheDao(db);
    api = _FakeSkillsApi();
    repo = SkillCacheRepository(dao: dao, api: api, userId: 'u1');
  });

  tearDown(() async {
    await db.close();
  });

  test('sync stores source fields and ready localization', () async {
    api.skills = const [
      ManagedSkill(
        id: 'general/web-search',
        name: 'web-search',
        description: 'Search the web',
        category: 'general',
        trigger: 'Use when web lookup is needed',
        enabled: true,
        source: 'managed',
        sourceLabel: 'Managed',
        writable: true,
        deletable: true,
        path: 'general/web-search/SKILL.md',
        root: '/tmp/skills',
        updatedAt: 0,
        hasConflict: false,
        sourceHash: 'sha256:a',
        localizationLocale: 'zh-CN',
        localizationStatus: 'ready',
        translatedName: '网页搜索',
        translatedDescription: '搜索网页',
        translatedTrigger: '需要联网搜索时使用',
      ),
    ];

    await repo.syncGateway(_scope('hermes'), 'zh-CN');
    final skills = await repo.getSkills('hermes', 'zh-CN');

    expect(api.lastListLocale, 'zh-CN');
    expect(skills.single.name, 'web-search');
    expect(skills.single.displayName, 'web-search');
    expect(skills.single.displayDescription, '搜索网页');
    expect(skills.single.displayTrigger, '需要联网搜索时使用');
  });

  test(
    'sync stops showing old localization when source hash changes',
    () async {
      api.skills = const [
        ManagedSkill(
          id: 'general/web-search',
          name: 'web-search',
          description: 'Search the web',
          category: 'general',
          enabled: true,
          source: 'managed',
          sourceLabel: 'Managed',
          writable: true,
          deletable: true,
          path: 'general/web-search/SKILL.md',
          root: '/tmp/skills',
          updatedAt: 0,
          hasConflict: false,
          sourceHash: 'sha256:a',
          localizationLocale: 'zh-CN',
          localizationStatus: 'ready',
          translatedName: '网页搜索',
        ),
      ];
      await repo.syncGateway(_scope('hermes'), 'zh-CN');

      api.skills = const [
        ManagedSkill(
          id: 'general/web-search',
          name: 'web-search',
          description: 'Search the web updated',
          category: 'general',
          enabled: true,
          source: 'managed',
          sourceLabel: 'Managed',
          writable: true,
          deletable: true,
          path: 'general/web-search/SKILL.md',
          root: '/tmp/skills',
          updatedAt: 1,
          hasConflict: false,
          sourceHash: 'sha256:b',
        ),
      ];

      await repo.syncGateway(_scope('hermes'), 'zh-CN');
      final skills = await repo.getSkills('hermes', 'zh-CN');

      expect(skills.single.sourceHash, 'sha256:b');
      expect(skills.single.translatedName, isNull);
      expect(skills.single.displayName, 'web-search');
    },
  );

  test('create updates cache only after server succeeds', () async {
    final create = repo.create(
      const SkillDraft(
        name: 'qa-helper',
        category: 'testing',
        description: 'Validate UI',
        body: '## Body\n',
      ),
      _scope('hermes'),
      'zh-CN',
    );
    await Future<void>.delayed(Duration.zero);

    expect(api.createdDraft?.name, 'qa-helper');
    expect(api.lastCreateLocale, 'zh-CN');
    expect(await repo.getSkills('hermes', 'zh-CN'), isEmpty);

    api.createCompleter.complete(
      const ManagedSkill(
        id: 'testing/qa-helper',
        name: 'qa-helper',
        description: 'Validate UI',
        category: 'testing',
        enabled: true,
        source: 'managed',
        sourceLabel: 'Managed',
        writable: true,
        deletable: true,
        path: 'testing/qa-helper/SKILL.md',
        root: '/tmp/skills',
        updatedAt: 0,
        hasConflict: false,
        sourceHash: 'sha256:c',
      ),
    );

    final created = await create;
    final cached = await repo.getSkills('hermes', 'zh-CN');
    expect(created.id, 'testing/qa-helper');
    expect(cached.map((skill) => skill.id), ['testing/qa-helper']);
  });

  test(
    'update removes old cache row when server returns renamed skill',
    () async {
      api.skills = const [
        ManagedSkill(
          id: 'general/code-review2',
          name: 'code-review2',
          description: 'Review code',
          category: 'general',
          enabled: true,
          source: 'managed',
          sourceLabel: 'Managed',
          writable: true,
          deletable: true,
          path: 'code-review2/SKILL.md',
          root: '/tmp/skills',
          updatedAt: 0,
          hasConflict: false,
        ),
      ];
      await repo.syncGateway(_scope('hermes'), 'zh-CN');
      api.updateResult = const ManagedSkill(
        id: 'general2/code-review22',
        name: 'code-review22',
        description: 'Review code',
        category: 'general2',
        enabled: true,
        source: 'managed',
        sourceLabel: 'Managed',
        writable: true,
        deletable: true,
        path: 'code-review22/SKILL.md',
        root: '/tmp/skills',
        updatedAt: 1,
        hasConflict: false,
      );

      final updated = await repo.update(
        'general/code-review2',
        const SkillDraft(
          name: 'code-review22',
          category: 'general2',
          description: 'Review code',
          body: '# Code Review\n',
        ),
        _scope('hermes'),
        'zh-CN',
      );

      final cached = await repo.getSkills('hermes', 'zh-CN');
      expect(api.updatedId, 'general/code-review2');
      expect(updated.id, 'general2/code-review22');
      expect(cached.map((skill) => skill.id), ['general2/code-review22']);
    },
  );

  test('getDetail reads local cache without calling remote API', () async {
    api.skills = const [
      ManagedSkill(
        id: 'general/web-search',
        name: 'web-search',
        description: 'Search the web',
        category: 'general',
        trigger: 'Cached trigger',
        body: '# Cached body\n',
        enabled: true,
        source: 'managed',
        sourceLabel: 'Managed',
        writable: true,
        deletable: true,
        path: 'general/web-search/SKILL.md',
        root: '/tmp/skills',
        updatedAt: 0,
        hasConflict: false,
      ),
    ];
    await repo.syncGateway(_scope('hermes'), 'en');
    api.detailResult = api.skills.single.copyWith(body: '# Remote body\n');

    final detail = await repo.getDetail(
      'general/web-search',
      _scope('hermes'),
      'en',
    );

    expect(api.detailCalls, 0);
    expect(detail?.body, '# Cached body\n');
  });
}

SkillScope _scope(String gatewayId) {
  return SkillScope(
    id: 'gateway:$gatewayId',
    type: 'gateway',
    label: gatewayId,
    description: gatewayId,
    readonly: false,
    gatewayId: gatewayId,
  );
}
