import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:client/data/repositories/task_cache_repository.dart';
import 'package:client/models/managed_task.dart';
import 'package:client/providers/tasks_provider.dart';
import 'package:client/services/tasks_api_service.dart';

class _FakeTasksApiService extends TasksApiService {
  List<ManagedTask> items;
  final List<TaskRun> runItems;
  Object? listError;
  String? listedAccountId;
  String? toggledTaskId;
  bool? toggledEnabled;
  String? triggeredTaskId;
  String? outputRunId;

  _FakeTasksApiService(this.items, {this.runItems = const [], this.listError});

  @override
  Future<List<ManagedTask>> listTasks({String? accountId}) async {
    listedAccountId = accountId;
    final error = listError;
    if (error != null) throw error;
    return items.where((task) => task.accountId == accountId).toList();
  }

  @override
  Future<ManagedTask?> setEnabled(
    String id,
    String accountId,
    bool enabled,
  ) async {
    toggledTaskId = id;
    toggledEnabled = enabled;
    final index = items.indexWhere((task) => task.id == id);
    final next = items[index].copyWith(enabled: enabled);
    items = [...items]..[index] = next;
    return next;
  }

  @override
  Future<TaskRun?> runTask(String id, String accountId) async {
    triggeredTaskId = id;
    return TaskRun(
      id: 'run_1',
      taskId: id,
      startedAt: '2026-04-24T00:00:00Z',
      status: 'running',
    );
  }

  @override
  Future<List<TaskRun>> listRuns(String id, String accountId) async {
    return runItems;
  }

  @override
  Future<String> getRunOutput(String id, String runId, String accountId) async {
    outputRunId = runId;
    return 'done';
  }
}

class _ApiBackedTaskCacheRepository implements TaskCacheRepository {
  _ApiBackedTaskCacheRepository(this.api, {this.cached = const []});

  final TasksApiService api;
  List<ManagedTask> cached;

  @override
  Stream<List<ManagedTask>> watchTasks(String gatewayId) {
    return Stream.value(_cachedFor(gatewayId));
  }

  @override
  Future<List<ManagedTask>> getTasks(String gatewayId) async {
    return _cachedFor(gatewayId);
  }

  @override
  Future<List<ManagedTask>> syncGateway(String gatewayId) async {
    final tasks = await api.listTasks(accountId: gatewayId);
    cached = [...cached.where((task) => task.accountId != gatewayId), ...tasks];
    return _cachedFor(gatewayId);
  }

  @override
  Future<ManagedTask> create(TaskDraft draft) async {
    final task = await api.createTask(draft);
    cached = _replaceCached(task);
    return task;
  }

  @override
  Future<ManagedTask> update(String id, TaskDraft draft) async {
    final task = await api.updateTask(id, draft);
    cached = _replaceCached(task);
    return task;
  }

  @override
  Future<void> delete(ManagedTask task) async {
    await api.deleteTask(task.id, task.accountId);
    cached = cached.where((item) => item.id != task.id).toList();
  }

  @override
  Future<ManagedTask?> setEnabled(ManagedTask task, bool enabled) async {
    final updated = await api.setEnabled(task.id, task.accountId, enabled);
    if (updated != null) {
      cached = _replaceCached(updated);
    }
    return updated;
  }

  List<ManagedTask> _cachedFor(String gatewayId) {
    return cached.where((task) => task.accountId == gatewayId).toList();
  }

  List<ManagedTask> _replaceCached(ManagedTask task) {
    return [...cached.where((item) => item.id != task.id), task];
  }
}

class _DelayedTasksApiService extends TasksApiService {
  final _pending = <String, List<Completer<List<ManagedTask>>>>{};
  bool delayHermes = false;
  bool delayOpenClaw = false;

  void delayGatewayLoads() {
    delayHermes = true;
    delayOpenClaw = true;
  }

  void completeHermes({int index = 0, String taskId = 'task_h'}) {
    _complete('hermes', index, [
      ManagedTask(
        id: taskId,
        accountId: 'hermes',
        agent: 'Hermes',
        name: 'Hermes task',
        schedule: '0 9 * * *',
        prompt: 'H',
        enabled: true,
        status: 'active',
      ),
    ]);
  }

  void failHermes({int index = 0}) {
    _pending['hermes']![index].completeError(
      DioException(
        requestOptions: RequestOptions(path: '/api/tasks'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/tasks'),
          statusCode: 504,
          data: const {'error': 'gateway_timeout'},
        ),
        type: DioExceptionType.badResponse,
      ),
    );
  }

  void completeOpenClaw({int index = 0, String taskId = 'task_o'}) {
    _complete('openclaw', index, [
      ManagedTask(
        id: taskId,
        accountId: 'openclaw',
        agent: 'OpenClaw',
        name: 'OpenClaw task',
        schedule: '0 10 * * *',
        prompt: 'O',
        enabled: true,
        status: 'active',
      ),
    ]);
  }

  @override
  Future<List<ManagedTask>> listTasks({String? accountId}) {
    if (accountId == 'hermes') {
      return delayHermes
          ? _queue('hermes')
          : Future.value(const <ManagedTask>[]);
    }
    if (accountId == 'openclaw') {
      return delayOpenClaw
          ? _queue('openclaw')
          : Future.value(const <ManagedTask>[]);
    }
    return Future.value(const <ManagedTask>[]);
  }

  Future<List<ManagedTask>> _queue(String accountId) {
    final completer = Completer<List<ManagedTask>>();
    (_pending[accountId] ??= []).add(completer);
    return completer.future;
  }

  void _complete(String accountId, int index, List<ManagedTask> tasks) {
    _pending[accountId]![index].complete(tasks);
  }
}

class _PendingTaskOperationsApiService extends TasksApiService {
  _PendingTaskOperationsApiService(this.items);

  List<ManagedTask> items;
  final createCompleter = Completer<ManagedTask>();
  final updateCompleter = Completer<ManagedTask>();
  final deleteCompleter = Completer<void>();
  final setEnabledCompleter = Completer<ManagedTask?>();
  final runCompleter = Completer<TaskRun?>();
  final runsCompleter = Completer<List<TaskRun>>();
  final outputCompleter = Completer<String>();

  @override
  Future<List<ManagedTask>> listTasks({String? accountId}) async {
    return items.where((task) => task.accountId == accountId).toList();
  }

  @override
  Future<ManagedTask> createTask(TaskDraft draft) {
    return createCompleter.future;
  }

  @override
  Future<ManagedTask> updateTask(String id, TaskDraft draft) {
    return updateCompleter.future;
  }

  @override
  Future<void> deleteTask(String id, String accountId) {
    return deleteCompleter.future;
  }

  @override
  Future<ManagedTask?> setEnabled(String id, String accountId, bool enabled) {
    return setEnabledCompleter.future;
  }

  @override
  Future<TaskRun?> runTask(String id, String accountId) {
    return runCompleter.future;
  }

  @override
  Future<List<TaskRun>> listRuns(String id, String accountId) {
    return runsCompleter.future;
  }

  @override
  Future<String> getRunOutput(String id, String runId, String accountId) {
    return outputCompleter.future;
  }
}

void main() {
  test('TasksController loads tasks for the first connected gateway', () async {
    final fake = _FakeTasksApiService([
      const ManagedTask(
        id: 'task_1',
        accountId: 'hermes',
        agent: 'Hermes',
        name: 'Daily summary',
        schedule: '0 9 * * *',
        prompt: 'Summarize',
        enabled: true,
        status: 'active',
      ),
    ]);
    final container = ProviderContainer(
      overrides: _taskProviderOverrides(fake),
    );
    addTearDown(container.dispose);

    await container.read(tasksControllerProvider.notifier).syncAccounts(const [
      TaskAccount(accountId: 'hermes', agentName: 'Hermes'),
    ]);

    final state = container.read(tasksControllerProvider);
    expect(state.selectedAccountId, 'hermes');
    expect(state.tasks.single.name, 'Daily summary');
    expect(fake.listedAccountId, 'hermes');
  });

  test('TasksController switches gateway and reloads scoped tasks', () async {
    final fake = _FakeTasksApiService([
      const ManagedTask(
        id: 'task_h',
        accountId: 'hermes',
        agent: 'Hermes',
        name: 'Hermes task',
        schedule: '0 9 * * *',
        prompt: 'H',
        enabled: true,
        status: 'active',
      ),
      const ManagedTask(
        id: 'task_o',
        accountId: 'openclaw',
        agent: 'OpenClaw',
        name: 'OpenClaw task',
        schedule: '0 10 * * *',
        prompt: 'O',
        enabled: true,
        status: 'active',
      ),
    ]);
    final container = ProviderContainer(
      overrides: _taskProviderOverrides(fake),
    );
    addTearDown(container.dispose);

    await container.read(tasksControllerProvider.notifier).syncAccounts(const [
      TaskAccount(accountId: 'hermes', agentName: 'Hermes'),
      TaskAccount(accountId: 'openclaw', agentName: 'OpenClaw'),
    ]);
    await container
        .read(tasksControllerProvider.notifier)
        .selectAccount('openclaw');

    final state = container.read(tasksControllerProvider);
    expect(state.selectedAccountId, 'openclaw');
    expect(state.tasks.single.id, 'task_o');
  });

  test(
    'TasksController clears previous tasks when selected gateway fails',
    () async {
      final error = DioException(
        requestOptions: RequestOptions(path: '/api/tasks'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/tasks'),
          statusCode: 504,
          data: const {'error': 'gateway_timeout'},
        ),
        type: DioExceptionType.badResponse,
      );
      final fake = _FakeTasksApiService([
        const ManagedTask(
          id: 'task_h',
          accountId: 'hermes',
          agent: 'Hermes',
          name: 'Hermes task',
          schedule: '0 9 * * *',
          prompt: 'H',
          enabled: true,
          status: 'active',
        ),
      ]);
      final container = ProviderContainer(
        overrides: _taskProviderOverrides(fake),
      );
      addTearDown(container.dispose);

      await container
          .read(tasksControllerProvider.notifier)
          .syncAccounts(const [
            TaskAccount(accountId: 'hermes', agentName: 'Hermes'),
            TaskAccount(accountId: 'openclaw', agentName: 'OpenClaw'),
          ]);
      fake.listError = error;
      await container
          .read(tasksControllerProvider.notifier)
          .selectAccount('openclaw');

      final state = container.read(tasksControllerProvider);
      expect(state.selectedAccountId, 'openclaw');
      expect(state.tasks, isEmpty);
      expect(state.errorAccountId, 'openclaw');
      expect(state.errorMessage, contains('OpenClaw 网关响应超时'));
    },
  );

  test(
    'TasksController clears removed gateway tasks before loading next account',
    () async {
      final error = DioException(
        requestOptions: RequestOptions(path: '/api/tasks'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/tasks'),
          statusCode: 504,
          data: const {'error': 'gateway_timeout'},
        ),
        type: DioExceptionType.badResponse,
      );
      final fake = _FakeTasksApiService([
        const ManagedTask(
          id: 'task_h',
          accountId: 'hermes',
          agent: 'Hermes',
          name: 'Hermes task',
          schedule: '0 9 * * *',
          prompt: 'H',
          enabled: true,
          status: 'active',
        ),
      ]);
      final container = ProviderContainer(
        overrides: _taskProviderOverrides(fake),
      );
      addTearDown(container.dispose);

      await container
          .read(tasksControllerProvider.notifier)
          .syncAccounts(const [
            TaskAccount(accountId: 'hermes', agentName: 'Hermes'),
            TaskAccount(accountId: 'openclaw', agentName: 'OpenClaw'),
          ]);
      expect(container.read(tasksControllerProvider).tasks.single.id, 'task_h');

      fake.listError = error;
      await container.read(tasksControllerProvider.notifier).syncAccounts(
        const [TaskAccount(accountId: 'openclaw', agentName: 'OpenClaw')],
      );

      final state = container.read(tasksControllerProvider);
      expect(state.selectedAccountId, 'openclaw');
      expect(state.tasks, isEmpty);
      expect(state.selectedTask, isNull);
      expect(state.runs, isEmpty);
      expect(state.errorAccountId, 'openclaw');
      expect(state.errorMessage, contains('OpenClaw 网关响应超时'));
    },
  );

  test(
    'TasksController loads cached tasks before remote sync completes',
    () async {
      final api = _DelayedTasksApiService()..delayGatewayLoads();
      final cache = _ApiBackedTaskCacheRepository(
        api,
        cached: [_task('cached_task')],
      );
      final controller = TasksController(api, cache: cache);
      addTearDown(controller.dispose);

      final load = controller.load(accountId: 'hermes', force: true);
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.isLoading, true);
      expect(controller.state.tasks.map((task) => task.id), ['cached_task']);

      api.completeHermes(taskId: 'remote_task');
      await load;

      expect(controller.state.isLoading, false);
      expect(controller.state.tasks.map((task) => task.id), ['remote_task']);
    },
  );

  test('TasksController keeps cached tasks when remote sync fails', () async {
    final api = _DelayedTasksApiService()..delayGatewayLoads();
    final cache = _ApiBackedTaskCacheRepository(
      api,
      cached: [_task('cached_task')],
    );
    final controller = TasksController(api, cache: cache);
    addTearDown(controller.dispose);

    final load = controller.load(accountId: 'hermes', force: true);
    await Future<void>.delayed(Duration.zero);
    api.failHermes();
    await load;

    expect(controller.state.isLoading, false);
    expect(controller.state.tasks.map((task) => task.id), ['cached_task']);
    expect(controller.state.errorAccountId, 'hermes');
    expect(controller.state.errorMessage, contains('Hermes 网关响应超时'));
  });

  test(
    'TasksController cache path ignores older same-gateway list after A B A switches',
    () async {
      final api = _DelayedTasksApiService()..delayGatewayLoads();
      final cache = _ApiBackedTaskCacheRepository(api);
      final controller = TasksController(api, cache: cache);
      addTearDown(controller.dispose);

      final oldHermesLoad = controller.load(accountId: 'hermes', force: true);
      await Future<void>.delayed(Duration.zero);
      final openClawLoad = controller.load(accountId: 'openclaw', force: true);
      await Future<void>.delayed(Duration.zero);
      final newHermesLoad = controller.load(accountId: 'hermes', force: true);
      await Future<void>.delayed(Duration.zero);

      api.completeHermes(index: 1, taskId: 'task_h_new');
      await newHermesLoad;
      api.completeOpenClaw();
      await openClawLoad;
      api.completeHermes(index: 0, taskId: 'task_h_old');
      await oldHermesLoad;

      expect(controller.state.selectedAccountId, 'hermes');
      expect(controller.state.tasks.map((task) => task.id), ['task_h_new']);
      expect(controller.state.errorMessage, isNull);
    },
  );

  test(
    'TasksController ignores stale task list when selected gateway changes',
    () async {
      final api = _DelayedTasksApiService();
      final controller = TasksController(api);
      addTearDown(controller.dispose);

      await controller.syncAccounts(const [
        TaskAccount(accountId: 'hermes', agentName: 'Hermes'),
        TaskAccount(accountId: 'openclaw', agentName: 'OpenClaw'),
      ]);

      api.delayGatewayLoads();
      final hermesLoad = controller.load(accountId: 'hermes', force: true);
      await Future<void>.delayed(Duration.zero);
      final openClawLoad = controller.load(accountId: 'openclaw', force: true);
      await Future<void>.delayed(Duration.zero);

      api.completeOpenClaw();
      await openClawLoad;
      api.completeHermes();
      await hermesLoad;

      expect(controller.state.selectedAccountId, 'openclaw');
      expect(controller.state.tasks.map((task) => task.accountId), [
        'openclaw',
      ]);
    },
  );

  test(
    'TasksController ignores stale task errors when selected gateway changes',
    () async {
      final api = _DelayedTasksApiService();
      final controller = TasksController(api);
      addTearDown(controller.dispose);

      await controller.syncAccounts(const [
        TaskAccount(accountId: 'hermes', agentName: 'Hermes'),
        TaskAccount(accountId: 'openclaw', agentName: 'OpenClaw'),
      ]);

      api.delayGatewayLoads();
      final hermesLoad = controller.load(accountId: 'hermes', force: true);
      await Future<void>.delayed(Duration.zero);
      final openClawLoad = controller.load(accountId: 'openclaw', force: true);
      await Future<void>.delayed(Duration.zero);

      api.completeOpenClaw();
      await openClawLoad;
      api.failHermes();
      await hermesLoad;

      expect(controller.state.selectedAccountId, 'openclaw');
      expect(controller.state.tasks.map((task) => task.accountId), [
        'openclaw',
      ]);
      expect(controller.state.errorMessage, isNull);
      expect(controller.state.errorAccountId, isNull);
    },
  );

  test(
    'TasksController ignores older same-gateway task list after A B A switches',
    () async {
      final api = _DelayedTasksApiService();
      final controller = TasksController(api);
      addTearDown(controller.dispose);

      await controller.syncAccounts(const [
        TaskAccount(accountId: 'hermes', agentName: 'Hermes'),
        TaskAccount(accountId: 'openclaw', agentName: 'OpenClaw'),
      ]);

      api.delayGatewayLoads();
      final oldHermesLoad = controller.load(accountId: 'hermes', force: true);
      await Future<void>.delayed(Duration.zero);
      final openClawLoad = controller.load(accountId: 'openclaw', force: true);
      await Future<void>.delayed(Duration.zero);
      final newHermesLoad = controller.load(accountId: 'hermes', force: true);
      await Future<void>.delayed(Duration.zero);

      api.completeHermes(index: 1, taskId: 'task_h_new');
      await newHermesLoad;
      api.completeOpenClaw();
      await openClawLoad;
      api.completeHermes(index: 0, taskId: 'task_h_old');
      await oldHermesLoad;

      expect(controller.state.selectedAccountId, 'hermes');
      expect(controller.state.tasks.map((task) => task.id), ['task_h_new']);
      expect(controller.state.errorMessage, isNull);
    },
  );

  test(
    'TasksController ignores older same-gateway task errors after A B A switches',
    () async {
      final api = _DelayedTasksApiService();
      final controller = TasksController(api);
      addTearDown(controller.dispose);

      await controller.syncAccounts(const [
        TaskAccount(accountId: 'hermes', agentName: 'Hermes'),
        TaskAccount(accountId: 'openclaw', agentName: 'OpenClaw'),
      ]);

      api.delayGatewayLoads();
      final oldHermesLoad = controller.load(accountId: 'hermes', force: true);
      await Future<void>.delayed(Duration.zero);
      final openClawLoad = controller.load(accountId: 'openclaw', force: true);
      await Future<void>.delayed(Duration.zero);
      final newHermesLoad = controller.load(accountId: 'hermes', force: true);
      await Future<void>.delayed(Duration.zero);

      api.completeHermes(index: 1, taskId: 'task_h_new');
      await newHermesLoad;
      api.completeOpenClaw();
      await openClawLoad;
      api.failHermes(index: 0);
      await oldHermesLoad;

      expect(controller.state.selectedAccountId, 'hermes');
      expect(controller.state.tasks.map((task) => task.id), ['task_h_new']);
      expect(controller.state.errorMessage, isNull);
      expect(controller.state.errorAccountId, isNull);
    },
  );

  test(
    'TasksController clears loading state when accounts disconnect',
    () async {
      final api = _DelayedTasksApiService();
      final controller = TasksController(api);
      addTearDown(controller.dispose);

      await controller.syncAccounts(const [
        TaskAccount(accountId: 'hermes', agentName: 'Hermes'),
      ]);

      api.delayGatewayLoads();
      final load = controller.load(accountId: 'hermes', force: true);
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.isLoading, true);

      await controller.syncAccounts(const []);

      expect(controller.state.selectedAccountId, isNull);
      expect(controller.state.tasks, isEmpty);
      expect(controller.state.isLoading, false);
      expect(controller.state.isLoadingRuns, false);

      api.completeHermes();
      await load;

      expect(controller.state.selectedAccountId, isNull);
      expect(controller.state.tasks, isEmpty);
      expect(controller.state.isLoading, false);
    },
  );

  test(
    'TasksController ignores pending create after accounts disconnect',
    () async {
      final api = _PendingTaskOperationsApiService(const []);
      final controller = TasksController(api);
      addTearDown(controller.dispose);

      await controller.syncAccounts(const [
        TaskAccount(accountId: 'hermes', agentName: 'Hermes'),
      ]);

      final create = controller.create(
        const TaskDraft(
          accountId: 'hermes',
          name: 'Created after disconnect',
          schedule: '0 9 * * *',
          prompt: 'Create',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.isSaving, true);

      await controller.syncAccounts(const []);

      expect(controller.state.selectedAccountId, isNull);
      expect(controller.state.isSaving, false);
      expect(controller.state.tasks, isEmpty);

      api.createCompleter.complete(
        const ManagedTask(
          id: 'task_created',
          accountId: 'hermes',
          agent: 'Hermes',
          name: 'Created after disconnect',
          schedule: '0 9 * * *',
          prompt: 'Create',
          enabled: true,
          status: 'active',
        ),
      );
      await create;

      expect(controller.state.selectedAccountId, isNull);
      expect(controller.state.selectedTask, isNull);
      expect(controller.state.tasks, isEmpty);
      expect(controller.state.isSaving, false);
    },
  );

  test(
    'TasksController ignores pending toggle after accounts disconnect',
    () async {
      const task = ManagedTask(
        id: 'task_1',
        accountId: 'hermes',
        agent: 'Hermes',
        name: 'Daily summary',
        schedule: '0 9 * * *',
        prompt: 'Summarize',
        enabled: true,
        status: 'active',
      );
      final api = _PendingTaskOperationsApiService([task]);
      final controller = TasksController(api);
      addTearDown(controller.dispose);

      await controller.syncAccounts(const [
        TaskAccount(accountId: 'hermes', agentName: 'Hermes'),
      ]);

      final toggle = controller.setEnabled(task, false);
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.togglingTaskIds, contains('task_1'));

      await controller.syncAccounts(const []);

      expect(controller.state.selectedAccountId, isNull);
      expect(controller.state.tasks, isEmpty);
      expect(controller.state.togglingTaskIds, isEmpty);

      api.setEnabledCompleter.complete(task.copyWith(enabled: false));
      await toggle;

      expect(controller.state.selectedAccountId, isNull);
      expect(controller.state.tasks, isEmpty);
      expect(controller.state.togglingTaskIds, isEmpty);
    },
  );

  test(
    'TasksController ignores pending runs after accounts disconnect',
    () async {
      const task = ManagedTask(
        id: 'task_1',
        accountId: 'hermes',
        agent: 'Hermes',
        name: 'Daily summary',
        schedule: '0 9 * * *',
        prompt: 'Summarize',
        enabled: true,
        status: 'active',
      );
      final api = _PendingTaskOperationsApiService([task]);
      final controller = TasksController(api);
      addTearDown(controller.dispose);

      await controller.syncAccounts(const [
        TaskAccount(accountId: 'hermes', agentName: 'Hermes'),
      ]);

      final loadRuns = controller.loadRuns(task);
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.selectedTask?.id, 'task_1');
      expect(controller.state.isLoadingRuns, true);

      await controller.syncAccounts(const []);

      expect(controller.state.selectedAccountId, isNull);
      expect(controller.state.selectedTask, isNull);
      expect(controller.state.isLoadingRuns, false);
      expect(controller.state.runs, isEmpty);

      api.runsCompleter.complete(const [
        TaskRun(
          id: 'run_late',
          taskId: 'task_1',
          startedAt: '2026-04-24T00:00:00Z',
          status: 'success',
        ),
      ]);
      await loadRuns;

      expect(controller.state.selectedAccountId, isNull);
      expect(controller.state.selectedTask, isNull);
      expect(controller.state.runs, isEmpty);
      expect(controller.state.isLoadingRuns, false);
    },
  );

  test('TasksController ignores pending update after account switch', () async {
    const hermesTask = ManagedTask(
      id: 'task_h',
      accountId: 'hermes',
      agent: 'Hermes',
      name: 'Hermes task',
      schedule: '0 9 * * *',
      prompt: 'H',
      enabled: true,
      status: 'active',
    );
    const openClawTask = ManagedTask(
      id: 'task_o',
      accountId: 'openclaw',
      agent: 'OpenClaw',
      name: 'OpenClaw task',
      schedule: '0 10 * * *',
      prompt: 'O',
      enabled: true,
      status: 'active',
    );
    final api = _PendingTaskOperationsApiService([hermesTask, openClawTask]);
    final controller = TasksController(api);
    addTearDown(controller.dispose);

    await controller.syncAccounts(const [
      TaskAccount(accountId: 'hermes', agentName: 'Hermes'),
      TaskAccount(accountId: 'openclaw', agentName: 'OpenClaw'),
    ]);

    final update = controller.update('task_h', TaskDraft.fromTask(hermesTask));
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.busyTaskIds, contains('task_h'));

    await controller.selectAccount('openclaw');

    expect(controller.state.selectedAccountId, 'openclaw');
    expect(controller.state.tasks.map((task) => task.id), ['task_o']);
    expect(controller.state.busyTaskIds, isEmpty);

    api.updateCompleter.complete(
      const ManagedTask(
        id: 'task_h',
        accountId: 'hermes',
        agent: 'Hermes',
        name: 'Late Hermes update',
        schedule: '0 9 * * *',
        prompt: 'H',
        enabled: true,
        status: 'active',
      ),
    );
    await update;

    expect(controller.state.selectedAccountId, 'openclaw');
    expect(controller.state.tasks.map((task) => task.id), ['task_o']);
    expect(controller.state.selectedTask, isNull);
    expect(controller.state.busyTaskIds, isEmpty);
  });

  test('TasksController ignores pending delete after account switch', () async {
    const hermesTask = ManagedTask(
      id: 'task_h',
      accountId: 'hermes',
      agent: 'Hermes',
      name: 'Hermes task',
      schedule: '0 9 * * *',
      prompt: 'H',
      enabled: true,
      status: 'active',
    );
    const openClawTask = ManagedTask(
      id: 'task_o',
      accountId: 'openclaw',
      agent: 'OpenClaw',
      name: 'OpenClaw task',
      schedule: '0 10 * * *',
      prompt: 'O',
      enabled: true,
      status: 'active',
    );
    final api = _PendingTaskOperationsApiService([hermesTask, openClawTask]);
    final controller = TasksController(api);
    addTearDown(controller.dispose);

    await controller.syncAccounts(const [
      TaskAccount(accountId: 'hermes', agentName: 'Hermes'),
      TaskAccount(accountId: 'openclaw', agentName: 'OpenClaw'),
    ]);

    final delete = controller.delete(hermesTask);
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.busyTaskIds, contains('task_h'));

    await controller.selectAccount('openclaw');
    api.deleteCompleter.complete();
    await delete;

    expect(controller.state.selectedAccountId, 'openclaw');
    expect(controller.state.tasks.map((task) => task.id), ['task_o']);
    expect(controller.state.busyTaskIds, isEmpty);
  });

  test('TasksController ignores pending run after account switch', () async {
    const hermesTask = ManagedTask(
      id: 'task_h',
      accountId: 'hermes',
      agent: 'Hermes',
      name: 'Hermes task',
      schedule: '0 9 * * *',
      prompt: 'H',
      enabled: true,
      status: 'active',
    );
    const openClawTask = ManagedTask(
      id: 'task_o',
      accountId: 'openclaw',
      agent: 'OpenClaw',
      name: 'OpenClaw task',
      schedule: '0 10 * * *',
      prompt: 'O',
      enabled: true,
      status: 'active',
    );
    final api = _PendingTaskOperationsApiService([hermesTask, openClawTask]);
    final controller = TasksController(api);
    addTearDown(controller.dispose);

    await controller.syncAccounts(const [
      TaskAccount(accountId: 'hermes', agentName: 'Hermes'),
      TaskAccount(accountId: 'openclaw', agentName: 'OpenClaw'),
    ]);

    final runNow = controller.runNow(hermesTask);
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.busyTaskIds, contains('task_h'));

    await controller.selectAccount('openclaw');
    api.runCompleter.complete(
      const TaskRun(
        id: 'run_late',
        taskId: 'task_h',
        startedAt: '2026-04-24T00:00:00Z',
        status: 'running',
      ),
    );
    await runNow;

    expect(controller.state.selectedAccountId, 'openclaw');
    expect(controller.state.tasks.map((task) => task.id), ['task_o']);
    expect(controller.state.selectedTask, isNull);
    expect(controller.state.runs, isEmpty);
    expect(controller.state.busyTaskIds, isEmpty);
  });

  test('TasksController ignores pending output after account switch', () async {
    const hermesTask = ManagedTask(
      id: 'task_h',
      accountId: 'hermes',
      agent: 'Hermes',
      name: 'Hermes task',
      schedule: '0 9 * * *',
      prompt: 'H',
      enabled: true,
      status: 'active',
    );
    const openClawTask = ManagedTask(
      id: 'task_o',
      accountId: 'openclaw',
      agent: 'OpenClaw',
      name: 'OpenClaw task',
      schedule: '0 10 * * *',
      prompt: 'O',
      enabled: true,
      status: 'active',
    );
    const run = TaskRun(
      id: 'run_1',
      taskId: 'task_h',
      startedAt: '2026-04-24T00:00:00Z',
      status: 'success',
    );
    final api = _PendingTaskOperationsApiService([hermesTask, openClawTask]);
    final controller = TasksController(api);
    addTearDown(controller.dispose);

    await controller.syncAccounts(const [
      TaskAccount(accountId: 'hermes', agentName: 'Hermes'),
      TaskAccount(accountId: 'openclaw', agentName: 'OpenClaw'),
    ]);
    final loadRuns = controller.loadRuns(hermesTask);
    await Future<void>.delayed(Duration.zero);
    api.runsCompleter.complete(const [run]);
    await loadRuns;
    expect(controller.state.selectedTask?.id, 'task_h');

    final output = controller.loadOutput(run);
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.selectedRunOutput, '');

    await controller.selectAccount('openclaw');
    api.outputCompleter.complete('late output');
    await output;

    expect(controller.state.selectedAccountId, 'openclaw');
    expect(controller.state.tasks.map((task) => task.id), ['task_o']);
    expect(controller.state.selectedTask, isNull);
    expect(controller.state.selectedRunOutput, isNull);
  });

  test('TasksController toggles task and triggers run output chain', () async {
    const run = TaskRun(
      id: 'run_done',
      taskId: 'task_1',
      startedAt: '2026-04-24T00:00:00Z',
      status: 'success',
      outputPreview: 'done',
    );
    const task = ManagedTask(
      id: 'task_1',
      accountId: 'hermes',
      agent: 'Hermes',
      name: 'Daily summary',
      schedule: '0 9 * * *',
      prompt: 'Summarize',
      enabled: true,
      status: 'active',
    );
    final fake = _FakeTasksApiService([task], runItems: [run]);
    final container = ProviderContainer(
      overrides: _taskProviderOverrides(fake),
    );
    addTearDown(container.dispose);

    await container.read(tasksControllerProvider.notifier).syncAccounts(const [
      TaskAccount(accountId: 'hermes', agentName: 'Hermes'),
    ]);
    await container
        .read(tasksControllerProvider.notifier)
        .setEnabled(task, false);
    await container.read(tasksControllerProvider.notifier).runNow(task);
    await container.read(tasksControllerProvider.notifier).loadRuns(task);
    await container.read(tasksControllerProvider.notifier).loadOutput(run);

    final state = container.read(tasksControllerProvider);
    expect(fake.toggledTaskId, 'task_1');
    expect(fake.toggledEnabled, false);
    expect(fake.triggeredTaskId, 'task_1');
    expect(state.runs.first.id, 'run_done');
    expect(state.selectedRunOutput, 'done');
  });

  test('TasksController stores a friendly gateway timeout message', () async {
    final fake = _FakeTasksApiService(
      const [],
      listError: DioException(
        requestOptions: RequestOptions(path: '/api/tasks'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/tasks'),
          statusCode: 504,
          data: const {'error': 'gateway_timeout'},
        ),
        type: DioExceptionType.badResponse,
      ),
    );
    final container = ProviderContainer(
      overrides: _taskProviderOverrides(fake),
    );
    addTearDown(container.dispose);

    await container.read(tasksControllerProvider.notifier).syncAccounts(const [
      TaskAccount(accountId: 'hermes', agentName: 'Hermes'),
    ]);

    final state = container.read(tasksControllerProvider);
    expect(state.errorMessage, 'Hermes 网关响应超时，请确认 Hermes Gateway 正在运行后重试。');
    expect(state.errorMessage, isNot(contains('DioException')));
  });
}

List<Override> _taskProviderOverrides(TasksApiService api) {
  return [
    tasksApiServiceProvider.overrideWithValue(api),
    taskCacheRepositoryProvider.overrideWithValue(
      _ApiBackedTaskCacheRepository(api),
    ),
  ];
}

ManagedTask _task(String id, {String accountId = 'hermes'}) {
  return ManagedTask(
    id: id,
    accountId: accountId,
    agent: accountId,
    name: id,
    schedule: '0 9 * * *',
    prompt: id,
    enabled: true,
    status: 'active',
  );
}
