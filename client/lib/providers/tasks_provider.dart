import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:client/data/repositories/task_cache_repository.dart';
import 'package:client/models/managed_task.dart';
import 'package:client/providers/database_providers.dart';
import 'package:client/services/tasks_api_service.dart';

export 'package:client/providers/database_providers.dart'
    show taskCacheRepositoryProvider, tasksApiServiceProvider;

final tasksControllerProvider =
    StateNotifierProvider<TasksController, TasksState>((ref) {
      return TasksController(
        ref.watch(tasksApiServiceProvider),
        cache: ref.watch(taskCacheRepositoryProvider),
      );
    });

@immutable
class TasksState {
  final List<TaskAccount> accounts;
  final String? selectedAccountId;
  final List<ManagedTask> tasks;
  final List<TaskRun> runs;
  final ManagedTask? selectedTask;
  final String? selectedRunOutput;
  final bool isLoading;
  final bool isSaving;
  final bool isLoadingRuns;
  final Set<String> busyTaskIds;
  final Set<String> togglingTaskIds;
  final String? errorMessage;
  final String? errorAccountId;

  const TasksState({
    this.accounts = const [],
    this.selectedAccountId,
    this.tasks = const [],
    this.runs = const [],
    this.selectedTask,
    this.selectedRunOutput,
    this.isLoading = false,
    this.isSaving = false,
    this.isLoadingRuns = false,
    this.busyTaskIds = const <String>{},
    this.togglingTaskIds = const <String>{},
    this.errorMessage,
    this.errorAccountId,
  });

  TaskAccount? get selectedAccount {
    for (final account in accounts) {
      if (account.accountId == selectedAccountId) return account;
    }
    return null;
  }

  TasksState copyWith({
    List<TaskAccount>? accounts,
    String? selectedAccountId,
    bool clearSelectedAccount = false,
    List<ManagedTask>? tasks,
    List<TaskRun>? runs,
    ManagedTask? selectedTask,
    bool clearSelectedTask = false,
    String? selectedRunOutput,
    bool clearRunOutput = false,
    bool? isLoading,
    bool? isSaving,
    bool? isLoadingRuns,
    Set<String>? busyTaskIds,
    Set<String>? togglingTaskIds,
    String? errorMessage,
    String? errorAccountId,
    bool clearError = false,
  }) {
    return TasksState(
      accounts: accounts ?? this.accounts,
      selectedAccountId: clearSelectedAccount
          ? null
          : (selectedAccountId ?? this.selectedAccountId),
      tasks: tasks ?? this.tasks,
      runs: runs ?? this.runs,
      selectedTask: clearSelectedTask
          ? null
          : (selectedTask ?? this.selectedTask),
      selectedRunOutput: clearRunOutput
          ? null
          : (selectedRunOutput ?? this.selectedRunOutput),
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      isLoadingRuns: isLoadingRuns ?? this.isLoadingRuns,
      busyTaskIds: busyTaskIds ?? this.busyTaskIds,
      togglingTaskIds: togglingTaskIds ?? this.togglingTaskIds,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      errorAccountId: clearError
          ? null
          : (errorAccountId ?? this.errorAccountId),
    );
  }
}

class TasksController extends StateNotifier<TasksState> {
  TasksController(this._api, {TaskCacheRepository? cache})
    : _cache = cache,
      super(const TasksState());

  final TasksApiService _api;
  final TaskCacheRepository? _cache;
  int _loadGeneration = 0;

  Future<void> syncAccounts(List<TaskAccount> accounts) async {
    final nextSelected = _resolveAccount(accounts, state.selectedAccountId);
    final selectionChanged = nextSelected != state.selectedAccountId;
    final sameAccounts = listEquals(
      accounts.map((a) => '${a.accountId}:${a.agentName}').toList(),
      state.accounts.map((a) => '${a.accountId}:${a.agentName}').toList(),
    );
    if (sameAccounts && nextSelected == state.selectedAccountId) return;

    if (selectionChanged) _loadGeneration += 1;

    state = state.copyWith(
      accounts: accounts,
      selectedAccountId: nextSelected,
      clearSelectedAccount: nextSelected == null,
      tasks: selectionChanged ? const [] : state.tasks,
      clearSelectedTask: true,
      runs: const [],
      clearRunOutput: true,
      isLoading: selectionChanged ? false : state.isLoading,
      isSaving: selectionChanged ? false : state.isSaving,
      isLoadingRuns: selectionChanged ? false : state.isLoadingRuns,
      busyTaskIds: selectionChanged ? const <String>{} : state.busyTaskIds,
      togglingTaskIds: selectionChanged
          ? const <String>{}
          : state.togglingTaskIds,
      clearError: selectionChanged,
    );

    if (nextSelected != null) {
      await load(accountId: nextSelected, force: true);
    }
  }

  Future<void> load({String? accountId, bool force = false}) async {
    final selected = accountId ?? state.selectedAccountId;
    if (selected == null) return;
    if (state.tasks.isNotEmpty &&
        !force &&
        selected == state.selectedAccountId) {
      return;
    }
    final switchingAccount = selected != state.selectedAccountId;
    final requestAccountId = selected;
    final requestGeneration = ++_loadGeneration;
    state = state.copyWith(
      selectedAccountId: requestAccountId,
      tasks: switchingAccount ? const [] : state.tasks,
      isLoading: true,
      isSaving: switchingAccount ? false : state.isSaving,
      isLoadingRuns: false,
      busyTaskIds: switchingAccount ? const <String>{} : state.busyTaskIds,
      togglingTaskIds: switchingAccount
          ? const <String>{}
          : state.togglingTaskIds,
      clearSelectedTask: true,
      runs: const [],
      clearRunOutput: true,
      clearError: true,
    );
    final cached = await _getCachedTasks(requestAccountId);
    if (requestGeneration != _loadGeneration) return;
    if (cached.isNotEmpty) {
      state = state.copyWith(tasks: cached);
    }
    try {
      final tasks = await _syncTasks(requestAccountId);
      if (requestGeneration != _loadGeneration) return;
      state = state.copyWith(tasks: tasks, isLoading: false);
    } catch (e) {
      if (requestGeneration != _loadGeneration) return;
      state = state.copyWith(
        isLoading: false,
        errorMessage: _taskErrorMessage(e, accountId: requestAccountId),
        errorAccountId: requestAccountId,
      );
    }
  }

  Future<void> refresh() => load(force: true);

  void clearError() {
    if (state.errorMessage == null) return;
    state = state.copyWith(clearError: true);
  }

  Future<void> selectAccount(String accountId) async {
    if (accountId == state.selectedAccountId) return;
    await load(accountId: accountId, force: true);
  }

  void selectUnavailableAccount(
    List<TaskAccount> accounts,
    String accountId,
    String message,
  ) {
    if (!accounts.any((account) => account.accountId == accountId)) return;
    _loadGeneration += 1;
    state = state.copyWith(
      accounts: accounts,
      selectedAccountId: accountId,
      tasks: const [],
      runs: const [],
      clearSelectedTask: true,
      clearRunOutput: true,
      isLoading: false,
      isSaving: false,
      isLoadingRuns: false,
      busyTaskIds: const <String>{},
      togglingTaskIds: const <String>{},
      errorMessage: message,
      errorAccountId: accountId,
    );
  }

  Future<void> create(TaskDraft draft) async {
    final requestAccountId = draft.accountId;
    final requestGeneration = _loadGeneration;
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final task = await _createTask(draft);
      if (!_isCurrentAccountRequest(requestAccountId, requestGeneration)) {
        if (state.selectedAccountId == requestAccountId) {
          state = state.copyWith(isSaving: false);
        }
        return;
      }
      state = state.copyWith(
        isSaving: false,
        selectedAccountId: task.accountId,
        selectedTask: task,
        tasks: [...state.tasks, task]..sort(_sortTasks),
      );
    } catch (e) {
      if (!_isCurrentAccountRequest(requestAccountId, requestGeneration)) {
        if (state.selectedAccountId == requestAccountId) {
          state = state.copyWith(isSaving: false);
        }
        return;
      }
      state = state.copyWith(
        isSaving: false,
        errorMessage: _taskErrorMessage(e, accountId: requestAccountId),
        errorAccountId: requestAccountId,
      );
      rethrow;
    }
  }

  Future<void> update(String id, TaskDraft draft) async {
    final requestAccountId = draft.accountId;
    final requestGeneration = _loadGeneration;
    _setBusy(id, true, clearError: true);
    try {
      final task = await _updateTask(id, draft);
      if (!_isCurrentAccountRequest(requestAccountId, requestGeneration)) {
        if (state.selectedAccountId == requestAccountId) {
          state = state.copyWith(busyTaskIds: _withoutBusy(id));
        }
        return;
      }
      state = state.copyWith(
        busyTaskIds: _withoutBusy(id),
        selectedTask: task,
        tasks: _replaceTask(state.tasks, task)..sort(_sortTasks),
      );
    } catch (e) {
      if (!_isCurrentAccountRequest(requestAccountId, requestGeneration)) {
        if (state.selectedAccountId == requestAccountId) {
          state = state.copyWith(busyTaskIds: _withoutBusy(id));
        }
        return;
      }
      state = state.copyWith(
        busyTaskIds: _withoutBusy(id),
        errorMessage: _taskErrorMessage(e, accountId: requestAccountId),
        errorAccountId: requestAccountId,
      );
      rethrow;
    }
  }

  Future<void> setEnabled(ManagedTask task, bool enabled) async {
    final requestAccountId = task.accountId;
    final requestGeneration = _loadGeneration;
    final before = state.tasks;
    _setToggling(task.id, true, clearError: true);
    state = state.copyWith(
      tasks: _replaceTask(state.tasks, task.copyWith(enabled: enabled)),
      selectedTask: state.selectedTask?.id == task.id
          ? state.selectedTask!.copyWith(enabled: enabled)
          : state.selectedTask,
    );
    try {
      final updated = await _setTaskEnabled(task, enabled);
      if (!_isCurrentAccountRequest(requestAccountId, requestGeneration)) {
        if (state.selectedAccountId == requestAccountId) {
          state = state.copyWith(togglingTaskIds: _withoutToggling(task.id));
        }
        return;
      }
      state = state.copyWith(
        togglingTaskIds: _withoutToggling(task.id),
        tasks: updated == null
            ? state.tasks
            : _replaceTask(state.tasks, updated),
        selectedTask: updated != null && state.selectedTask?.id == task.id
            ? updated
            : state.selectedTask,
      );
    } catch (e) {
      if (!_isCurrentAccountRequest(requestAccountId, requestGeneration)) {
        if (state.selectedAccountId == requestAccountId) {
          state = state.copyWith(togglingTaskIds: _withoutToggling(task.id));
        }
        return;
      }
      state = state.copyWith(
        tasks: before,
        togglingTaskIds: _withoutToggling(task.id),
        errorMessage: _taskErrorMessage(e, accountId: task.accountId),
        errorAccountId: task.accountId,
      );
      rethrow;
    }
  }

  Future<void> delete(ManagedTask task) async {
    final requestAccountId = task.accountId;
    final requestGeneration = _loadGeneration;
    _setBusy(task.id, true, clearError: true);
    try {
      await _deleteTask(task);
      if (!_isCurrentAccountRequest(requestAccountId, requestGeneration)) {
        if (state.selectedAccountId == requestAccountId) {
          state = state.copyWith(busyTaskIds: _withoutBusy(task.id));
        }
        return;
      }
      state = state.copyWith(
        busyTaskIds: _withoutBusy(task.id),
        clearSelectedTask: state.selectedTask?.id == task.id,
        runs: state.selectedTask?.id == task.id ? const [] : state.runs,
        clearRunOutput: state.selectedTask?.id == task.id,
        tasks: state.tasks.where((item) => item.id != task.id).toList(),
      );
    } catch (e) {
      if (!_isCurrentAccountRequest(requestAccountId, requestGeneration)) {
        if (state.selectedAccountId == requestAccountId) {
          state = state.copyWith(busyTaskIds: _withoutBusy(task.id));
        }
        return;
      }
      state = state.copyWith(
        busyTaskIds: _withoutBusy(task.id),
        errorMessage: _taskErrorMessage(e, accountId: task.accountId),
        errorAccountId: task.accountId,
      );
      rethrow;
    }
  }

  Future<void> runNow(ManagedTask task) async {
    final requestAccountId = task.accountId;
    final requestGeneration = _loadGeneration;
    _setBusy(task.id, true, clearError: true);
    try {
      final run = await _api.runTask(task.id, task.accountId);
      if (!_isCurrentAccountRequest(requestAccountId, requestGeneration)) {
        if (state.selectedAccountId == requestAccountId) {
          state = state.copyWith(busyTaskIds: _withoutBusy(task.id));
        }
        return;
      }
      final next = run == null ? task : task.copyWith(lastRun: run);
      state = state.copyWith(
        busyTaskIds: _withoutBusy(task.id),
        selectedTask: next,
        tasks: _replaceTask(state.tasks, next),
        runs: run == null ? state.runs : [run, ...state.runs],
      );
    } catch (e) {
      if (!_isCurrentAccountRequest(requestAccountId, requestGeneration)) {
        if (state.selectedAccountId == requestAccountId) {
          state = state.copyWith(busyTaskIds: _withoutBusy(task.id));
        }
        return;
      }
      state = state.copyWith(
        busyTaskIds: _withoutBusy(task.id),
        errorMessage: _taskErrorMessage(e, accountId: task.accountId),
        errorAccountId: task.accountId,
      );
      rethrow;
    }
  }

  Future<void> loadRuns(ManagedTask task) async {
    final requestAccountId = task.accountId;
    final requestGeneration = _loadGeneration;
    state = state.copyWith(
      selectedTask: task,
      isLoadingRuns: true,
      clearRunOutput: true,
      clearError: true,
    );
    try {
      final runs = await _api.listRuns(task.id, task.accountId);
      if (!_isCurrentAccountRequest(requestAccountId, requestGeneration)) {
        if (state.selectedAccountId == requestAccountId) {
          state = state.copyWith(isLoadingRuns: false);
        }
        return;
      }
      state = state.copyWith(runs: runs, isLoadingRuns: false);
    } catch (e) {
      if (!_isCurrentAccountRequest(requestAccountId, requestGeneration)) {
        if (state.selectedAccountId == requestAccountId) {
          state = state.copyWith(isLoadingRuns: false);
        }
        return;
      }
      state = state.copyWith(
        isLoadingRuns: false,
        errorMessage: _taskErrorMessage(e, accountId: task.accountId),
        errorAccountId: task.accountId,
      );
    }
  }

  Future<void> loadOutput(TaskRun run) async {
    final task = state.selectedTask;
    if (task == null) return;
    final requestAccountId = task.accountId;
    final requestGeneration = _loadGeneration;
    state = state.copyWith(selectedRunOutput: '', clearError: true);
    try {
      final output = await _api.getRunOutput(task.id, run.id, task.accountId);
      if (!_isCurrentAccountRequest(requestAccountId, requestGeneration)) {
        return;
      }
      state = state.copyWith(selectedRunOutput: output);
    } catch (e) {
      if (!_isCurrentAccountRequest(requestAccountId, requestGeneration)) {
        return;
      }
      state = state.copyWith(
        errorMessage: _taskErrorMessage(e, accountId: task.accountId),
        errorAccountId: task.accountId,
      );
    }
  }

  String? _resolveAccount(List<TaskAccount> accounts, String? current) {
    if (accounts.isEmpty) return null;
    if (current != null && accounts.any((item) => item.accountId == current)) {
      return current;
    }
    return accounts.first.accountId;
  }

  bool _isCurrentAccountRequest(String accountId, int generation) {
    return generation == _loadGeneration &&
        state.selectedAccountId == accountId;
  }

  void _setBusy(String id, bool busy, {bool clearError = false}) {
    state = state.copyWith(
      busyTaskIds: busy ? _withBusy(id) : _withoutBusy(id),
      clearError: clearError,
    );
  }

  Set<String> _withBusy(String id) => {...state.busyTaskIds, id};

  Set<String> _withoutBusy(String id) => {...state.busyTaskIds}..remove(id);

  void _setToggling(String id, bool busy, {bool clearError = false}) {
    state = state.copyWith(
      togglingTaskIds: busy ? _withToggling(id) : _withoutToggling(id),
      clearError: clearError,
    );
  }

  Set<String> _withToggling(String id) => {...state.togglingTaskIds, id};

  Set<String> _withoutToggling(String id) =>
      {...state.togglingTaskIds}..remove(id);

  List<ManagedTask> _replaceTask(List<ManagedTask> tasks, ManagedTask next) {
    final index = tasks.indexWhere((task) => task.id == next.id);
    if (index == -1) return [...tasks, next];
    return [...tasks]..[index] = next;
  }

  static int _sortTasks(ManagedTask a, ManagedTask b) {
    final nextA = a.nextRunAt ?? '';
    final nextB = b.nextRunAt ?? '';
    if (nextA.isEmpty && nextB.isNotEmpty) return 1;
    if (nextA.isNotEmpty && nextB.isEmpty) return -1;
    final nextCompare = nextA.compareTo(nextB);
    if (nextCompare != 0) return nextCompare;
    return a.name.compareTo(b.name);
  }

  Future<List<ManagedTask>> _getCachedTasks(String accountId) {
    final cache = _cache;
    if (cache == null) return Future.value(const <ManagedTask>[]);
    return cache.getTasks(accountId);
  }

  Future<List<ManagedTask>> _syncTasks(String accountId) {
    final cache = _cache;
    if (cache == null) return _api.listTasks(accountId: accountId);
    return cache.syncGateway(accountId);
  }

  Future<ManagedTask> _createTask(TaskDraft draft) {
    final cache = _cache;
    if (cache == null) return _api.createTask(draft);
    return cache.create(draft);
  }

  Future<ManagedTask> _updateTask(String id, TaskDraft draft) {
    final cache = _cache;
    if (cache == null) return _api.updateTask(id, draft);
    return cache.update(id, draft);
  }

  Future<void> _deleteTask(ManagedTask task) {
    final cache = _cache;
    if (cache == null) return _api.deleteTask(task.id, task.accountId);
    return cache.delete(task);
  }

  Future<ManagedTask?> _setTaskEnabled(ManagedTask task, bool enabled) {
    final cache = _cache;
    if (cache == null) {
      return _api.setEnabled(task.id, task.accountId, enabled);
    }
    return cache.setEnabled(task, enabled);
  }
}

String _taskErrorMessage(Object error, {String? accountId}) {
  if (error is DioException) {
    final response = error.response;
    final statusCode = response?.statusCode;
    final code = _responseErrorCode(response?.data);
    final gatewayName = _gatewayDisplayName(accountId);

    if (statusCode == 504 || code == 'gateway_timeout') {
      return '$gatewayName 网关响应超时，请确认 $gatewayName Gateway 正在运行后重试。';
    }
    if (statusCode == 503 || code == 'gateway_unavailable') {
      return '$gatewayName Gateway 未连接，请先启动或重连 gateway。';
    }
    if (statusCode == 501 || code == 'tasks_unsupported') {
      return '$gatewayName 暂不支持任务管理。';
    }
    if (statusCode == 400 || code == 'account_required') {
      return '请选择一个已连接的 gateway 后再刷新任务。';
    }

    final serverMessage = _responseMessage(response?.data);
    if (serverMessage != null && serverMessage.isNotEmpty) {
      return serverMessage;
    }
    if (statusCode != null) {
      return '任务请求失败，服务端返回 $statusCode。';
    }
    return '无法连接 Clawke Server，请检查服务是否正在运行。';
  }

  if (error is FormatException) {
    return '任务接口返回格式异常，请稍后重试。';
  }

  final message = error.toString();
  if (message.isEmpty) return '任务请求失败，请稍后重试。';
  return message;
}

String _gatewayDisplayName(String? accountId) {
  final value = accountId?.trim();
  if (value == null || value.isEmpty) return 'Gateway';
  if (value.toLowerCase() == 'hermes') return 'Hermes';
  if (value.toLowerCase() == 'openclaw') return 'OpenClaw';
  return value;
}

String? _responseErrorCode(Object? data) {
  if (data is Map<String, dynamic>) return data['error'] as String?;
  if (data is Map) return data['error'] as String?;
  return null;
}

String? _responseMessage(Object? data) {
  if (data is Map<String, dynamic>) return data['message'] as String?;
  if (data is Map) return data['message'] as String?;
  return null;
}
