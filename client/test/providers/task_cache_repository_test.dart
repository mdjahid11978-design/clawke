import 'dart:async';

import 'package:client/data/database/app_database.dart';
import 'package:client/data/database/dao/task_cache_dao.dart';
import 'package:client/data/repositories/task_cache_repository.dart';
import 'package:client/models/managed_task.dart';
import 'package:client/services/tasks_api_service.dart';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeTasksApi extends TasksApiService {
  List<ManagedTask> tasks = const [];
  final createCompleter = Completer<ManagedTask>();
  TaskDraft? createdDraft;

  @override
  Future<List<ManagedTask>> listTasks({String? accountId}) async {
    return tasks.where((task) => task.accountId == accountId).toList();
  }

  @override
  Future<ManagedTask> createTask(TaskDraft draft) {
    createdDraft = draft;
    return createCompleter.future;
  }
}

void main() {
  late AppDatabase db;
  late TaskCacheDao dao;
  late _FakeTasksApi api;
  late TaskCacheRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dao = TaskCacheDao(db);
    api = _FakeTasksApi();
    repo = TaskCacheRepository(dao: dao, api: api, userId: 'u1');
  });

  tearDown(() async {
    await db.close();
  });

  test('sync stores task definitions and strips lastRun', () async {
    api.tasks = const [
      ManagedTask(
        id: 'task_1',
        accountId: 'hermes',
        agent: 'Hermes',
        name: 'Daily',
        schedule: '0 9 * * *',
        scheduleText: 'Every day at 09:00',
        prompt: 'Summarize',
        enabled: true,
        status: 'active',
        skills: ['notes'],
        deliver: 'local',
        lastRun: TaskRun(
          id: 'run_1',
          taskId: 'task_1',
          startedAt: '2026-04-25T09:00:00Z',
          status: 'success',
          outputPreview: 'secret preview',
        ),
      ),
    ];

    await repo.syncGateway('hermes');

    final cached = await repo.getTasks('hermes');
    expect(cached, hasLength(1));
    expect(cached.single.id, 'task_1');
    expect(cached.single.skills, ['notes']);
    expect(cached.single.deliver, 'local');
    expect(cached.single.lastRun, isNull);
  });

  test('sync deletes missing tasks only for the snapshot gateway', () async {
    await _insertCached(dao, 'hermes', 'keep');
    await _insertCached(dao, 'hermes', 'delete_me');
    await _insertCached(dao, 'openclaw', 'other_gateway');
    api.tasks = const [
      ManagedTask(
        id: 'keep',
        accountId: 'hermes',
        agent: 'Hermes',
        name: 'Keep',
        schedule: '0 9 * * *',
        prompt: 'Keep',
        enabled: true,
        status: 'active',
      ),
    ];

    await repo.syncGateway('hermes');

    expect((await repo.getTasks('hermes')).map((task) => task.id), ['keep']);
    expect((await repo.getTasks('openclaw')).map((task) => task.id), [
      'other_gateway',
    ]);
  });

  test('create mutation updates cache only after server succeeds', () async {
    final create = repo.create(
      const TaskDraft(
        accountId: 'hermes',
        name: 'Created',
        schedule: '0 10 * * *',
        prompt: 'Create it',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(api.createdDraft?.name, 'Created');
    expect(await repo.getTasks('hermes'), isEmpty);

    api.createCompleter.complete(
      const ManagedTask(
        id: 'created',
        accountId: 'hermes',
        agent: 'Hermes',
        name: 'Created',
        schedule: '0 10 * * *',
        prompt: 'Create it',
        enabled: true,
        status: 'active',
        lastRun: TaskRun(
          id: 'run_after_create',
          taskId: 'created',
          startedAt: '2026-04-25T10:00:00Z',
          status: 'success',
        ),
      ),
    );

    final created = await create;
    final cached = await repo.getTasks('hermes');
    expect(created.lastRun, isNull);
    expect(cached.map((task) => task.id), ['created']);
    expect(cached.single.lastRun, isNull);
  });
}

Future<void> _insertCached(TaskCacheDao dao, String gatewayId, String taskId) {
  return dao.upsertTask(
    TaskCacheCompanion.insert(
      userId: 'u1',
      gatewayId: gatewayId,
      taskId: taskId,
      name: taskId,
      schedule: '* * * * *',
      prompt: taskId,
      enabled: true,
      status: 'active',
      syncedAt: 100,
      skillsJson: const drift.Value('[]'),
    ),
  );
}
