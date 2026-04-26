import 'package:client/data/database/app_database.dart';
import 'package:client/data/database/dao/task_cache_dao.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late TaskCacheDao dao;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dao = TaskCacheDao(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('upserts, watches, and gets task definitions only', () async {
    final tableInfo = await db
        .customSelect('PRAGMA table_info(task_cache)')
        .get();
    final columns = tableInfo.map((row) => row.read<String>('name')).toSet();
    expect(columns, isNot(contains('last_run')));
    expect(columns, isNot(contains('runs')));
    expect(columns, isNot(contains('output')));
    expect(columns, isNot(contains('output_preview')));

    final watched = dao.watchTasks('u1', 'hermes');
    final watching = expectLater(
      watched,
      emitsThrough(
        predicate<List<TaskCacheData>>(
          (rows) =>
              rows.map((row) => row.taskId).toList().join(',') ==
              'task_1,task_2',
        ),
      ),
    );

    await dao.upsertTask(
      TaskCacheCompanion.insert(
        userId: 'u1',
        gatewayId: 'hermes',
        taskId: 'task_2',
        name: 'Beta',
        schedule: '0 10 * * *',
        prompt: 'Summarize beta',
        enabled: true,
        status: 'active',
        skillsJson: const Value('["notes"]'),
        deliver: const Value('email'),
        createdAt: const Value('2026-04-25T09:00:00Z'),
        updatedAt: const Value('2026-04-25T09:30:00Z'),
        syncedAt: 100,
      ),
    );
    await dao.upsertTask(
      TaskCacheCompanion.insert(
        userId: 'u1',
        gatewayId: 'hermes',
        taskId: 'task_1',
        name: 'Alpha',
        schedule: '0 9 * * *',
        scheduleText: const Value('Every day at 09:00'),
        prompt: 'Summarize alpha',
        enabled: false,
        status: 'paused',
        syncedAt: 101,
      ),
    );

    await watching;

    final rows = await dao.getTasks('u1', 'hermes');
    expect(rows.map((row) => row.taskId), ['task_1', 'task_2']);
    expect(rows.first.name, 'Alpha');
    expect(rows.first.scheduleText, 'Every day at 09:00');
    expect(rows.first.skillsJson, '[]');
    expect(rows.first.deliver, isNull);

    await dao.upsertTask(
      TaskCacheCompanion.insert(
        userId: 'u1',
        gatewayId: 'hermes',
        taskId: 'task_1',
        name: 'Alpha updated',
        schedule: '0 8 * * *',
        prompt: 'Summarize alpha updated',
        enabled: true,
        status: 'active',
        skillsJson: const Value('["notes","calendar"]'),
        syncedAt: 102,
      ),
    );

    final updated = await dao.getTasks('u1', 'hermes');
    expect(updated.first.taskId, 'task_1');
    expect(updated.first.name, 'Alpha updated');
    expect(updated.first.skillsJson, '["notes","calendar"]');
  });

  test(
    'deleteMissing only removes tasks for the same user and gateway',
    () async {
      Future<void> insertTask(String userId, String gatewayId, String taskId) {
        return dao.upsertTask(
          TaskCacheCompanion.insert(
            userId: userId,
            gatewayId: gatewayId,
            taskId: taskId,
            name: taskId,
            schedule: '* * * * *',
            prompt: taskId,
            enabled: true,
            status: 'active',
            syncedAt: 100,
          ),
        );
      }

      await insertTask('u1', 'hermes', 'keep');
      await insertTask('u1', 'hermes', 'delete_me');
      await insertTask('u1', 'openclaw', 'delete_me');
      await insertTask('u2', 'hermes', 'delete_me');

      await dao.deleteMissing('u1', 'hermes', {'keep'});

      expect((await dao.getTasks('u1', 'hermes')).map((row) => row.taskId), [
        'keep',
      ]);
      expect((await dao.getTasks('u1', 'openclaw')).map((row) => row.taskId), [
        'delete_me',
      ]);
      expect((await dao.getTasks('u2', 'hermes')).map((row) => row.taskId), [
        'delete_me',
      ]);
    },
  );

  test('deleteTask removes only the requested task identity', () async {
    await dao.upsertTask(
      TaskCacheCompanion.insert(
        userId: 'u1',
        gatewayId: 'hermes',
        taskId: 'task_1',
        name: 'Daily',
        schedule: '0 9 * * *',
        prompt: 'Summarize',
        enabled: true,
        status: 'active',
        syncedAt: 100,
      ),
    );
    await dao.upsertTask(
      TaskCacheCompanion.insert(
        userId: 'u1',
        gatewayId: 'openclaw',
        taskId: 'task_1',
        name: 'Daily',
        schedule: '0 9 * * *',
        prompt: 'Summarize',
        enabled: true,
        status: 'active',
        syncedAt: 100,
      ),
    );

    await dao.deleteTask('u1', 'hermes', 'task_1');

    expect(await dao.getTasks('u1', 'hermes'), isEmpty);
    expect(await dao.getTasks('u1', 'openclaw'), hasLength(1));
  });
}
