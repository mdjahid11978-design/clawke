# Task and Skill Cache with Skill Translation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为任务列表和技能列表增加 DB-first 缓存，并为 skill 增加 Server + Client 双端翻译缓存。

**Architecture:** Client 使用 Drift 缓存 task 定义、skill metadata/detail 和 skill localization，页面优先读 DB，再异步同步 Server。Server 不缓存 task 真相，只转发 Gateway；Server 缓存 skill 翻译并负责去重、排队和后台翻译。所有 mutation 坚持 server-first，失败不做本地乐观写入。

**Tech Stack:** Flutter + Riverpod + Drift + Dio；Node.js/Express + better-sqlite3 + node:test；Gateway request/response over upstream WebSocket。

---

## 执行约束

- 不提交 git，除非用户明确要求。
- 不操作生产 DB。Server tests 必须用 `:memory:` 或临时目录。
- 修改核心状态逻辑必须先写 failing test，再实现。
- 完成每个任务后更新本计划 checkbox。
- 任务执行记录、输出、output preview 不进入本地 task cache。
- Task 不做翻译。
- Skill 翻译只通过 Server 发起，Client 不持有模型 API Key。
- Skill `name` 始终显示原文；当前实现只翻译 `description`，不翻译 `trigger/body`。

## 文件结构

### Client Task Cache

- Create: `client/lib/data/database/tables/task_cache.drift`
  - 保存 task 定义快照，不包含 `lastRun`。
- Create: `client/lib/data/database/dao/task_cache_dao.dart`
  - watch/upsert/deleteMissing/delete 操作。
- Create: `client/lib/data/repositories/task_cache_repository.dart`
  - DB-first watch，同步 Server 快照，server-first mutation 后更新缓存。
- Modify: `client/lib/data/database/app_database.dart`
  - include `task_cache.drift`，schema version +1，migration 建表。
- Modify: `client/lib/providers/database_providers.dart`
  - 注册 `TaskCacheDao` 和 `TaskCacheRepository`。
- Modify: `client/lib/providers/tasks_provider.dart`
  - Controller 从 cache repository watch 当前 gateway tasks。
  - 刷新时调用 Server，并校验请求返回仍属于当前 gateway。
- Modify: `client/lib/screens/tasks_management_screen.dart`
  - 保持页面使用 controller state，不直接关心 cache。
- Test: `client/test/data/database/task_cache_dao_test.dart`
- Test: `client/test/providers/task_cache_repository_test.dart`
- Test: update `client/test/tasks_provider_test.dart`
- Test: update `client/test/tasks_management_screen_test.dart`

### Client Skill Cache and Localization

- Create: `client/lib/data/database/tables/skill_cache.drift`
  - 保存 skill metadata/detail source fields。
- Create: `client/lib/data/database/tables/skill_localizations.drift`
  - 保存当前用户本地翻译结果。
- Create: `client/lib/data/database/dao/skill_cache_dao.dart`
  - watch/upsert/deleteMissing/detail/localization 操作。
- Create: `client/lib/data/repositories/skill_cache_repository.dart`
  - DB-first watch，同步 Server skill list/detail，写入 localization。
- Modify: `client/lib/data/database/app_database.dart`
  - include skill cache tables，schema version +1，migration 建表。
- Modify: `client/lib/models/managed_skill.dart`
  - 增加 localization 字段和 display getters。
- Modify: `client/lib/services/skills_api_service.dart`
  - 请求带 `locale`，解析 `localization`。
- Modify: `client/lib/providers/database_providers.dart`
  - 注册 `SkillCacheDao` 和 `SkillCacheRepository`。
- Modify: `client/lib/providers/skills_provider.dart`
  - Controller 使用 cache repository，详情按需缓存，切换 gateway 时防旧请求覆盖。
- Modify: `client/lib/screens/skills_management_screen.dart`
  - 列表和详情优先显示 display 字段；编辑表单使用原文字段。
- Test: `client/test/data/database/skill_cache_dao_test.dart`
- Test: `client/test/providers/skill_cache_repository_test.dart`
- Test: update `client/test/skills_provider_test.dart`
- Test: update `client/test/skills_management_screen_test.dart`

### Server Skill Translation

- Create: `server/src/store/skill-translation-store.ts`
  - `skill_translation_cache` 和 `skill_translation_jobs` 访问层。
- Create: `server/src/services/skill-translation-service.ts`
  - source hash、cache lookup、job enqueue、translator 调用。
- Create: `server/src/types/skill-translation.ts`
  - translation cache/job/domain types。
- Modify: `server/src/store/database.ts`
  - 新增 translation cache/job 表和 migration。
- Modify: `server/src/routes/skills-routes.ts`
  - 读取 `locale`，返回 ready localization；缺失时 enqueue job。
- Modify: `server/src/index.ts`
  - 初始化 translation service 并注入 skills routes。
- Test: `server/test/skill-translation-store.test.js`
- Test: `server/test/skill-translation-service.test.js`
- Test: update `server/test/skills-routes.test.js`

---

## Task 1: Fix Existing Gateway UI and Async Race Regressions

**Files:**
- Modify: `client/lib/screens/tasks_management_screen.dart`
- Modify: `client/lib/providers/tasks_provider.dart`
- Modify: `client/lib/providers/skills_provider.dart`
- Test: update `client/test/tasks_management_screen_test.dart`
- Test: update `client/test/skills_management_screen_test.dart`

- [x] **Step 1: 写任务页红色告警 failing test**

在 `client/test/tasks_management_screen_test.dart` 中现有 gateway timeout 测试增加断言：

```dart
final notice = tester.widget<AppNoticeBar>(
  find.byKey(const ValueKey('app_notice_bar')),
);
expect(notice.severity, AppNoticeSeverity.error);
```

Run:

```bash
cd client && flutter test test/tasks_management_screen_test.dart
```

Expected: FAIL，因为当前 severity 是 warning。

- [x] **Step 2: 修复任务页告警 severity**

将 `client/lib/screens/tasks_management_screen.dart` 中 Gateway 错误提示：

```dart
severity: AppNoticeSeverity.warning,
```

改为：

```dart
severity: AppNoticeSeverity.error,
```

- [x] **Step 3: 写任务快速切换竞态 failing test**

在 `client/test/tasks_provider_test.dart` 增加测试。测试 API 让 `hermes` 延迟返回，`openclaw` 立即返回。

```dart
test('ignores stale task list when selected gateway changes', () async {
  final api = _DelayedTasksApiService();
  final controller = TasksController(api);

  await controller.syncAccounts(const [
    TaskAccount(accountId: 'hermes', agentName: 'Hermes'),
    TaskAccount(accountId: 'openclaw', agentName: 'OpenClaw'),
  ]);

  final hermesLoad = controller.load(accountId: 'hermes', force: true);
  final openclawLoad = controller.load(accountId: 'openclaw', force: true);

  api.completeOpenClaw();
  await openclawLoad;
  api.completeHermes();
  await hermesLoad;

  expect(controller.state.selectedAccountId, 'openclaw');
  expect(controller.state.tasks.map((task) => task.accountId), ['openclaw']);
});
```

Run:

```bash
cd client && flutter test test/tasks_provider_test.dart
```

Expected: FAIL，旧请求可能覆盖当前列表。

- [x] **Step 4: 修复任务 provider 竞态**

在 `TasksController.load()` 记录 request gateway，返回后校验：

```dart
final requestAccountId = selected;
final tasks = await _api.listTasks(accountId: requestAccountId);
if (state.selectedAccountId != requestAccountId) return;
state = state.copyWith(tasks: tasks, isLoading: false);
```

catch 分支也校验：

```dart
if (state.selectedAccountId != requestAccountId) return;
```

- [x] **Step 5: 写技能快速切换竞态 failing test**

在 `client/test/skills_provider_test.dart` 增加测试：

```dart
test('ignores stale skill list when selected gateway changes', () async {
  final api = _DelayedSkillsApiService();
  final controller = SkillsController(api);

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

  final hermesLoad = controller.selectGateway('hermes');
  final openclawLoad = controller.selectGateway('openclaw');

  api.completeOpenClaw();
  await openclawLoad;
  api.completeHermes();
  await hermesLoad;

  expect(controller.state.selectedScope?.gatewayId, 'openclaw');
  expect(controller.state.skills.map((skill) => skill.id), ['openclaw/skill']);
});
```

Run:

```bash
cd client && flutter test test/skills_provider_test.dart
```

Expected: FAIL，旧请求可能覆盖当前列表。

- [x] **Step 6: 修复技能 provider 竞态**

在 `SkillsController._loadScopedList()` 记录 request scope id，返回后校验：

```dart
final requestScopeId = selectedScope.id;
final skills = await _api.listSkills(scope: selectedScope);
if (state.selectedScopeId != requestScopeId) return;
state = state.copyWith(skills: skills, isLoading: false);
```

catch 分支也校验：

```dart
if (state.selectedScopeId != requestScopeId) return;
```

- [x] **Step 7: 运行 Task 1 测试**

```bash
cd client && flutter test test/tasks_provider_test.dart test/skills_provider_test.dart test/tasks_management_screen_test.dart test/skills_management_screen_test.dart
cd client && dart analyze lib/providers/tasks_provider.dart lib/providers/skills_provider.dart lib/screens/tasks_management_screen.dart
```

Expected: PASS / No issues found.

---

## Task 2: Client Task Cache Schema and DAO

**Files:**
- Create: `client/lib/data/database/tables/task_cache.drift`
- Create: `client/lib/data/database/dao/task_cache_dao.dart`
- Modify: `client/lib/data/database/app_database.dart`
- Test: `client/test/data/database/task_cache_dao_test.dart`

- [x] **Step 1: 写 failing DAO test**

创建 `client/test/data/database/task_cache_dao_test.dart`：

```dart
import 'package:client/data/database/app_database.dart';
import 'package:client/data/database/dao/task_cache_dao.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late TaskCacheDao dao;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dao = TaskCacheDao(db);
  });

  tearDown(() => db.close());

  test('upserts task definitions without lastRun fields', () async {
    await dao.upsertTask(TaskCacheCompanion.insert(
      userId: 'u1',
      gatewayId: 'hermes',
      taskId: 'task_1',
      name: 'Daily',
      schedule: '0 9 * * *',
      prompt: 'Summarize',
      enabled: true,
      status: 'active',
      skillsJson: const Value('["notes"]'),
      syncedAt: 100,
    ));

    final rows = await dao.getTasks('u1', 'hermes');
    expect(rows, hasLength(1));
    expect(rows.single.taskId, 'task_1');
    expect(rows.single.name, 'Daily');
  });

  test('deleteMissing only removes tasks for the same user and gateway', () async {
    await dao.upsertTask(TaskCacheCompanion.insert(
      userId: 'u1',
      gatewayId: 'hermes',
      taskId: 'keep',
      name: 'Keep',
      schedule: '* * * * *',
      prompt: 'Keep',
      enabled: true,
      status: 'active',
      syncedAt: 100,
    ));
    await dao.upsertTask(TaskCacheCompanion.insert(
      userId: 'u1',
      gatewayId: 'openclaw',
      taskId: 'other_gateway',
      name: 'Other',
      schedule: '* * * * *',
      prompt: 'Other',
      enabled: true,
      status: 'active',
      syncedAt: 100,
    ));

    await dao.deleteMissing('u1', 'hermes', {'keep'});

    expect(await dao.getTasks('u1', 'hermes'), hasLength(1));
    expect(await dao.getTasks('u1', 'openclaw'), hasLength(1));
  });
}
```

Run:

```bash
cd client && flutter test test/data/database/task_cache_dao_test.dart
```

Expected: FAIL because DAO/table do not exist.

- [x] **Step 2: 创建 task cache Drift table**

创建 `client/lib/data/database/tables/task_cache.drift`：

```sql
CREATE TABLE task_cache (
  user_id TEXT NOT NULL,
  gateway_id TEXT NOT NULL,
  task_id TEXT NOT NULL,
  name TEXT NOT NULL,
  schedule TEXT NOT NULL,
  schedule_text TEXT,
  prompt TEXT NOT NULL,
  enabled BOOLEAN NOT NULL,
  status TEXT NOT NULL,
  skills_json TEXT NOT NULL DEFAULT '[]',
  deliver TEXT,
  created_at TEXT,
  updated_at TEXT,
  synced_at INTEGER NOT NULL,
  PRIMARY KEY (user_id, gateway_id, task_id)
);

watchTasks: SELECT * FROM task_cache
  WHERE user_id = :user_id AND gateway_id = :gateway_id
  ORDER BY name COLLATE NOCASE ASC, task_id ASC;

getTasks: SELECT * FROM task_cache
  WHERE user_id = :user_id AND gateway_id = :gateway_id
  ORDER BY name COLLATE NOCASE ASC, task_id ASC;

getTask: SELECT * FROM task_cache
  WHERE user_id = :user_id AND gateway_id = :gateway_id AND task_id = :task_id;
```

- [x] **Step 3: 创建 TaskCacheDao**

创建 `client/lib/data/database/dao/task_cache_dao.dart`：

```dart
import 'package:client/data/database/app_database.dart';
import 'package:drift/drift.dart';

part 'task_cache_dao.g.dart';

@DriftAccessor(tables: [TaskCache])
class TaskCacheDao extends DatabaseAccessor<AppDatabase>
    with _$TaskCacheDaoMixin {
  TaskCacheDao(super.db);

  Stream<List<TaskCacheData>> watchTasks(String userId, String gatewayId) {
    return (select(taskCache)
          ..where((row) => row.userId.equals(userId))
          ..where((row) => row.gatewayId.equals(gatewayId))
          ..orderBy([
            (row) => OrderingTerm.asc(row.name),
            (row) => OrderingTerm.asc(row.taskId),
          ]))
        .watch();
  }

  Future<List<TaskCacheData>> getTasks(String userId, String gatewayId) {
    return (select(taskCache)
          ..where((row) => row.userId.equals(userId))
          ..where((row) => row.gatewayId.equals(gatewayId))
          ..orderBy([
            (row) => OrderingTerm.asc(row.name),
            (row) => OrderingTerm.asc(row.taskId),
          ]))
        .get();
  }

  Future<void> upsertTask(TaskCacheCompanion task) {
    return into(taskCache).insertOnConflictUpdate(task);
  }

  Future<void> deleteTask(String userId, String gatewayId, String taskId) {
    return (delete(taskCache)
          ..where((row) => row.userId.equals(userId))
          ..where((row) => row.gatewayId.equals(gatewayId))
          ..where((row) => row.taskId.equals(taskId)))
        .go();
  }

  Future<void> deleteMissing(
    String userId,
    String gatewayId,
    Set<String> remoteIds,
  ) async {
    final rows = await getTasks(userId, gatewayId);
    for (final row in rows) {
      if (!remoteIds.contains(row.taskId)) {
        await deleteTask(userId, gatewayId, row.taskId);
      }
    }
  }
}
```

- [x] **Step 4: 注册 table/DAO 并生成代码**

修改 `client/lib/data/database/app_database.dart`：

```dart
import 'package:client/data/database/dao/task_cache_dao.dart';
```

在 `@DriftDatabase` 增加：

```dart
include: {
  'tables/task_cache.drift',
}
```

schemaVersion +1，并在 migration 增加：

```dart
if (from < 9) {
  await m.createTable(taskCache);
}
```

Run:

```bash
cd client && dart run build_runner build --delete-conflicting-outputs
```

Expected: generated files updated.

- [x] **Step 5: 运行 Task 2 测试**

```bash
cd client && flutter test test/data/database/task_cache_dao_test.dart
cd client && dart analyze lib/data/database
```

Expected: PASS / No issues found.

---

## Task 3: Client Task Cache Repository and Controller Integration

**Files:**
- Create: `client/lib/data/repositories/task_cache_repository.dart`
- Modify: `client/lib/providers/database_providers.dart`
- Modify: `client/lib/providers/tasks_provider.dart`
- Test: `client/test/providers/task_cache_repository_test.dart`
- Test: update `client/test/tasks_provider_test.dart`

- [x] **Step 1: 写 repository failing test**

创建 `client/test/providers/task_cache_repository_test.dart`：

```dart
import 'package:client/data/database/app_database.dart';
import 'package:client/data/database/dao/task_cache_dao.dart';
import 'package:client/data/repositories/task_cache_repository.dart';
import 'package:client/models/managed_task.dart';
import 'package:client/services/tasks_api_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeTasksApi extends TasksApiService {
  List<ManagedTask> tasks = const [];

  @override
  Future<List<ManagedTask>> listTasks({String? accountId}) async => tasks;
}

void main() {
  test('sync stores task definitions and strips lastRun', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final api = _FakeTasksApi()
      ..tasks = const [
        ManagedTask(
          id: 'task_1',
          accountId: 'hermes',
          agent: 'Hermes',
          name: 'Daily',
          schedule: '0 9 * * *',
          prompt: 'Summarize',
          enabled: true,
          status: 'active',
          lastRun: TaskRun(
            id: 'run_1',
            taskId: 'task_1',
            startedAt: '2026-04-25T09:00:00Z',
            status: 'success',
          ),
        ),
      ];
    final repo = TaskCacheRepository(
      dao: TaskCacheDao(db),
      api: api,
      userId: 'u1',
    );

    await repo.syncGateway('hermes');
    final cached = await repo.getTasks('hermes');

    expect(cached, hasLength(1));
    expect(cached.single.id, 'task_1');
    expect(cached.single.lastRun, isNull);
    await db.close();
  });
}
```

Run:

```bash
cd client && flutter test test/providers/task_cache_repository_test.dart
```

Expected: FAIL because repository does not exist.

- [x] **Step 2: 实现 TaskCacheRepository**

创建 `client/lib/data/repositories/task_cache_repository.dart`，提供：

```dart
class TaskCacheRepository {
  TaskCacheRepository({
    required TaskCacheDao dao,
    required TasksApiService api,
    required String userId,
  });

  Stream<List<ManagedTask>> watchTasks(String gatewayId);
  Future<List<ManagedTask>> getTasks(String gatewayId);
  Future<List<ManagedTask>> syncGateway(String gatewayId);
  Future<ManagedTask> create(TaskDraft draft);
  Future<ManagedTask> update(String id, TaskDraft draft);
  Future<void> delete(ManagedTask task);
  Future<ManagedTask?> setEnabled(ManagedTask task, bool enabled);
}
```

Mapping rule:

```dart
ManagedTask(
  id: row.taskId,
  accountId: row.gatewayId,
  agent: row.gatewayId,
  name: row.name,
  schedule: row.schedule,
  scheduleText: row.scheduleText,
  prompt: row.prompt,
  enabled: row.enabled,
  status: row.status,
  skills: decodeSkills(row.skillsJson),
  deliver: row.deliver,
  createdAt: row.createdAt,
  updatedAt: row.updatedAt,
  lastRun: null,
)
```

When mapping API result to DB, never write `lastRun`.

- [x] **Step 3: 注册 provider**

修改 `client/lib/providers/database_providers.dart`：

```dart
final taskCacheDaoProvider = Provider<TaskCacheDao>((ref) {
  return TaskCacheDao(ref.watch(databaseProvider));
});

final taskCacheRepositoryProvider = Provider<TaskCacheRepository>((ref) {
  return TaskCacheRepository(
    dao: ref.watch(taskCacheDaoProvider),
    api: ref.watch(tasksApiServiceProvider),
    userId: ref.watch(currentUserUidProvider),
  );
});
```

- [x] **Step 4: 更新 TasksController 使用 repository**

将 `TasksController` 构造改为接收 repository。保留 `TasksApiService` 用于 runs/output，或由 repository 暴露 runs/output passthrough。

关键行为：

```dart
Future<void> load({String? accountId, bool force = false}) async {
  final selected = accountId ?? state.selectedAccountId;
  if (selected == null) return;
  final requestAccountId = selected;

  state = state.copyWith(selectedAccountId: selected, isLoading: true);

  final cached = await _cache.getTasks(requestAccountId);
  if (state.selectedAccountId == requestAccountId && cached.isNotEmpty) {
    state = state.copyWith(tasks: cached);
  }

  try {
    final remote = await _cache.syncGateway(requestAccountId);
    if (state.selectedAccountId != requestAccountId) return;
    state = state.copyWith(tasks: remote, isLoading: false);
  } catch (e) {
    if (state.selectedAccountId != requestAccountId) return;
    state = state.copyWith(isLoading: false, errorMessage: _taskErrorMessage(e));
  }
}
```

- [x] **Step 5: 更新 provider tests**

在 `client/test/tasks_provider_test.dart` 增加：

```dart
test('loads cached tasks before remote sync completes', () async {
  final repo = _FakeTaskCacheRepository(
    cached: const [ManagedTask(...)],
    remoteCompleter: Completer<List<ManagedTask>>(),
  );
  final controller = TasksController(repo);

  final future = controller.load(accountId: 'hermes', force: true);
  await Future<void>.delayed(Duration.zero);

  expect(controller.state.tasks.map((task) => task.id), ['cached_task']);

  repo.remoteCompleter.complete(const [ManagedTask(...)]);
  await future;

  expect(controller.state.tasks.map((task) => task.id), ['remote_task']);
});
```

Run:

```bash
cd client && flutter test test/providers/task_cache_repository_test.dart test/tasks_provider_test.dart test/tasks_management_screen_test.dart
```

Expected: PASS.

---

## Task 4: Client Skill Cache Schema, DAO, and Localized Model

**Files:**
- Create: `client/lib/data/database/tables/skill_cache.drift`
- Create: `client/lib/data/database/tables/skill_localizations.drift`
- Create: `client/lib/data/database/dao/skill_cache_dao.dart`
- Modify: `client/lib/data/database/app_database.dart`
- Modify: `client/lib/models/managed_skill.dart`
- Test: `client/test/data/database/skill_cache_dao_test.dart`
- Test: update `client/test/skills_management_screen_test.dart`

- [x] **Step 1: 写 skill cache DAO failing test**

创建 `client/test/data/database/skill_cache_dao_test.dart`，验证：

```dart
test('watch returns localized display fields when ready', () async {
  await dao.upsertSkill(... source name 'web-search' ...);
  await dao.upsertLocalization(... locale 'zh-CN', translatedName '网页搜索', status 'ready' ...);

  final rows = await dao.getSkills('u1', 'hermes', locale: 'zh-CN');

  expect(rows.single.translatedName, '网页搜索');
  expect(rows.single.name, 'web-search');
});
```

Run:

```bash
cd client && flutter test test/data/database/skill_cache_dao_test.dart
```

Expected: FAIL because tables/DAO do not exist.

- [x] **Step 2: 创建 skill cache tables**

创建 `client/lib/data/database/tables/skill_cache.drift`：

```sql
CREATE TABLE skill_cache (
  user_id TEXT NOT NULL,
  gateway_id TEXT NOT NULL,
  skill_id TEXT NOT NULL,
  name TEXT NOT NULL,
  description TEXT NOT NULL,
  category TEXT NOT NULL,
  enabled BOOLEAN NOT NULL,
  source TEXT NOT NULL,
  source_label TEXT NOT NULL,
  writable BOOLEAN NOT NULL,
  deletable BOOLEAN NOT NULL,
  path TEXT NOT NULL,
  root TEXT NOT NULL,
  updated_at REAL NOT NULL DEFAULT 0,
  has_conflict BOOLEAN NOT NULL DEFAULT FALSE,
  trigger TEXT,
  body TEXT,
  content TEXT,
  source_hash TEXT NOT NULL DEFAULT '',
  detail_fetched_at INTEGER,
  synced_at INTEGER NOT NULL,
  PRIMARY KEY (user_id, gateway_id, skill_id)
);
```

创建 `client/lib/data/database/tables/skill_localizations.drift`：

```sql
CREATE TABLE skill_localizations (
  user_id TEXT NOT NULL,
  gateway_id TEXT NOT NULL,
  skill_id TEXT NOT NULL,
  locale TEXT NOT NULL,
  source_hash TEXT NOT NULL,
  translated_name TEXT,
  translated_description TEXT,
  translated_trigger TEXT,
  translated_body TEXT,
  status TEXT NOT NULL,
  error_code TEXT,
  error_message TEXT,
  updated_at INTEGER NOT NULL,
  PRIMARY KEY (user_id, gateway_id, skill_id, locale)
);
```

- [x] **Step 3: 创建 SkillCacheDao**

DAO 必须提供：

```dart
Stream<List<SkillWithLocalization>> watchSkills(
  String userId,
  String gatewayId, {
  required String locale,
});

Future<List<SkillWithLocalization>> getSkills(
  String userId,
  String gatewayId, {
  required String locale,
});

Future<void> upsertSkill(SkillCacheCompanion skill);
Future<void> upsertLocalization(SkillLocalizationsCompanion localization);
Future<void> deleteMissing(String userId, String gatewayId, Set<String> remoteIds);
Future<void> deleteSkill(String userId, String gatewayId, String skillId);
```

`SkillWithLocalization` 是 DAO-level value object，包含 source row + optional localization row。

- [x] **Step 4: 扩展 ManagedSkill localization 字段**

修改 `client/lib/models/managed_skill.dart`：

```dart
final String? sourceHash;
final String? localizationLocale;
final String? localizationStatus;
final String? translatedName;
final String? translatedDescription;
final String? translatedTrigger;
final String? translatedBody;

String get displayName => name;
String get displayDescription => translatedDescription ?? description;
String? get displayTrigger => translatedTrigger ?? trigger;
String? get displayBody => translatedBody ?? body;
```

`fromJson` 解析：

```dart
final localization = json['localization'] as Map?;
translatedName: null,
translatedDescription: localization?['description'] as String?,
translatedTrigger: localization?['trigger'] as String?,
translatedBody: localization?['body'] as String?,
```

- [x] **Step 5: 注册 tables 并生成代码**

修改 `client/lib/data/database/app_database.dart`：

```dart
include: {
  'tables/skill_cache.drift',
  'tables/skill_localizations.drift',
}
```

schemaVersion +1：

```dart
if (from < 10) {
  await m.createTable(skillCache);
  await m.createTable(skillLocalizations);
}
```

Run:

```bash
cd client && dart run build_runner build --delete-conflicting-outputs
```

- [x] **Step 6: 更新 UI 使用 display 字段**

在 `client/lib/screens/skills_management_screen.dart`：

- 搜索使用 `displayName/displayDescription`。
- 卡片 title 使用 `displayName`。
- 卡片 description 使用 `displayDescription`。
- 详情阅读展示使用 `displayBody`。
- 编辑表单仍使用 source fields：`name/description/trigger/body`。

- [x] **Step 7: 运行 Task 4 测试**

```bash
cd client && flutter test test/data/database/skill_cache_dao_test.dart test/skills_management_screen_test.dart
cd client && dart analyze lib/models/managed_skill.dart lib/data/database lib/screens/skills_management_screen.dart
```

Expected: PASS / No issues found.

---

## Task 5: Client Skill Cache Repository and Controller Integration

**Files:**
- Create: `client/lib/data/repositories/skill_cache_repository.dart`
- Modify: `client/lib/services/skills_api_service.dart`
- Modify: `client/lib/providers/database_providers.dart`
- Modify: `client/lib/providers/skills_provider.dart`
- Test: `client/test/providers/skill_cache_repository_test.dart`
- Test: update `client/test/skills_provider_test.dart`

- [x] **Step 1: 写 repository failing test**

创建 `client/test/providers/skill_cache_repository_test.dart`：

```dart
test('sync stores source fields and ready localization', () async {
  final api = _FakeSkillsApiService()
    ..skills = const [
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

  final repo = SkillCacheRepository(... locale: 'zh-CN');
  await repo.syncGateway(_scope('hermes'));
  final skills = await repo.getSkills('hermes');

  expect(skills.single.name, 'web-search');
  expect(skills.single.displayName, '网页搜索');
});
```

Run:

```bash
cd client && flutter test test/providers/skill_cache_repository_test.dart
```

Expected: FAIL because repository does not exist.

- [x] **Step 2: 更新 SkillsApiService 支持 locale**

方法签名调整：

```dart
Future<List<ManagedSkill>> listSkills({
  SkillScope? scope,
  String? locale,
});

Future<ManagedSkill> getSkill(
  String id, {
  SkillScope? scope,
  String? locale,
});
```

请求 query 增加：

```dart
if (locale != null && locale.isNotEmpty) 'locale': locale,
```

- [x] **Step 3: 实现 SkillCacheRepository**

创建 `client/lib/data/repositories/skill_cache_repository.dart`，提供：

```dart
class SkillCacheRepository {
  Stream<List<ManagedSkill>> watchSkills(String gatewayId, String locale);
  Future<List<ManagedSkill>> getSkills(String gatewayId, String locale);
  Future<List<ManagedSkill>> syncGateway(SkillScope scope, String locale);
  Future<ManagedSkill?> getDetail(String id, SkillScope scope, String locale);
  Future<ManagedSkill> create(SkillDraft draft, SkillScope? scope, String locale);
  Future<ManagedSkill> update(String id, SkillDraft draft, SkillScope? scope, String locale);
  Future<void> delete(String id, SkillScope? scope);
  Future<void> setEnabled(String id, bool enabled, SkillScope? scope, String locale);
}
```

Repository 写入规则：

- list sync 写 metadata 和 list-level localization。
- detail sync 写 `body/trigger/content` 和 detail localization。
- delete 成功后删除 source 和 localizations。
- update 成功后 upsert source，新 `sourceHash` 下旧 localization 不再用于显示。

- [x] **Step 4: 注册 provider**

修改 `client/lib/providers/database_providers.dart`：

```dart
final skillCacheDaoProvider = Provider<SkillCacheDao>((ref) {
  return SkillCacheDao(ref.watch(databaseProvider));
});

final skillCacheRepositoryProvider = Provider<SkillCacheRepository>((ref) {
  return SkillCacheRepository(
    dao: ref.watch(skillCacheDaoProvider),
    api: ref.watch(skillsApiServiceProvider),
    userId: ref.watch(currentUserUidProvider),
  );
});
```

- [x] **Step 5: 更新 SkillsController 使用 repository**

`SkillsController` 构造改为接收 `SkillCacheRepository` 和 locale provider 值。Controller 行为：

- `syncGateways()` 先从 DB 读当前 gateway skills。
- 后台调用 repository sync。
- 请求返回时校验 `selectedScopeId`。
- detail 打开时先读缓存，再拉 Server。

关键校验：

```dart
final requestScopeId = selectedScope.id;
final remote = await _cache.syncGateway(selectedScope, locale);
if (state.selectedScopeId != requestScopeId) return;
state = state.copyWith(skills: remote, isLoading: false);
```

- [x] **Step 6: 更新 tests**

在 `client/test/skills_provider_test.dart` 增加：

```dart
test('shows cached localized skills before remote sync completes', () async {
  final repo = _FakeSkillCacheRepository(
    cached: const [ManagedSkill(... translatedName: '网页搜索' ...)],
    remoteCompleter: Completer<List<ManagedSkill>>(),
  );
  final controller = SkillsController(repo, locale: 'zh-CN');

  final future = controller.syncGateways([_gateway('hermes')]);
  await Future<void>.delayed(Duration.zero);

  expect(controller.state.skills.single.displayName, '网页搜索');

  repo.remoteCompleter.complete(const [ManagedSkill(... translatedName: '网络搜索' ...)]);
  await future;

  expect(controller.state.skills.single.displayName, '网络搜索');
});
```

- [x] **Step 7: 运行 Task 5 测试**

```bash
cd client && flutter test test/providers/skill_cache_repository_test.dart test/providers/skills_provider_test.dart test/skills_management_screen_test.dart
cd client && dart analyze lib/data/repositories/skill_cache_repository.dart lib/services/skills_api_service.dart lib/providers/skills_provider.dart
```

Expected: PASS / No issues found.

---

## Task 6: Server Skill Translation Store and Service

**Files:**
- Create: `server/src/types/skill-translation.ts`
- Create: `server/src/store/skill-translation-store.ts`
- Create: `server/src/services/skill-translation-service.ts`
- Modify: `server/src/store/database.ts`
- Test: `server/test/skill-translation-store.test.js`
- Test: `server/test/skill-translation-service.test.js`

- [x] **Step 1: 写 store failing test**

创建 `server/test/skill-translation-store.test.js`：

```js
import test from 'node:test';
import assert from 'node:assert/strict';
import { Database } from '../dist/store/database.js';
import { SkillTranslationStore } from '../dist/store/skill-translation-store.js';

test('translation store deduplicates cache by source hash and locale', () => {
  const db = new Database(':memory:');
  const store = new SkillTranslationStore(db);

  store.upsertCache({
    gateway_type: 'hermes',
    gateway_id: 'hermes',
    skill_id: 'general/web-search',
    locale: 'zh-CN',
    field_set: 'metadata',
    source_hash: 'sha256:a',
    translated_name: '网页搜索',
    translated_description: '搜索网页',
    status: 'ready',
  });

  const item = store.getReadyCache({
    gateway_type: 'hermes',
    gateway_id: 'hermes',
    skill_id: 'general/web-search',
    locale: 'zh-CN',
    field_set: 'metadata',
    source_hash: 'sha256:a',
  });

  assert.equal(item.translated_name, '网页搜索');
  db.close();
});
```

Run:

```bash
cd server && npm run build && node --test --test-concurrency=1 --test-force-exit test/skill-translation-store.test.js
```

Expected: FAIL because store does not exist.

- [x] **Step 2: 增加 Server DB tables**

修改 `server/src/store/database.ts`，新增：

```sql
CREATE TABLE IF NOT EXISTS skill_translation_cache (
  gateway_type TEXT NOT NULL,
  gateway_id TEXT NOT NULL,
  skill_id TEXT NOT NULL,
  locale TEXT NOT NULL,
  field_set TEXT NOT NULL,
  source_hash TEXT NOT NULL,
  translated_name TEXT,
  translated_description TEXT,
  translated_trigger TEXT,
  translated_body TEXT,
  status TEXT NOT NULL,
  error_code TEXT,
  error_message TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  PRIMARY KEY (gateway_type, gateway_id, skill_id, locale, field_set, source_hash)
);

CREATE TABLE IF NOT EXISTS skill_translation_jobs (
  job_id TEXT PRIMARY KEY,
  gateway_type TEXT NOT NULL,
  gateway_id TEXT NOT NULL,
  skill_id TEXT NOT NULL,
  locale TEXT NOT NULL,
  field_set TEXT NOT NULL,
  source_hash TEXT NOT NULL,
  status TEXT NOT NULL,
  attempt_count INTEGER NOT NULL DEFAULT 0,
  last_error TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  UNIQUE (gateway_type, gateway_id, skill_id, locale, field_set, source_hash)
);
```

- [x] **Step 3: 创建 translation types**

创建 `server/src/types/skill-translation.ts`：

```ts
export type SkillTranslationStatus = 'missing' | 'pending' | 'ready' | 'failed';
export type SkillTranslationFieldSet = 'metadata' | 'detail';

export interface SkillTranslationKey {
  gateway_type: string;
  gateway_id: string;
  skill_id: string;
  locale: string;
  field_set: SkillTranslationFieldSet;
  source_hash: string;
}

export interface SkillTranslationCache extends SkillTranslationKey {
  translated_name?: string | null;
  translated_description?: string | null;
  translated_trigger?: string | null;
  translated_body?: string | null;
  status: SkillTranslationStatus;
  error_code?: string | null;
  error_message?: string | null;
}
```

- [x] **Step 4: 实现 SkillTranslationStore**

创建 `server/src/store/skill-translation-store.ts`：

```ts
export class SkillTranslationStore {
  constructor(private readonly db: Database) {}

  getReadyCache(key: SkillTranslationKey): SkillTranslationCache | null;
  upsertCache(cache: SkillTranslationCache): void;
  enqueueJob(key: SkillTranslationKey): string;
  markJobRunning(jobId: string): void;
  markJobReady(jobId: string): void;
  markJobFailed(jobId: string, error: string): void;
}
```

`enqueueJob` 使用 UNIQUE key，已有 pending/running job 时返回已有 `job_id`。

- [x] **Step 5: 写 service failing test**

创建 `server/test/skill-translation-service.test.js`：

```js
test('service returns ready cache and does not enqueue duplicate job', async () => {
  const db = new Database(':memory:');
  const store = new SkillTranslationStore(db);
  const service = new SkillTranslationService({
    store,
    translator: async () => {
      throw new Error('translator should not be called');
    },
  });

  store.upsertCache({
    gateway_type: 'hermes',
    gateway_id: 'hermes',
    skill_id: 'general/web-search',
    locale: 'zh-CN',
    field_set: 'metadata',
    source_hash: 'sha256:a',
    translated_name: '网页搜索',
    status: 'ready',
  });

  const result = service.getOrQueue({
    gatewayType: 'hermes',
    gatewayId: 'hermes',
    skillId: 'general/web-search',
    locale: 'zh-CN',
    fieldSet: 'metadata',
    sourceHash: 'sha256:a',
    source: { name: 'web-search', description: 'Search' },
  });

  assert.equal(result.status, 'ready');
  assert.equal(result.name, '网页搜索');
});
```

- [x] **Step 6: 实现 SkillTranslationService**

Service 提供：

```ts
export class SkillTranslationService {
  getOrQueue(input: SkillTranslationLookupInput): SkillLocalizationPayload;
  runNextJob(): Promise<boolean>;
}
```

`getOrQueue()` 行为：

- locale 为空或等于 source locale 时返回 `missing`，不排队。
- ready cache 命中时返回 ready payload。
- cache 未命中时 enqueue job，返回 pending。

source hash 函数：

```ts
createHash('sha256').update(JSON.stringify(source)).digest('hex')
```

- [x] **Step 7: 运行 Task 6 测试**

```bash
cd server && npm run build
cd server && node --test --test-concurrency=1 --test-force-exit test/skill-translation-store.test.js test/skill-translation-service.test.js
```

Expected: PASS.

---

## Task 7: Server Skills Routes Localization

**Files:**
- Modify: `server/src/routes/skills-routes.ts`
- Modify: `server/src/index.ts`
- Test: update `server/test/skills-routes.test.js`

- [x] **Step 1: 写 skills route localization failing test**

在 `server/test/skills-routes.test.js` 增加：

```js
test('list returns ready localization and queues missing translations', async () => {
  const translation = new FakeSkillTranslationService();
  translation.readyName = '网页搜索';

  const routes = initSkillsRoutes({
    requestGateway: fakeGatewayRequest,
    translationService: translation,
  });

  const res = await routes.listSkills(fakeReq({ gateway_id: 'hermes', locale: 'zh-CN' }));

  assert.equal(res.skills[0].localization.locale, 'zh-CN');
  assert.equal(res.skills[0].localization.status, 'ready');
  assert.equal(res.skills[0].localization.name, undefined);
  assert.equal(res.skills[0].localization.description, '搜索网页');
});
```

Run:

```bash
cd server && npm run build && node --test --test-concurrency=1 --test-force-exit test/skills-routes.test.js
```

Expected: FAIL because route does not use translation service.

- [x] **Step 2: 修改 route dependency**

`initSkillsRoutes` options 增加：

```ts
translationService?: SkillTranslationService;
```

list/detail response mapping 时调用：

```ts
const localization = translationService?.getOrQueue({
  gatewayType,
  gatewayId,
  skillId: skill.id,
  locale,
  fieldSet: 'metadata',
  sourceHash,
  source: {
    name: skill.name,
    description: skill.description,
  },
});
```

detail 使用 `fieldSet: 'detail'`，source 包含 `trigger/body`。

- [x] **Step 3: 修改 index 注入**

在 `server/src/index.ts` 初始化：

```ts
const skillTranslationStore = new SkillTranslationStore(db);
const skillTranslationService = new SkillTranslationService({
  store: skillTranslationStore,
  translator: createConfiguredSkillTranslator(config),
});
```

注入 skills routes。

- [x] **Step 4: 运行 Server targeted tests**

```bash
cd server && npm run build
cd server && node --test --test-concurrency=1 --test-force-exit test/skills-routes.test.js test/skills-gateway-client.test.js test/gateway-routes.test.js test/gateway-store.test.js
```

Expected: PASS.

---

## Task 8: Client Localization End-to-End Projection

**Files:**
- Modify: `client/lib/screens/skills_management_screen.dart`
- Modify: `client/lib/providers/skills_provider.dart`
- Test: update `client/test/skills_management_screen_test.dart`
- Test: update `client/test/providers/skills_provider_test.dart`

- [x] **Step 1: 写页面 projection failing test**

在 `client/test/skills_management_screen_test.dart` 增加：

```dart
testWidgets('skill list displays translated fields and editor keeps source fields', (tester) async {
  final api = _FakeSkillsApiService()
    ..skills = const [
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
        translatedName: '网页搜索',
        translatedDescription: '搜索网页',
        localizationStatus: 'ready',
      ),
    ];

  await tester.pumpWidget(buildSubject(locale: const Locale('zh'), api: api));
  await tester.pumpAndSettle();

  expect(find.text('网页搜索'), findsOneWidget);
  expect(find.text('搜索网页'), findsOneWidget);

  await tester.tap(find.widgetWithText(OutlinedButton, '编辑'));
  await tester.pumpAndSettle();

  expect(find.widgetWithText(TextFormField, 'web-search'), findsOneWidget);
});
```

Run:

```bash
cd client && flutter test test/skills_management_screen_test.dart
```

Expected: FAIL until UI uses display fields while editor uses source fields.

- [x] **Step 2: 更新 list/search/detail projection**

在 `SkillsManagementScreen` 中：

```dart
skill.displayName
skill.displayDescription
skill.displayTrigger
skill.displayBody
```

用于展示和搜索。

编辑弹窗初始值继续用：

```dart
skill.name
skill.description
skill.trigger
skill.body
```

- [x] **Step 3: 运行 Client targeted tests**

```bash
cd client && flutter test test/data/database/skill_cache_dao_test.dart test/providers/skill_cache_repository_test.dart test/providers/skills_provider_test.dart test/skills_management_screen_test.dart
cd client && dart analyze lib/models/managed_skill.dart lib/data/repositories/skill_cache_repository.dart lib/providers/skills_provider.dart lib/screens/skills_management_screen.dart
```

Expected: PASS / No issues found.

---

## Task 9: Full Verification

**Files:**
- Test: `client/test/cache_e2e_test.dart`
- Test: `client/integration_test/task_skill_management_e2e_test.dart`

- [x] **Step 1: Server targeted verification**

```bash
cd server && npm run build
cd server && node --test --test-concurrency=1 --test-force-exit test/gateway-store.test.js test/gateway-routes.test.js test/task-gateway-client.test.js test/tasks-routes.test.js test/skills-gateway-client.test.js test/skills-routes.test.js test/skill-translation-store.test.js test/skill-translation-service.test.js
```

Expected: PASS.

- [x] **Step 2: Client targeted verification**

```bash
cd client && flutter test test/cache_e2e_test.dart test/core/cup_parser_test.dart test/models/message_model_test.dart test/data/database/gateway_dao_test.dart test/data/database/task_cache_dao_test.dart test/data/database/skill_cache_dao_test.dart test/providers/gateway_repository_test.dart test/providers/task_cache_repository_test.dart test/providers/skill_cache_repository_test.dart test/tasks_provider_test.dart test/skills_provider_test.dart test/widgets/gateway_selector_pane_test.dart test/tasks_management_screen_test.dart test/skills_management_screen_test.dart
```

Expected: PASS.
Status: PASS, 113 tests.

- [x] **Step 2.1: Client macOS integration verification**

```bash
cd client && flutter test -d macos --timeout=60s integration_test/i18n_all_screens_e2e_test.dart
cd client && flutter test -d macos --timeout=60s integration_test/task_skill_management_e2e_test.dart
```

Expected: PASS.
Status: PASS. i18n default Chinese and task/skill cache UI flows passed in macOS app host.

- [x] **Step 3: Gateway smoke tests**

```bash
cd /Users/samy/MyProject/ai/clawke
node --import ./server/node_modules/tsx/dist/loader.mjs --test gateways/openclaw/clawke/src/task-adapter.test.ts gateways/openclaw/clawke/src/skill-adapter.test.ts
cd /Users/samy/MyProject/ai/clawke/gateways/hermes/clawke
python3 -m pytest test_clawke_channel.py test_task_adapter.py test_skill_adapter.py
```

Expected: PASS.

- [ ] **Step 4: Analyze**

```bash
cd client && dart analyze lib test
cd server && npm run build
```

Expected: No issues found / build success.

Status: server build passes; targeted client analyze for modified files including `test/cache_e2e_test.dart` passes. Full `dart analyze lib test` is blocked by existing unrelated warnings/infos outside this task scope.

- [x] **Step 5: Manual E2E with temporary data dir**

Use a temporary data dir to avoid touching real DB:

```bash
cd /Users/samy/MyProject/ai/clawke/server
CLAWKE_DATA_DIR=/tmp/clawke-cache-e2e npm run dev
```

Manual checks:

```text
1. Open task management.
2. Confirm cached task definitions render before network refresh.
3. Confirm task run history/output are not restored from cache after app restart.
4. Delete a task on Gateway, refresh, confirm local task cache deletes it.
5. Open skill center, confirm cached skill list renders before network refresh.
6. Open skill detail, confirm body is cached after first open.
7. Use locale zh-CN, confirm ready skill translation displays.
8. Confirm missing/pending/failed translation falls back to source text.
9. Confirm editing a translated skill edits source fields, not translated fields.
```

Expected: all checks match.

Status: partial PASS. Source-built macOS app (`ai.clawke.app`) connected to source Server with `CLAWKE_DATA_DIR=/tmp/clawke-real-e2e`; disconnected Gateway state rendered correctly. Full live Gateway CRUD still requires Hermes/OpenClaw Gateway to be connected.

---

## Known Risks

- Server full `node --test` currently includes older E2E scripts that may bind ports, require live services, or touch historical paths. Use targeted tests for this feature.
- `server/test/verify-persistence.js` must not be run as part of this work because it references persistent DB paths.
- Translation model provider may need separate API-key configuration. If no provider is configured, Server should keep localization status `pending` or `failed` without blocking skill usage.
