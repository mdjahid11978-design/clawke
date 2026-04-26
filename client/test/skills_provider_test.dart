import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:client/data/repositories/skill_cache_repository.dart';
import 'package:client/models/gateway_info.dart';
import 'package:client/models/managed_skill.dart';
import 'package:client/providers/skills_provider.dart';
import 'package:client/services/skills_api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeSkillsApiService extends SkillsApiService {
  _FakeSkillsApiService(this.items);

  List<ManagedSkill> items;
  List<SkillScope> scopes = const [
    SkillScope(
      id: 'gateway:hermes-work',
      type: 'gateway',
      label: 'hermes-work',
      description: 'Hermes gateway',
      readonly: false,
      gatewayId: 'hermes-work',
    ),
    SkillScope(
      id: 'gateway:openclaw-lab',
      type: 'gateway',
      label: 'openclaw-lab',
      description: 'OpenClaw gateway',
      readonly: false,
      gatewayId: 'openclaw-lab',
    ),
  ];
  String? loadedScopeId;
  String? toggledId;
  bool? toggledEnabled;
  String? toggledScopeId;
  String? updatedId;
  SkillDraft? updatedDraft;
  String? updatedScopeId;
  ManagedSkill? updateResult;

  @override
  Future<List<SkillScope>> listScopes() async => scopes;

  @override
  Future<List<ManagedSkill>> listSkills({
    SkillScope? scope,
    String? locale,
  }) async {
    loadedScopeId = scope?.id;
    return items;
  }

  @override
  Future<void> setEnabled(String id, bool enabled, {SkillScope? scope}) async {
    toggledId = id;
    toggledEnabled = enabled;
    toggledScopeId = scope?.id;
    final index = items.indexWhere((skill) => skill.id == id);
    final next = items[index].copyWith(enabled: enabled);
    items = [...items]..[index] = next;
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
    updatedScopeId = scope?.id;
    final next =
        updateResult ??
        items
            .firstWhere((skill) => skill.id == id)
            .copyWith(
              name: draft.name,
              description: draft.description,
              category: draft.category,
              body: draft.body,
            );
    items = [...items.where((skill) => skill.id != id), next];
    return next;
  }
}

class _ApiBackedSkillCacheRepository implements SkillCacheRepository {
  _ApiBackedSkillCacheRepository(this.api);

  final SkillsApiService api;
  List<ManagedSkill> cached = const [];

  @override
  Stream<List<ManagedSkill>> watchSkills(String gatewayId, String locale) {
    return Stream.value(_cachedFor(gatewayId));
  }

  @override
  Future<List<ManagedSkill>> getSkills(String gatewayId, String locale) async {
    return _cachedFor(gatewayId);
  }

  @override
  Future<List<ManagedSkill>> syncGateway(
    SkillScope scope,
    String locale,
  ) async {
    final gatewayId = _gatewayId(scope);
    final skills = await api.listSkills(scope: scope, locale: locale);
    cached = [
      ...cached.where((skill) => !_belongsTo(skill, gatewayId)),
      ...skills,
    ];
    return skills;
  }

  @override
  Future<ManagedSkill?> getCachedSkill(
    String id,
    SkillScope scope,
    String locale,
  ) async {
    return cached.where((skill) => skill.id == id).firstOrNull;
  }

  @override
  Future<ManagedSkill?> getDetail(
    String id,
    SkillScope scope,
    String locale,
  ) async {
    final skill = await api.getSkill(id, scope: scope, locale: locale);
    cached = _replaceCached(skill);
    return skill;
  }

  @override
  Future<ManagedSkill> create(
    SkillDraft draft,
    SkillScope? scope,
    String locale,
  ) async {
    final skill = await api.createSkill(draft, scope: scope, locale: locale);
    cached = _replaceCached(skill);
    return skill;
  }

  @override
  Future<ManagedSkill> update(
    String id,
    SkillDraft draft,
    SkillScope? scope,
    String locale,
  ) async {
    final skill = await api.updateSkill(
      id,
      draft,
      scope: scope,
      locale: locale,
    );
    cached = _replaceCached(skill);
    return skill;
  }

  @override
  Future<void> delete(String id, SkillScope? scope) async {
    await api.deleteSkill(id, scope: scope);
    cached = cached.where((skill) => skill.id != id).toList();
  }

  @override
  Future<void> setEnabled(
    String id,
    bool enabled,
    SkillScope? scope,
    String locale,
  ) async {
    await api.setEnabled(id, enabled, scope: scope);
    final index = cached.indexWhere((skill) => skill.id == id);
    if (index != -1) {
      cached = [...cached]..[index] = cached[index].copyWith(enabled: enabled);
    }
  }

  List<ManagedSkill> _cachedFor(String gatewayId) {
    return cached.where((skill) => _belongsTo(skill, gatewayId)).toList();
  }

  List<ManagedSkill> _replaceCached(ManagedSkill skill) {
    return [...cached.where((item) => item.id != skill.id), skill];
  }

  bool _belongsTo(ManagedSkill skill, String gatewayId) {
    return skill.sourceLabel.toLowerCase().contains(gatewayId.toLowerCase());
  }
}

class _SlowFakeSkillsApiService extends SkillsApiService {
  _SlowFakeSkillsApiService(this.items);

  List<ManagedSkill> items;
  final completer = Completer<void>();

  @override
  Future<List<SkillScope>> listScopes() async => const [
    SkillScope(
      id: 'gateway:hermes-work',
      type: 'gateway',
      label: 'hermes-work',
      description: 'Hermes gateway',
      readonly: false,
      gatewayId: 'hermes-work',
    ),
  ];

  @override
  Future<List<ManagedSkill>> listSkills({
    SkillScope? scope,
    String? locale,
  }) async => items;

  @override
  Future<void> setEnabled(String id, bool enabled, {SkillScope? scope}) {
    return completer.future;
  }
}

class _DelayedSkillsApiService extends SkillsApiService {
  final _pending = <String, List<Completer<List<ManagedSkill>>>>{};
  bool delayHermes = false;
  bool delayOpenClaw = false;

  void delayGatewayLoads() {
    delayHermes = true;
    delayOpenClaw = true;
  }

  void completeHermes({int index = 0, String skillId = 'hermes/skill'}) {
    _complete('hermes', index, [
      ManagedSkill(
        id: skillId,
        name: 'Hermes skill',
        description: 'Hermes skill',
        category: 'general',
        enabled: true,
        source: 'external',
        sourceLabel: 'Hermes',
        writable: true,
        deletable: true,
        path: '/tmp/hermes/SKILL.md',
        root: '/tmp/hermes',
        updatedAt: 0,
        hasConflict: false,
      ),
    ]);
  }

  void failHermes({int index = 0}) {
    _pending['hermes']![index].completeError(
      DioException(
        requestOptions: RequestOptions(path: '/api/skills'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/skills'),
          statusCode: 504,
          data: const {'error': 'gateway_timeout'},
        ),
        type: DioExceptionType.badResponse,
      ),
    );
  }

  void completeOpenClaw({int index = 0, String skillId = 'openclaw/skill'}) {
    _complete('openclaw', index, [
      ManagedSkill(
        id: skillId,
        name: 'OpenClaw skill',
        description: 'OpenClaw skill',
        category: 'general',
        enabled: true,
        source: 'external',
        sourceLabel: 'OpenClaw',
        writable: true,
        deletable: true,
        path: '/tmp/openclaw/SKILL.md',
        root: '/tmp/openclaw',
        updatedAt: 0,
        hasConflict: false,
      ),
    ]);
  }

  @override
  Future<List<SkillScope>> listScopes() async => const [
    SkillScope(
      id: 'gateway:hermes',
      type: 'gateway',
      label: 'Hermes',
      description: 'hermes',
      readonly: false,
      gatewayId: 'hermes',
    ),
    SkillScope(
      id: 'gateway:openclaw',
      type: 'gateway',
      label: 'OpenClaw',
      description: 'openclaw',
      readonly: false,
      gatewayId: 'openclaw',
    ),
  ];

  @override
  Future<List<ManagedSkill>> listSkills({SkillScope? scope, String? locale}) {
    final gatewayId = scope?.gatewayId;
    if (gatewayId == 'hermes') {
      return delayHermes
          ? _queue('hermes')
          : Future.value(const <ManagedSkill>[]);
    }
    if (gatewayId == 'openclaw') {
      return delayOpenClaw
          ? _queue('openclaw')
          : Future.value(const <ManagedSkill>[]);
    }
    return Future.value(const <ManagedSkill>[]);
  }

  Future<List<ManagedSkill>> _queue(String gatewayId) {
    final completer = Completer<List<ManagedSkill>>();
    (_pending[gatewayId] ??= []).add(completer);
    return completer.future;
  }

  void _complete(String gatewayId, int index, List<ManagedSkill> skills) {
    _pending[gatewayId]![index].complete(skills);
  }
}

class _DelayedSkillCacheRepository implements SkillCacheRepository {
  _DelayedSkillCacheRepository({this.cached = const []});

  List<ManagedSkill> cached;
  final _pending = <String, List<Completer<List<ManagedSkill>>>>{};

  @override
  Future<List<ManagedSkill>> getSkills(String gatewayId, String locale) async {
    return _cachedFor(gatewayId);
  }

  @override
  Stream<List<ManagedSkill>> watchSkills(String gatewayId, String locale) {
    return Stream.value(_cachedFor(gatewayId));
  }

  @override
  Future<List<ManagedSkill>> syncGateway(SkillScope scope, String locale) {
    final gatewayId = _gatewayId(scope);
    final completer = Completer<List<ManagedSkill>>();
    (_pending[gatewayId] ??= []).add(completer);
    return completer.future;
  }

  void complete(String gatewayId, List<ManagedSkill> skills, {int index = 0}) {
    cached = [
      ...cached.where((skill) => !_belongsTo(skill, gatewayId)),
      ...skills,
    ];
    _pending[gatewayId]![index].complete(skills);
  }

  List<ManagedSkill> _cachedFor(String gatewayId) {
    return cached.where((skill) => _belongsTo(skill, gatewayId)).toList();
  }

  bool _belongsTo(ManagedSkill skill, String gatewayId) {
    return skill.sourceLabel.toLowerCase().contains(gatewayId.toLowerCase());
  }

  @override
  Future<ManagedSkill> create(
    SkillDraft draft,
    SkillScope? scope,
    String locale,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<void> delete(String id, SkillScope? scope) {
    throw UnimplementedError();
  }

  @override
  Future<ManagedSkill?> getCachedSkill(
    String id,
    SkillScope scope,
    String locale,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<ManagedSkill?> getDetail(String id, SkillScope scope, String locale) {
    throw UnimplementedError();
  }

  @override
  Future<void> setEnabled(
    String id,
    bool enabled,
    SkillScope? scope,
    String locale,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<ManagedSkill> update(
    String id,
    SkillDraft draft,
    SkillScope? scope,
    String locale,
  ) {
    throw UnimplementedError();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({'clawke_locale': 'en'});

  test('SkillsController loads skills and updates enabled state', () async {
    final fake = _FakeSkillsApiService([
      const ManagedSkill(
        id: 'general/web-search',
        name: 'web-search',
        description: 'Search the web',
        category: 'general',
        enabled: true,
        source: 'managed',
        sourceLabel: 'Clawke managed',
        writable: true,
        deletable: true,
        path: 'general/web-search/SKILL.md',
        root: '/tmp/skills',
        updatedAt: 0,
        hasConflict: false,
      ),
    ]);

    final container = ProviderContainer(
      overrides: _skillProviderOverrides(fake),
    );
    addTearDown(container.dispose);

    await container.read(skillsControllerProvider.notifier).load();
    expect(
      container.read(skillsControllerProvider).skills.single.enabled,
      true,
    );

    await container
        .read(skillsControllerProvider.notifier)
        .setEnabled('general/web-search', false);

    expect(fake.toggledId, 'general/web-search');
    expect(fake.toggledEnabled, false);
    expect(fake.toggledScopeId, 'gateway:hermes-work');
    expect(
      container.read(skillsControllerProvider).skills.single.enabled,
      false,
    );
  });

  test(
    'SkillsController removes old skill id when update renames skill',
    () async {
      final fake = _FakeSkillsApiService([
        const ManagedSkill(
          id: 'general/code-review2',
          name: 'code-review2',
          description: 'Review code',
          category: 'general',
          enabled: true,
          source: 'managed',
          sourceLabel: 'Clawke managed',
          writable: true,
          deletable: true,
          path: 'code-review2/SKILL.md',
          root: '/tmp/skills',
          updatedAt: 0,
          hasConflict: false,
        ),
      ]);
      fake.updateResult = const ManagedSkill(
        id: 'general2/code-review22',
        name: 'code-review22',
        description: 'Review code',
        category: 'general2',
        enabled: true,
        source: 'managed',
        sourceLabel: 'Clawke managed',
        writable: true,
        deletable: true,
        path: 'code-review22/SKILL.md',
        root: '/tmp/skills',
        updatedAt: 1,
        hasConflict: false,
      );

      final container = ProviderContainer(
        overrides: _skillProviderOverrides(fake),
      );
      addTearDown(container.dispose);

      await container.read(skillsControllerProvider.notifier).load();
      await container
          .read(skillsControllerProvider.notifier)
          .update(
            'general/code-review2',
            const SkillDraft(
              name: 'code-review22',
              category: 'general2',
              description: 'Review code',
              body: '# Code Review\n',
            ),
          );

      expect(fake.updatedId, 'general/code-review2');
      expect(
        container
            .read(skillsControllerProvider)
            .skills
            .map((skill) => skill.id),
        ['general2/code-review22'],
      );

      await container
          .read(skillsControllerProvider.notifier)
          .setEnabled('general2/code-review22', false);

      expect(fake.toggledId, 'general2/code-review22');
    },
  );

  test(
    'SkillsController loads scopes and defaults to the first gateway scope',
    () async {
      final fake = _FakeSkillsApiService([
        const ManagedSkill(
          id: 'general/web-search',
          name: 'web-search',
          description: 'Search the web',
          category: 'general',
          enabled: true,
          source: 'managed',
          sourceLabel: 'Clawke managed',
          writable: true,
          deletable: true,
          path: 'general/web-search/SKILL.md',
          root: '/tmp/skills',
          updatedAt: 0,
          hasConflict: false,
        ),
      ]);

      final container = ProviderContainer(
        overrides: _skillProviderOverrides(fake),
      );
      addTearDown(container.dispose);

      await container.read(skillsControllerProvider.notifier).load();

      final state = container.read(skillsControllerProvider);
      expect(
        state.scopes.map((scope) => scope.id),
        contains('gateway:hermes-work'),
      );
      expect(state.selectedScopeId, 'gateway:hermes-work');
      expect(state.selectedScope?.label, 'hermes-work');
      expect(state.isScopeReadOnly, isFalse);
      expect(fake.loadedScopeId, 'gateway:hermes-work');
    },
  );

  test('SkillsController refreshes scopes when skills already exist', () async {
    final fake = _FakeSkillsApiService([
      const ManagedSkill(
        id: 'general/web-search',
        name: 'web-search',
        description: 'Search the web',
        category: 'general',
        enabled: true,
        source: 'managed',
        sourceLabel: 'Clawke managed',
        writable: true,
        deletable: true,
        path: 'general/web-search/SKILL.md',
        root: '/tmp/skills',
        updatedAt: 0,
        hasConflict: false,
      ),
    ]);
    fake.scopes = const [
      SkillScope(
        id: 'gateway:hermes-work',
        type: 'gateway',
        label: 'hermes-work',
        description: 'Hermes gateway',
        readonly: false,
        gatewayId: 'hermes-work',
      ),
    ];

    final container = ProviderContainer(
      overrides: _skillProviderOverrides(fake),
    );
    addTearDown(container.dispose);

    await container.read(skillsControllerProvider.notifier).load();
    expect(
      container.read(skillsControllerProvider).scopes.map((scope) => scope.id),
      ['gateway:hermes-work'],
    );

    fake.scopes = const [
      SkillScope(
        id: 'gateway:hermes-work',
        type: 'gateway',
        label: 'hermes-work',
        description: 'Hermes gateway',
        readonly: false,
        gatewayId: 'hermes-work',
      ),
      SkillScope(
        id: 'gateway:openclaw-lab',
        type: 'gateway',
        label: 'openclaw-lab',
        description: 'OpenClaw gateway',
        readonly: false,
        gatewayId: 'openclaw-lab',
      ),
    ];

    await container.read(skillsControllerProvider.notifier).load();

    expect(
      container.read(skillsControllerProvider).scopes.map((scope) => scope.id),
      ['gateway:hermes-work', 'gateway:openclaw-lab'],
    );
  });

  test('SkillsController reports an error when gateway scopes fail', () async {
    final fake = _FailingScopesSkillsApiService([
      const ManagedSkill(
        id: 'general/web-search',
        name: 'web-search',
        description: 'Search the web',
        category: 'general',
        enabled: true,
        source: 'managed',
        sourceLabel: 'Clawke managed',
        writable: true,
        deletable: true,
        path: 'general/web-search/SKILL.md',
        root: '/tmp/skills',
        updatedAt: 0,
        hasConflict: false,
      ),
    ]);

    final container = ProviderContainer(
      overrides: _skillProviderOverrides(fake),
    );
    addTearDown(container.dispose);

    await container.read(skillsControllerProvider.notifier).load();

    final state = container.read(skillsControllerProvider);
    expect(state.skills, isEmpty);
    expect(state.scopes, isEmpty);
    expect(state.selectedScopeId, isNull);
    expect(fake.legacyListCalled, isFalse);
    expect(state.errorMessage, contains('scopes unavailable'));
  });

  test(
    'SkillsController changes selected scope and reloads scoped skills',
    () async {
      final fake = _FakeSkillsApiService([
        const ManagedSkill(
          id: 'general/web-search',
          name: 'web-search',
          description: 'Search the web',
          category: 'general',
          enabled: true,
          source: 'managed',
          sourceLabel: 'Clawke managed',
          writable: true,
          deletable: true,
          path: 'general/web-search/SKILL.md',
          root: '/tmp/skills',
          updatedAt: 0,
          hasConflict: false,
        ),
      ]);

      final container = ProviderContainer(
        overrides: _skillProviderOverrides(fake),
      );
      addTearDown(container.dispose);

      await container.read(skillsControllerProvider.notifier).load();
      await container
          .read(skillsControllerProvider.notifier)
          .selectScope('gateway:openclaw-lab');

      final state = container.read(skillsControllerProvider);
      expect(state.selectedScopeId, 'gateway:openclaw-lab');
      expect(state.isScopeReadOnly, isFalse);
      expect(fake.loadedScopeId, 'gateway:openclaw-lab');
    },
  );

  test(
    'SkillsController shows cached localized skills before remote sync completes',
    () async {
      final repo = _DelayedSkillCacheRepository(
        cached: const [
          ManagedSkill(
            id: 'general/web-search',
            name: 'web-search',
            description: 'Search the web',
            category: 'general',
            enabled: true,
            source: 'managed',
            sourceLabel: 'hermes',
            writable: true,
            deletable: true,
            path: 'general/web-search/SKILL.md',
            root: '/tmp/skills',
            updatedAt: 0,
            hasConflict: false,
            translatedName: '网页搜索',
          ),
        ],
      );
      final controller = SkillsController(
        _FakeSkillsApiService(const []),
        cache: repo,
        locale: 'zh-CN',
      );
      addTearDown(controller.dispose);

      final load = controller.syncGateways(const [
        GatewayInfo(
          gatewayId: 'hermes',
          displayName: 'Hermes',
          gatewayType: 'hermes',
          status: GatewayConnectionStatus.online,
          capabilities: ['skills'],
        ),
      ]);
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.isLoading, true);
      expect(controller.state.skills.single.displayName, 'web-search');

      repo.complete('hermes', const [
        ManagedSkill(
          id: 'general/web-search',
          name: 'web-search',
          description: 'Search the web',
          category: 'general',
          enabled: true,
          source: 'managed',
          sourceLabel: 'hermes',
          writable: true,
          deletable: true,
          path: 'general/web-search/SKILL.md',
          root: '/tmp/skills',
          updatedAt: 0,
          hasConflict: false,
          translatedName: '网络搜索',
        ),
      ]);
      await load;

      expect(controller.state.isLoading, false);
      expect(controller.state.skills.single.displayName, 'web-search');
    },
  );

  test(
    'SkillsController ignores stale skill list when selected gateway changes',
    () async {
      final api = _DelayedSkillsApiService();
      final controller = SkillsController(api);
      addTearDown(controller.dispose);

      await controller.syncGateways(const [
        GatewayInfo(
          gatewayId: 'openclaw',
          displayName: 'OpenClaw',
          gatewayType: 'openclaw',
          status: GatewayConnectionStatus.online,
          capabilities: ['skills'],
        ),
        GatewayInfo(
          gatewayId: 'hermes',
          displayName: 'Hermes',
          gatewayType: 'hermes',
          status: GatewayConnectionStatus.online,
          capabilities: ['skills'],
        ),
      ]);

      api.delayGatewayLoads();
      final hermesLoad = controller.selectGateway('hermes');
      final openClawLoad = controller.selectGateway('openclaw');

      api.completeOpenClaw();
      await openClawLoad;
      api.completeHermes();
      await hermesLoad;

      expect(controller.state.selectedScope?.gatewayId, 'openclaw');
      expect(controller.state.skills.map((skill) => skill.id), [
        'openclaw/skill',
      ]);
    },
  );

  test(
    'SkillsController ignores stale skill errors when selected gateway changes',
    () async {
      final api = _DelayedSkillsApiService();
      final controller = SkillsController(api);
      addTearDown(controller.dispose);

      await controller.syncGateways(const [
        GatewayInfo(
          gatewayId: 'openclaw',
          displayName: 'OpenClaw',
          gatewayType: 'openclaw',
          status: GatewayConnectionStatus.online,
          capabilities: ['skills'],
        ),
        GatewayInfo(
          gatewayId: 'hermes',
          displayName: 'Hermes',
          gatewayType: 'hermes',
          status: GatewayConnectionStatus.online,
          capabilities: ['skills'],
        ),
      ]);

      api.delayGatewayLoads();
      final hermesLoad = controller.selectGateway('hermes');
      final openClawLoad = controller.selectGateway('openclaw');

      api.completeOpenClaw();
      await openClawLoad;
      api.failHermes();
      await hermesLoad;

      expect(controller.state.selectedScope?.gatewayId, 'openclaw');
      expect(controller.state.skills.map((skill) => skill.id), [
        'openclaw/skill',
      ]);
      expect(controller.state.errorMessage, isNull);
    },
  );

  test(
    'SkillsController ignores older same-scope skill list after A B A switches',
    () async {
      final api = _DelayedSkillsApiService();
      final controller = SkillsController(api);
      addTearDown(controller.dispose);

      await controller.syncGateways(const [
        GatewayInfo(
          gatewayId: 'openclaw',
          displayName: 'OpenClaw',
          gatewayType: 'openclaw',
          status: GatewayConnectionStatus.online,
          capabilities: ['skills'],
        ),
        GatewayInfo(
          gatewayId: 'hermes',
          displayName: 'Hermes',
          gatewayType: 'hermes',
          status: GatewayConnectionStatus.online,
          capabilities: ['skills'],
        ),
      ]);

      api.delayGatewayLoads();
      final oldHermesLoad = controller.selectGateway('hermes');
      final openClawLoad = controller.selectGateway('openclaw');
      final newHermesLoad = controller.selectGateway('hermes');

      api.completeHermes(index: 1, skillId: 'hermes/new');
      await newHermesLoad;
      api.completeOpenClaw();
      await openClawLoad;
      api.completeHermes(index: 0, skillId: 'hermes/old');
      await oldHermesLoad;

      expect(controller.state.selectedScope?.gatewayId, 'hermes');
      expect(controller.state.skills.map((skill) => skill.id), ['hermes/new']);
      expect(controller.state.errorMessage, isNull);
    },
  );

  test(
    'SkillsController ignores older same-scope skill errors after A B A switches',
    () async {
      final api = _DelayedSkillsApiService();
      final controller = SkillsController(api);
      addTearDown(controller.dispose);

      await controller.syncGateways(const [
        GatewayInfo(
          gatewayId: 'openclaw',
          displayName: 'OpenClaw',
          gatewayType: 'openclaw',
          status: GatewayConnectionStatus.online,
          capabilities: ['skills'],
        ),
        GatewayInfo(
          gatewayId: 'hermes',
          displayName: 'Hermes',
          gatewayType: 'hermes',
          status: GatewayConnectionStatus.online,
          capabilities: ['skills'],
        ),
      ]);

      api.delayGatewayLoads();
      final oldHermesLoad = controller.selectGateway('hermes');
      final openClawLoad = controller.selectGateway('openclaw');
      final newHermesLoad = controller.selectGateway('hermes');

      api.completeHermes(index: 1, skillId: 'hermes/new');
      await newHermesLoad;
      api.completeOpenClaw();
      await openClawLoad;
      api.failHermes(index: 0);
      await oldHermesLoad;

      expect(controller.state.selectedScope?.gatewayId, 'hermes');
      expect(controller.state.skills.map((skill) => skill.id), ['hermes/new']);
      expect(controller.state.errorMessage, isNull);
    },
  );

  test(
    'SkillsController ignores stale public load skill list after gateway sync',
    () async {
      final api = _DelayedSkillsApiService();
      final controller = SkillsController(api);
      addTearDown(controller.dispose);

      await controller.syncGateways(const [
        GatewayInfo(
          gatewayId: 'hermes',
          displayName: 'Hermes',
          gatewayType: 'hermes',
          status: GatewayConnectionStatus.online,
          capabilities: ['skills'],
        ),
        GatewayInfo(
          gatewayId: 'openclaw',
          displayName: 'OpenClaw',
          gatewayType: 'openclaw',
          status: GatewayConnectionStatus.online,
          capabilities: ['skills'],
        ),
      ]);
      expect(controller.state.selectedScope?.gatewayId, 'hermes');

      api.delayGatewayLoads();
      final load = controller.load(force: true);
      await Future<void>.delayed(Duration.zero);
      final openClawLoad = controller.selectGateway('openclaw');

      api.completeOpenClaw();
      await openClawLoad;
      api.completeHermes();
      await load;

      expect(controller.state.selectedScope?.gatewayId, 'openclaw');
      expect(controller.state.skills.map((skill) => skill.id), [
        'openclaw/skill',
      ]);
      expect(controller.state.errorMessage, isNull);
      expect(controller.state.isLoading, false);
    },
  );

  test(
    'SkillsController ignores stale public load errors while gateway sync is loading',
    () async {
      final api = _DelayedSkillsApiService();
      final controller = SkillsController(api);
      addTearDown(controller.dispose);

      await controller.syncGateways(const [
        GatewayInfo(
          gatewayId: 'hermes',
          displayName: 'Hermes',
          gatewayType: 'hermes',
          status: GatewayConnectionStatus.online,
          capabilities: ['skills'],
        ),
        GatewayInfo(
          gatewayId: 'openclaw',
          displayName: 'OpenClaw',
          gatewayType: 'openclaw',
          status: GatewayConnectionStatus.online,
          capabilities: ['skills'],
        ),
      ]);
      expect(controller.state.selectedScope?.gatewayId, 'hermes');

      api.delayGatewayLoads();
      final load = controller.load(force: true);
      await Future<void>.delayed(Duration.zero);
      final openClawLoad = controller.selectGateway('openclaw');

      api.failHermes();
      await load;

      expect(controller.state.selectedScope?.gatewayId, 'openclaw');
      expect(controller.state.errorMessage, isNull);
      expect(controller.state.isLoading, true);

      api.completeOpenClaw();
      await openClawLoad;

      expect(controller.state.selectedScope?.gatewayId, 'openclaw');
      expect(controller.state.skills.map((skill) => skill.id), [
        'openclaw/skill',
      ]);
      expect(controller.state.errorMessage, isNull);
      expect(controller.state.isLoading, false);
    },
  );

  test('SkillsController clears stale skills when scope load fails', () async {
    final fake = _FailingSelectedScopeSkillsApiService([
      const ManagedSkill(
        id: 'apple/apple-notes',
        name: 'apple-notes',
        description: 'Manage Apple Notes',
        category: 'apple',
        enabled: true,
        source: 'external',
        sourceLabel: 'Hermes skills',
        writable: false,
        deletable: false,
        path: '/Users/samy/.hermes/skills/apple/apple-notes/SKILL.md',
        root: '/Users/samy/.hermes/skills',
        updatedAt: 0,
        hasConflict: false,
      ),
    ]);

    final container = ProviderContainer(
      overrides: _skillProviderOverrides(fake),
    );
    addTearDown(container.dispose);

    await container.read(skillsControllerProvider.notifier).load();
    expect(container.read(skillsControllerProvider).skills, isNotEmpty);

    await container
        .read(skillsControllerProvider.notifier)
        .selectScope('gateway:openclaw-lab');

    final state = container.read(skillsControllerProvider);
    expect(state.selectedScopeId, 'gateway:openclaw-lab');
    expect(state.skills, isEmpty);
    expect(state.errorMessage, 'OpenClaw 网关响应超时，请确认 OpenClaw Gateway 正在运行后重试。');
    expect(state.errorMessage, isNot(contains('DioException')));
  });

  test('SkillsController updates enabled state before API completes', () async {
    final fake = _SlowFakeSkillsApiService([
      const ManagedSkill(
        id: 'general/web-search',
        name: 'web-search',
        description: 'Search the web',
        category: 'general',
        enabled: true,
        source: 'managed',
        sourceLabel: 'Clawke managed',
        writable: true,
        deletable: true,
        path: 'general/web-search/SKILL.md',
        root: '/tmp/skills',
        updatedAt: 0,
        hasConflict: false,
      ),
    ]);

    final container = ProviderContainer(
      overrides: _skillProviderOverrides(fake),
    );
    addTearDown(container.dispose);

    await container.read(skillsControllerProvider.notifier).load();
    unawaited(
      container
          .read(skillsControllerProvider.notifier)
          .setEnabled('general/web-search', false),
    );
    await Future<void>.delayed(Duration.zero);

    final state = container.read(skillsControllerProvider);
    expect(state.skills.single.enabled, false);
    expect(state.togglingSkillIds, contains('general/web-search'));
  });
}

List<Override> _skillProviderOverrides(SkillsApiService api) {
  return [
    skillsApiServiceProvider.overrideWithValue(api),
    skillCacheRepositoryProvider.overrideWithValue(
      _ApiBackedSkillCacheRepository(api),
    ),
  ];
}

String _gatewayId(SkillScope scope) {
  final gatewayId = scope.gatewayId;
  if (gatewayId != null && gatewayId.isNotEmpty) return gatewayId;
  return 'global';
}

class _FailingScopesSkillsApiService extends SkillsApiService {
  _FailingScopesSkillsApiService(this.items);

  final List<ManagedSkill> items;
  bool legacyListCalled = false;

  @override
  Future<List<SkillScope>> listScopes() async {
    throw Exception('scopes unavailable');
  }

  @override
  Future<List<ManagedSkill>> listSkills({
    SkillScope? scope,
    String? locale,
  }) async {
    legacyListCalled = scope == null;
    return items;
  }
}

class _FailingSelectedScopeSkillsApiService extends _FakeSkillsApiService {
  _FailingSelectedScopeSkillsApiService(super.items);

  @override
  Future<List<ManagedSkill>> listSkills({
    SkillScope? scope,
    String? locale,
  }) async {
    if (scope?.id == 'gateway:openclaw-lab') {
      throw DioException(
        requestOptions: RequestOptions(path: '/api/skills'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/skills'),
          statusCode: 504,
          data: const {'error': 'gateway_timeout'},
        ),
        type: DioExceptionType.badResponse,
      );
    }
    return super.listSkills(scope: scope);
  }
}
