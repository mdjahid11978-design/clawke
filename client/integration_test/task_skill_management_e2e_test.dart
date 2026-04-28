import 'dart:async';

import 'package:client/data/database/app_database.dart';
import 'package:client/data/database/dao/gateway_dao.dart';
import 'package:client/data/database/dao/skill_cache_dao.dart';
import 'package:client/data/database/dao/task_cache_dao.dart';
import 'package:client/data/repositories/gateway_repository.dart';
import 'package:client/data/repositories/skill_cache_repository.dart';
import 'package:client/data/repositories/task_cache_repository.dart';
import 'package:client/l10n/app_localizations.dart';
import 'package:client/models/gateway_info.dart';
import 'package:client/models/managed_skill.dart';
import 'package:client/models/managed_task.dart';
import 'package:client/providers/auth_provider.dart';
import 'package:client/providers/database_providers.dart';
import 'package:client/screens/skills_management_screen.dart';
import 'package:client/screens/tasks_management_screen.dart';
import 'package:client/services/gateways_api_service.dart';
import 'package:client/services/skills_api_service.dart';
import 'package:client/services/tasks_api_service.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _userId = 'mac-e2e-user';

const _gateway = GatewayInfo(
  gatewayId: 'hermes',
  displayName: 'Hermes',
  gatewayType: 'hermes',
  status: GatewayConnectionStatus.online,
  capabilities: ['chat', 'tasks', 'skills', 'models'],
);

const _scope = SkillScope(
  id: 'gateway:hermes',
  type: 'gateway',
  label: 'Hermes',
  description: 'Gateway',
  readonly: false,
  gatewayId: 'hermes',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({'clawke_locale': 'zh'});
  });

  testWidgets('macOS task management uses cache first then remote refresh', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    final gatewayRepo = GatewayRepository(
      dao: GatewayDao(db),
      api: _FakeGatewaysApi([_gateway]),
    );
    await gatewayRepo.syncFromServer();

    final seedApi = _FakeTasksApiService()
      ..listResponse = [_task('cached-weather', '缓存天气任务')];
    final taskRepo = TaskCacheRepository(
      dao: TaskCacheDao(db),
      api: seedApi,
      userId: _userId,
    );
    await taskRepo.syncGateway('hermes');

    final remoteCompleter = Completer<List<ManagedTask>>();
    final tasksApi = _FakeTasksApiService()..listCompleter = remoteCompleter;

    await _pumpSubject(
      tester,
      db: db,
      gatewayRepo: gatewayRepo,
      tasksApi: tasksApi,
      child: const TasksManagementScreen(),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('任务管理'), findsOneWidget);
    expect(find.text('缓存天气任务'), findsOneWidget);
    expect(tasksApi.lastListAccountId, 'hermes');

    remoteCompleter.complete([_task('remote-weather', '远端天气任务')]);
    await _pumpFrames(tester);

    expect(find.text('缓存天气任务'), findsNothing);
    expect(find.text('远端天气任务'), findsOneWidget);
  });

  testWidgets(
    'macOS skill management renders translated cache and detail source',
    (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      final gatewayRepo = GatewayRepository(
        dao: GatewayDao(db),
        api: _FakeGatewaysApi([_gateway]),
      );
      await gatewayRepo.syncFromServer();

      final seedApi = _FakeSkillsApiService()
        ..listResponse = [
          _skill(
            sourceHash: 'hash-cached',
            translatedName: '网页搜索',
            translatedDescription: '搜索网页',
          ),
        ];
      final skillRepo = SkillCacheRepository(
        dao: SkillCacheDao(db),
        api: seedApi,
        userId: _userId,
      );
      await skillRepo.syncGateway(_scope, 'zh');

      final listCompleter = Completer<List<ManagedSkill>>();
      final skillsApi = _FakeSkillsApiService()
        ..listCompleter = listCompleter
        ..detailResponse = _skill(
          trigger: 'Use when web lookup is needed',
          body: '## Source body\n',
          sourceHash: 'hash-detail',
          translatedName: '网络搜索',
          translatedDescription: '联网搜索',
          translatedTrigger: '需要联网搜索时使用',
          translatedBody: '## 翻译正文\n',
        );

      await _pumpSubject(
        tester,
        db: db,
        gatewayRepo: gatewayRepo,
        skillsApi: skillsApi,
        child: const SkillsManagementScreen(),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(skillsApi.lastListLocale, 'zh');
      expect(find.text('web-search'), findsOneWidget);
      expect(find.text('搜索网页'), findsOneWidget);
      expect(find.text('网页搜索'), findsNothing);

      listCompleter.complete([
        _skill(
          trigger: 'Use when web lookup is needed',
          body: '## Source body\n',
          sourceHash: 'hash-remote',
          translatedName: '网络搜索',
          translatedDescription: '联网搜索',
          translatedTrigger: '需要联网搜索时使用',
          translatedBody: '## 翻译正文\n',
        ),
      ]);
      await _pumpFrames(tester);

      expect(find.text('web-search'), findsOneWidget);
      expect(find.text('联网搜索'), findsOneWidget);
      expect(find.text('网络搜索'), findsNothing);

      await tester.tap(find.widgetWithText(OutlinedButton, '编辑').first);
      await _pumpFrames(tester);

      expect(skillsApi.lastDetailLocale, isNull);
      final fields = find.byType(TextFormField);
      expect(
        tester.widget<TextFormField>(fields.at(0)).controller?.text,
        'web-search',
      );
      expect(
        tester.widget<TextFormField>(fields.at(2)).controller?.text,
        'Use when web lookup is needed',
      );
      expect(
        tester.widget<TextFormField>(fields.at(3)).controller?.text,
        'Search the web',
      );
      expect(
        tester.widget<TextFormField>(fields.at(4)).controller?.text,
        '## Source body\n',
      );
    },
  );
}

Future<void> _pumpSubject(
  WidgetTester tester, {
  required AppDatabase db,
  required GatewayRepository gatewayRepo,
  TasksApiService? tasksApi,
  SkillsApiService? skillsApi,
  required Widget child,
}) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserUidProvider.overrideWithValue(_userId),
        databaseProvider.overrideWithValue(db),
        gatewayRepositoryProvider.overrideWithValue(gatewayRepo),
        if (tasksApi != null)
          tasksApiServiceProvider.overrideWithValue(tasksApi),
        if (skillsApi != null)
          skillsApiServiceProvider.overrideWithValue(skillsApi),
      ],
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      ),
    ),
  );
}

Future<void> _pumpFrames(WidgetTester tester) async {
  for (var i = 0; i < 8; i += 1) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

ManagedTask _task(String id, String name) {
  return ManagedTask(
    id: id,
    accountId: 'hermes',
    agent: 'Hermes',
    name: name,
    schedule: '0 9 * * *',
    scheduleText: '每天 09:00',
    prompt: '查询杭州天气',
    enabled: true,
    status: 'active',
    skills: const ['web-search'],
    createdAt: '2026-04-25T00:00:00Z',
    updatedAt: '2026-04-25T00:00:00Z',
  );
}

ManagedSkill _skill({
  String? trigger,
  String? body,
  required String sourceHash,
  String? translatedName,
  String? translatedDescription,
  String? translatedTrigger,
  String? translatedBody,
}) {
  return ManagedSkill(
    id: 'general/web-search',
    name: 'web-search',
    description: 'Search the web',
    category: 'general',
    trigger: trigger,
    body: body,
    enabled: true,
    source: 'managed',
    sourceLabel: 'Clawke managed',
    writable: true,
    deletable: true,
    path: 'general/web-search/SKILL.md',
    root: '/tmp/skills',
    updatedAt: 0,
    hasConflict: false,
    sourceHash: sourceHash,
    localizationLocale: translatedName == null ? null : 'zh',
    localizationStatus: translatedName == null ? null : 'ready',
    translatedName: translatedName,
    translatedDescription: translatedDescription,
    translatedTrigger: translatedTrigger,
    translatedBody: translatedBody,
  );
}

class _FakeGatewaysApi implements GatewaysApi {
  _FakeGatewaysApi(this.gateways);

  final List<GatewayInfo> gateways;

  @override
  Future<List<GatewayInfo>> listGateways() async => gateways;

  @override
  Future<void> renameGateway(String gatewayId, String displayName) async {}
}

class _FakeTasksApiService extends TasksApiService {
  List<ManagedTask> listResponse = const [];
  Completer<List<ManagedTask>>? listCompleter;
  String? lastListAccountId;

  @override
  Future<List<ManagedTask>> listTasks({String? accountId}) {
    lastListAccountId = accountId;
    return listCompleter?.future ?? Future.value(listResponse);
  }
}

class _FakeSkillsApiService extends SkillsApiService {
  List<ManagedSkill> listResponse = const [];
  Completer<List<ManagedSkill>>? listCompleter;
  ManagedSkill? detailResponse;
  String? lastListLocale;
  String? lastDetailLocale;

  @override
  Future<List<SkillScope>> listScopes() async => const [_scope];

  @override
  Future<List<ManagedSkill>> listSkills({SkillScope? scope, String? locale}) {
    lastListLocale = locale;
    return listCompleter?.future ?? Future.value(listResponse);
  }

  @override
  Future<ManagedSkill> getSkill(
    String id, {
    SkillScope? scope,
    String? locale,
  }) async {
    lastDetailLocale = locale;
    return detailResponse ?? _skill(sourceHash: 'hash-detail');
  }
}
