import 'package:client/data/database/app_database.dart';

class TaskCacheDao {
  final AppDatabase _db;
  TaskCacheDao(this._db);

  Stream<List<TaskCacheData>> watchTasks(String userId, String gatewayId) {
    return _db.watchTasks(userId, gatewayId).watch();
  }

  Future<List<TaskCacheData>> getTasks(String userId, String gatewayId) {
    return _db.getTasks(userId, gatewayId).get();
  }

  Future<void> upsertTask(TaskCacheCompanion task) {
    return _db.into(_db.taskCache).insertOnConflictUpdate(task);
  }

  Future<void> deleteTask(String userId, String gatewayId, String taskId) {
    return (_db.delete(_db.taskCache)
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
    final existing = await getTasks(userId, gatewayId);
    for (final task in existing) {
      if (!remoteIds.contains(task.taskId)) {
        await deleteTask(userId, gatewayId, task.taskId);
      }
    }
  }
}
