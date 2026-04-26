import 'dart:convert';

import 'package:client/data/database/app_database.dart';
import 'package:client/data/database/dao/task_cache_dao.dart';
import 'package:client/models/managed_task.dart';
import 'package:client/services/tasks_api_service.dart';
import 'package:drift/drift.dart' as drift;

class TaskCacheRepository {
  TaskCacheRepository({
    required TaskCacheDao dao,
    required TasksApiService api,
    required String userId,
  }) : _dao = dao,
       _api = api,
       _userId = userId;

  final TaskCacheDao _dao;
  final TasksApiService _api;
  final String _userId;

  Stream<List<ManagedTask>> watchTasks(String gatewayId) {
    return _dao.watchTasks(_userId, gatewayId).map(_fromRows);
  }

  Future<List<ManagedTask>> getTasks(String gatewayId) async {
    return _fromRows(await _dao.getTasks(_userId, gatewayId));
  }

  Future<List<ManagedTask>> syncGateway(String gatewayId) async {
    final tasks = await _api.listTasks(accountId: gatewayId);
    for (final task in tasks) {
      await _upsert(task, gatewayId: gatewayId);
    }
    await _dao.deleteMissing(_userId, gatewayId, {
      for (final task in tasks) task.id,
    });
    return getTasks(gatewayId);
  }

  Future<ManagedTask> create(TaskDraft draft) async {
    final task = await _api.createTask(draft);
    await _upsert(task, gatewayId: draft.accountId);
    return _stripRuntimeFields(task);
  }

  Future<ManagedTask> update(String id, TaskDraft draft) async {
    final task = await _api.updateTask(id, draft);
    await _upsert(task, gatewayId: draft.accountId);
    return _stripRuntimeFields(task);
  }

  Future<void> delete(ManagedTask task) async {
    await _api.deleteTask(task.id, task.accountId);
    await _dao.deleteTask(_userId, task.accountId, task.id);
  }

  Future<ManagedTask?> setEnabled(ManagedTask task, bool enabled) async {
    final updated = await _api.setEnabled(task.id, task.accountId, enabled);
    final next = updated ?? task.copyWith(enabled: enabled);
    await _upsert(next, gatewayId: task.accountId);
    return _stripRuntimeFields(next);
  }

  Future<void> _upsert(ManagedTask task, {required String gatewayId}) {
    return _dao.upsertTask(_toCompanion(task, gatewayId: gatewayId));
  }

  TaskCacheCompanion _toCompanion(
    ManagedTask task, {
    required String gatewayId,
  }) {
    return TaskCacheCompanion.insert(
      userId: _userId,
      gatewayId: gatewayId,
      taskId: task.id,
      name: task.name,
      schedule: task.schedule,
      scheduleText: drift.Value(task.scheduleText),
      prompt: task.prompt,
      enabled: task.enabled,
      status: task.status,
      skillsJson: drift.Value(jsonEncode(task.skills)),
      deliver: drift.Value(task.deliver),
      createdAt: drift.Value(task.createdAt),
      updatedAt: drift.Value(task.updatedAt),
      syncedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  List<ManagedTask> _fromRows(List<TaskCacheData> rows) {
    return rows.map(_fromRow).toList();
  }

  ManagedTask _fromRow(TaskCacheData row) {
    return ManagedTask(
      id: row.taskId,
      accountId: row.gatewayId,
      agent: row.gatewayId,
      name: row.name,
      schedule: row.schedule,
      scheduleText: row.scheduleText,
      prompt: row.prompt,
      enabled: row.enabled,
      status: row.status,
      skills: _decodeSkills(row.skillsJson),
      deliver: row.deliver,
      nextRunAt: null,
      lastRun: null,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }
}

ManagedTask _stripRuntimeFields(ManagedTask task) {
  return ManagedTask(
    id: task.id,
    accountId: task.accountId,
    agent: task.agent,
    name: task.name,
    schedule: task.schedule,
    scheduleText: task.scheduleText,
    prompt: task.prompt,
    enabled: task.enabled,
    status: task.status,
    skills: task.skills,
    deliver: task.deliver,
    nextRunAt: task.nextRunAt,
    lastRun: null,
    createdAt: task.createdAt,
    updatedAt: task.updatedAt,
  );
}

List<String> _decodeSkills(String raw) {
  try {
    final parsed = jsonDecode(raw);
    if (parsed is! List) return const [];
    return parsed.map((item) => item.toString()).toList();
  } catch (_) {
    return const [];
  }
}
