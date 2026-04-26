import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:client/models/gateway_info.dart';
import 'package:client/models/managed_task.dart';
import 'package:client/providers/database_providers.dart';
import 'package:client/providers/gateway_provider.dart';
import 'package:client/providers/tasks_provider.dart';
import 'package:client/widgets/empty_state_panel.dart';
import 'package:client/widgets/gateway_selector_pane.dart';
import 'package:client/widgets/gateway_unavailable_panel.dart';

enum _TaskStatusFilter { all, enabled, running, error }

enum _TaskPage { list, detail, edit, runs, runOutput }

class TasksManagementScreen extends ConsumerStatefulWidget {
  final bool showAppBar;

  const TasksManagementScreen({super.key, this.showAppBar = false});

  @override
  ConsumerState<TasksManagementScreen> createState() =>
      _TasksManagementScreenState();
}

class _TasksManagementScreenState extends ConsumerState<TasksManagementScreen> {
  final _searchController = TextEditingController();
  _TaskStatusFilter _statusFilter = _TaskStatusFilter.all;
  _TaskPage _page = _TaskPage.list;
  String? _activeTaskId;
  String? _activeRunId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshGatewayCache();
      _syncGateways();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<List<GatewayInfo>>>(gatewayListProvider, (_, next) {
      final gateways = next.valueOrNull;
      if (gateways != null) unawaited(_syncGateways(gateways));
    });

    final state = ref.watch(tasksControllerProvider);
    final gateways =
        ref.watch(gatewayListProvider).valueOrNull ?? const <GatewayInfo>[];
    final colorScheme = Theme.of(context).colorScheme;

    final content = Container(
      color: colorScheme.surface,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 980;
          final unavailableGateway = _selectedUnavailableGateway(
            gateways,
            state,
          );
          final body = _buildBody(
            state,
            gateways,
            unavailableGateway: unavailableGateway,
            compact: !wide,
          );

          if (!wide) return body;

          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GatewaySelectorPane(
                gateways: gateways,
                selectedGatewayId: state.selectedAccountId,
                capability: 'tasks',
                errorGatewayId:
                    state.errorAccountId ?? unavailableGateway?.gatewayId,
                issueKeyPrefix: 'tasks_gateway_issue',
                onSelected: _selectAccount,
                onRename: (gatewayId, displayName) => ref
                    .read(gatewayRepositoryProvider)
                    .renameGateway(gatewayId, displayName),
              ),
              Expanded(child: body),
            ],
          );
        },
      ),
    );

    if (!widget.showAppBar) return content;

    return Scaffold(appBar: _buildAppBar(state, gateways), body: content);
  }

  PreferredSizeWidget _buildAppBar(
    TasksState state,
    List<GatewayInfo> gateways,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final unavailableGateway = _selectedUnavailableGateway(gateways, state);
    final hasGatewayIssue =
        unavailableGateway != null || state.errorAccountId != null;

    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        tooltip: _localized(context, 'Back', '返回'),
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      centerTitle: true,
      title: Text(_localized(context, 'Tasks', '任务管理')),
      backgroundColor: colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: _localized(context, 'Refresh', '刷新'),
          onPressed: state.isLoading || hasGatewayIssue
              ? null
              : () => unawaited(_refreshTasks(gateways)),
        ),
        IconButton(
          icon: const Icon(Icons.add),
          tooltip: _localized(context, 'New Task', '新建任务'),
          onPressed: state.selectedAccountId == null || hasGatewayIssue
              ? null
              : () => _openEditor(),
        ),
      ],
    );
  }

  void _refreshGatewayCache() {
    unawaited(
      ref
          .read(gatewayRepositoryProvider)
          .syncFromServer()
          .catchError(
            (Object error, StackTrace stackTrace) =>
                debugPrint('[Gateway] ⚠️ sync failed: $error'),
          ),
    );
  }

  Future<void> _syncGateways([List<GatewayInfo>? gateways]) async {
    final source =
        gateways ??
        ref.read(gatewayListProvider).valueOrNull ??
        const <GatewayInfo>[];
    final state = ref.read(tasksControllerProvider);
    final ordered = orderGatewaysForSelection(
      source,
      'tasks',
      currentGatewayId: state.selectedAccountId,
    );
    final selected = gatewayForSelection(
      source,
      'tasks',
      currentGatewayId: state.selectedAccountId,
    );
    final accounts = _taskAccountsFromGateways(ordered);
    if (selected != null && gatewayUnavailableFor(selected, 'tasks')) {
      _markTasksGatewayUnavailable(accounts, selected);
      return;
    }
    await ref.read(tasksControllerProvider.notifier).syncAccounts(accounts);
  }

  Future<void> _refreshTasks(List<GatewayInfo> gateways) {
    final state = ref.read(tasksControllerProvider);
    final selected = gatewayById(gateways, state.selectedAccountId);
    if (selected != null && gatewayUnavailableFor(selected, 'tasks')) {
      _markTasksGatewayUnavailable(
        _taskAccountsFromGateways(
          orderGatewaysForSelection(
            gateways,
            'tasks',
            currentGatewayId: selected.gatewayId,
          ),
        ),
        selected,
      );
      return Future.value();
    }
    return ref.read(tasksControllerProvider.notifier).refresh();
  }

  List<ManagedTask> _filtered(List<ManagedTask> tasks) {
    final query = _searchController.text.trim().toLowerCase();
    return tasks.where((task) {
      final matchesStatus = switch (_statusFilter) {
        _TaskStatusFilter.all => true,
        _TaskStatusFilter.enabled => task.enabled,
        _TaskStatusFilter.running => _isTaskRunning(task),
        _TaskStatusFilter.error => _isTaskError(task),
      };
      if (!matchesStatus) return false;
      if (query.isEmpty) return true;
      return task.name.toLowerCase().contains(query) ||
          task.schedule.toLowerCase().contains(query) ||
          task.prompt.toLowerCase().contains(query) ||
          task.skills.any((skill) => skill.toLowerCase().contains(query));
    }).toList();
  }

  ManagedTask? _activeTask(TasksState state) {
    final id = _activeTaskId;
    if (id == null) return state.selectedTask;
    for (final task in state.tasks) {
      if (task.id == id) return task;
    }
    if (state.selectedTask?.id == id) return state.selectedTask;
    return null;
  }

  TaskRun? _activeRun(TasksState state) {
    final id = _activeRunId;
    if (id == null) return null;
    for (final run in state.runs) {
      if (run.id == id) return run;
    }
    return null;
  }

  void _showList() {
    setState(() {
      _page = _TaskPage.list;
      _activeTaskId = null;
      _activeRunId = null;
    });
  }

  void _showDetail(ManagedTask task) {
    setState(() {
      _page = _TaskPage.detail;
      _activeTaskId = task.id;
      _activeRunId = null;
    });
  }

  Widget _buildBody(
    TasksState state,
    List<GatewayInfo> gateways, {
    GatewayInfo? unavailableGateway,
    required bool compact,
  }) {
    if (_page == _TaskPage.list) {
      return RefreshIndicator(
        onRefresh: () => _refreshTasks(gateways),
        child: _buildTaskList(
          state,
          gateways,
          unavailableGateway: unavailableGateway,
          compact: compact,
        ),
      );
    }

    final task = _activeTask(state);
    if (_page == _TaskPage.edit) {
      final accountId =
          task?.accountId ??
          state.selectedAccountId ??
          (state.accounts.isEmpty ? null : state.accounts.first.accountId);
      if (accountId == null) {
        return _buildTaskList(
          state,
          gateways,
          unavailableGateway: unavailableGateway,
          compact: compact,
        );
      }
      return _TaskEditPage(
        accountId: accountId,
        initial: task,
        isSaving:
            state.isSaving ||
            (task != null && state.busyTaskIds.contains(task.id)),
        onCancel: () => task == null ? _showList() : _showDetail(task),
        onSave: (draft) => _saveTask(draft, initial: task),
        onDelete: task == null ? null : () => _confirmDeleteTask(task),
      );
    }

    if (task == null) {
      return _buildTaskList(
        state,
        gateways,
        unavailableGateway: unavailableGateway,
        compact: compact,
      );
    }

    if (_page == _TaskPage.runs) {
      return _TaskRunsPage(
        task: task,
        state: state,
        onBack: () => _showDetail(task),
        onOpenOutput: _showRunOutput,
      );
    }

    if (_page == _TaskPage.runOutput) {
      final run = _activeRun(state);
      if (run == null) {
        return _TaskRunsPage(
          task: task,
          state: state,
          onBack: () => _showDetail(task),
          onOpenOutput: _showRunOutput,
        );
      }
      return _TaskRunOutputPage(
        task: task,
        run: run,
        output: state.selectedRunOutput,
        onBack: () => _showRuns(task),
      );
    }

    return _TaskDetailPage(
      task: task,
      onBack: _showList,
      onEdit: () => _openEditor(initial: task),
      onRun: () => _runTask(task),
      onRuns: () => _showRuns(task),
    );
  }

  Widget _buildTaskList(
    TasksState state,
    List<GatewayInfo> gateways, {
    GatewayInfo? unavailableGateway,
    required bool compact,
  }) {
    final filteredTasks = _filtered(state.tasks);
    final showUnavailablePanel = unavailableGateway != null;
    final showDisconnected = !showUnavailablePanel && state.accounts.isEmpty;
    final showLoading =
        !showUnavailablePanel && state.isLoading && state.tasks.isEmpty;
    final showEmpty =
        !showUnavailablePanel &&
        !showDisconnected &&
        !showLoading &&
        filteredTasks.isEmpty;
    final hasMobileGatewaySelector = compact && gateways.isNotEmpty;

    if (!showUnavailablePanel &&
        (showDisconnected || showLoading || showEmpty)) {
      return _buildTaskStateList(
        state,
        gateways,
        compact: compact,
        showDisconnected: showDisconnected,
        showLoading: showLoading,
      );
    }

    final padding = compact ? 16.0 : 28.0;
    final toolbar = _Toolbar(
      controller: _searchController,
      filter: _statusFilter,
      compact: compact,
      total: state.tasks.length,
      enabled: state.tasks.where((task) => task.enabled).length,
      running: state.tasks.where(_isTaskRunning).length,
      error: state.tasks.where(_isTaskError).length,
      onFilterChanged: (filter) => setState(() => _statusFilter = filter),
      onChanged: (_) => setState(() {}),
    );
    final topItems = <Widget>[
      if (hasMobileGatewaySelector) ...[
        GatewayMobileSelectorButton(
          gateways: gateways,
          selectedGatewayId: state.selectedAccountId,
          capability: 'tasks',
          errorGatewayId: state.errorAccountId ?? unavailableGateway?.gatewayId,
          issueKeyPrefix: 'tasks_gateway_issue',
          onSelected: _selectAccount,
        ),
        const SizedBox(height: 18),
      ],
      _Header(
        isLoading: state.isLoading,
        canCreate: state.selectedAccountId != null && !showUnavailablePanel,
        hasGatewayIssue: showUnavailablePanel || state.errorAccountId != null,
        compact: compact && widget.showAppBar,
        onCreate: () => _openEditor(),
        onRefresh: () => unawaited(_refreshTasks(gateways)),
      ),
      const SizedBox(height: 18),
      toolbar,
      const SizedBox(height: 12),
      if (!showUnavailablePanel)
        _ContentMeta(visibleCount: filteredTasks.length)
      else
        SizedBox(
          height: gatewayUnavailablePanelHeight(context, compact),
          child: GatewayUnavailablePanel(
            title: gatewayUnavailableTitle(
              context,
              unavailableGateway,
              capability: 'tasks',
              capabilityNameZh: '任务管理',
              capabilityNameEn: 'task management',
            ),
            message: _localized(
              context,
              'Reconnect the gateway to refresh tasks.',
              '连接恢复后，任务列表会自动刷新。',
            ),
            footnote: _localized(
              context,
              'No task request will be sent.',
              '当前不会发起任务请求',
            ),
          ),
        ),
      if (!showUnavailablePanel) const SizedBox(height: 12),
    ];

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: EdgeInsets.only(left: padding, top: padding, right: padding),
          sliver: SliverList(delegate: SliverChildListDelegate(topItems)),
        ),
        if (!showUnavailablePanel)
          SliverPadding(
            padding: EdgeInsets.only(
              left: padding,
              right: padding,
              bottom: padding,
            ),
            sliver: SliverToBoxAdapter(
              child: _TaskCardWrap(
                tasks: filteredTasks,
                compact: compact,
                selectedTaskId: state.selectedTask?.id,
                busyTaskIds: state.busyTaskIds,
                togglingTaskIds: state.togglingTaskIds,
                onOpen: _showDetail,
                onToggle: _toggleTask,
                onRun: _runTask,
                onRuns: _showRuns,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTaskStateList(
    TasksState state,
    List<GatewayInfo> gateways, {
    required bool compact,
    required bool showDisconnected,
    required bool showLoading,
  }) {
    final padding = compact ? 16.0 : 28.0;
    final topItems = <Widget>[
      if (compact && gateways.isNotEmpty) ...[
        GatewayMobileSelectorButton(
          gateways: gateways,
          selectedGatewayId: state.selectedAccountId,
          capability: 'tasks',
          errorGatewayId: state.errorAccountId,
          issueKeyPrefix: 'tasks_gateway_issue',
          onSelected: _selectAccount,
        ),
        const SizedBox(height: 18),
      ],
      _Header(
        isLoading: state.isLoading,
        canCreate: state.selectedAccountId != null,
        hasGatewayIssue: state.errorAccountId != null,
        compact: compact && widget.showAppBar,
        onCreate: () => _openEditor(),
        onRefresh: () => unawaited(_refreshTasks(gateways)),
      ),
      const SizedBox(height: 18),
      _Toolbar(
        controller: _searchController,
        filter: _statusFilter,
        compact: compact,
        total: state.tasks.length,
        enabled: state.tasks.where((task) => task.enabled).length,
        running: state.tasks.where(_isTaskRunning).length,
        error: state.tasks.where(_isTaskError).length,
        onFilterChanged: (filter) => setState(() => _statusFilter = filter),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 18),
    ];
    final statePanel = showDisconnected
        ? const _DisconnectedPanel()
        : showLoading
        ? const _LoadingPanel()
        : const _EmptyPanel();

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: EdgeInsets.only(left: padding, top: padding, right: padding),
          sliver: SliverList(delegate: SliverChildListDelegate(topItems)),
        ),
        SliverPadding(
          padding: EdgeInsets.only(
            left: padding,
            right: padding,
            bottom: padding,
          ),
          sliver: SliverFillRemaining(hasScrollBody: false, child: statePanel),
        ),
      ],
    );
  }

  Future<void> _selectAccount(String accountId) async {
    final gateways =
        ref.read(gatewayListProvider).valueOrNull ?? const <GatewayInfo>[];
    final gateway = gatewayById(gateways, accountId);
    if (gateway != null && gatewayUnavailableFor(gateway, 'tasks')) {
      _markTasksGatewayUnavailable(
        _taskAccountsFromGateways(
          orderGatewaysForSelection(
            gateways,
            'tasks',
            currentGatewayId: accountId,
          ),
        ),
        gateway,
      );
      return;
    }
    await ref.read(tasksControllerProvider.notifier).selectAccount(accountId);
    if (mounted) _showList();
  }

  GatewayInfo? _selectedUnavailableGateway(
    List<GatewayInfo> gateways,
    TasksState state,
  ) {
    final gateway = gatewayById(gateways, state.selectedAccountId);
    if (gateway == null || !gatewayUnavailableFor(gateway, 'tasks')) {
      return null;
    }
    return gateway;
  }

  List<TaskAccount> _taskAccountsFromGateways(List<GatewayInfo> gateways) {
    return gateways
        .where((gateway) => gateway.supports('tasks'))
        .map(
          (gateway) => TaskAccount(
            accountId: gateway.gatewayId,
            agentName: gateway.displayName,
          ),
        )
        .toList();
  }

  void _markTasksGatewayUnavailable(
    List<TaskAccount> accounts,
    GatewayInfo gateway,
  ) {
    ref
        .read(tasksControllerProvider.notifier)
        .selectUnavailableAccount(
          accounts,
          gateway.gatewayId,
          gatewayUnavailableStateMessage(context, gateway),
        );
  }

  void _openEditor({ManagedTask? initial}) {
    final accountId =
        initial?.accountId ??
        ref.read(tasksControllerProvider).selectedAccountId;
    if (accountId == null) return;
    setState(() {
      _page = _TaskPage.edit;
      _activeTaskId = initial?.id;
    });
  }

  Future<void> _saveTask(TaskDraft draft, {ManagedTask? initial}) async {
    final notifier = ref.read(tasksControllerProvider.notifier);
    try {
      if (initial == null) {
        await notifier.create(draft);
      } else {
        await notifier.update(initial.id, draft);
      }
      final savedTask = ref.read(tasksControllerProvider).selectedTask;
      if (mounted) {
        setState(() {
          _page = _TaskPage.detail;
          _activeTaskId = savedTask?.id ?? initial?.id;
        });
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              initial == null
                  ? _localized(context, 'Task created', '任务已创建')
                  : _localized(context, 'Task saved', '任务已保存'),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
      // The persistent error panel displays the API error.
    }
  }

  Future<void> _toggleTask(ManagedTask task, bool enabled) async {
    try {
      await ref
          .read(tasksControllerProvider.notifier)
          .setEnabled(task, enabled);
    } catch (_) {
      // The persistent error panel displays the API error.
    }
  }

  Future<void> _confirmDeleteTask(ManagedTask task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_localized(context, 'Delete task?', '删除任务？')),
        content: Text(
          _localized(
            context,
            'This will delete task ${task.name}. This action cannot be undone.\nContinue?',
            '将删除任务 ${task.name}，此操作不可撤销。\n是否继续？',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(_localized(context, 'Cancel', '取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: Text(_localized(context, 'Delete', '删除')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(tasksControllerProvider.notifier).delete(task);
      if (!mounted) return;
      _showList();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_localized(context, 'Task deleted', '任务已删除')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      // The persistent error panel displays the API error.
    }
  }

  Future<void> _runTask(ManagedTask task) async {
    try {
      await ref.read(tasksControllerProvider.notifier).runNow(task);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_localized(context, 'Task triggered', '已触发任务')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
      // The persistent error panel displays the API error.
    }
  }

  Future<void> _showRuns(ManagedTask task) async {
    setState(() {
      _page = _TaskPage.runs;
      _activeTaskId = task.id;
      _activeRunId = null;
    });
    await ref.read(tasksControllerProvider.notifier).loadRuns(task);
  }

  Future<void> _showRunOutput(TaskRun run) async {
    setState(() {
      _page = _TaskPage.runOutput;
      _activeRunId = run.id;
    });
    await ref.read(tasksControllerProvider.notifier).loadOutput(run);
  }
}

class _Header extends StatelessWidget {
  final bool isLoading;
  final bool canCreate;
  final bool hasGatewayIssue;
  final bool compact;
  final VoidCallback onCreate;
  final VoidCallback onRefresh;

  const _Header({
    required this.isLoading,
    required this.canCreate,
    required this.hasGatewayIssue,
    required this.compact,
    required this.onCreate,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    if (compact) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Wrap(
      spacing: 16,
      runSpacing: 16,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _localized(context, 'Task Management', '任务管理'),
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _localized(
                  context,
                  'Manage agent-side schedules, manual triggers, run history, and outputs.',
                  '管理 agent 侧任务的生命周期、手动触发、执行记录和结果。',
                ),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            IconButton.filledTonal(
              onPressed: isLoading || hasGatewayIssue ? null : onRefresh,
              icon: const Icon(Icons.refresh),
              tooltip: _localized(context, 'Refresh', '刷新'),
            ),
            FilledButton.icon(
              onPressed: canCreate ? onCreate : null,
              icon: const Icon(Icons.add),
              label: Text(_localized(context, 'New Task', '新建任务')),
            ),
          ],
        ),
      ],
    );
  }
}

class _Toolbar extends StatelessWidget {
  final TextEditingController controller;
  final _TaskStatusFilter filter;
  final bool compact;
  final int total;
  final int enabled;
  final int running;
  final int error;
  final ValueChanged<_TaskStatusFilter> onFilterChanged;
  final ValueChanged<String> onChanged;

  const _Toolbar({
    required this.controller,
    required this.filter,
    required this.compact,
    required this.total,
    required this.enabled,
    required this.running,
    required this.error,
    required this.onFilterChanged,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final searchTextStyle = theme.textTheme.bodyMedium;
    final filterTextStyle = theme.textTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.w600,
    );

    FilterChip filterChip({
      required String label,
      required bool selected,
      required VoidCallback onSelected,
      Key? key,
    }) {
      return FilterChip(
        key: key,
        label: Text(label),
        labelStyle: filterTextStyle,
        selected: selected,
        onSelected: (_) => onSelected(),
      );
    }

    if (!compact) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 320,
              child: TextField(
                controller: controller,
                onChanged: onChanged,
                style: searchTextStyle,
                decoration: InputDecoration(
                  hintText: _localized(context, 'Search tasks...', '搜索任务...'),
                  hintStyle: searchTextStyle?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            filterChip(
              label: '${_localized(context, 'All', '全部')} $total',
              selected: filter == _TaskStatusFilter.all,
              onSelected: () => onFilterChanged(_TaskStatusFilter.all),
            ),
            filterChip(
              label: '${_localized(context, 'Enabled', '已启用')} $enabled',
              selected: filter == _TaskStatusFilter.enabled,
              onSelected: () => onFilterChanged(_TaskStatusFilter.enabled),
            ),
            filterChip(
              label: '${_localized(context, 'Running', '运行中')} $running',
              selected: filter == _TaskStatusFilter.running,
              onSelected: () => onFilterChanged(_TaskStatusFilter.running),
            ),
            filterChip(
              label: '${_localized(context, 'Error', '异常')} $error',
              selected: filter == _TaskStatusFilter.error,
              onSelected: () => onFilterChanged(_TaskStatusFilter.error),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final searchWidth = compact
            ? constraints.maxWidth
            : constraints.maxWidth < 320
            ? constraints.maxWidth
            : 320.0;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: searchWidth,
              child: TextField(
                controller: controller,
                onChanged: onChanged,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: _localized(context, 'Search tasks...', '搜索任务...'),
                  isDense: true,
                  border: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                  ),
                ),
              ),
            ),
            SegmentedButton<_TaskStatusFilter>(
              selected: {filter},
              onSelectionChanged: (selected) => onFilterChanged(selected.first),
              segments: [
                ButtonSegment(
                  value: _TaskStatusFilter.all,
                  label: Text('${_localized(context, 'All', '全部')} $total'),
                ),
                ButtonSegment(
                  value: _TaskStatusFilter.enabled,
                  label: Text(
                    '${_localized(context, 'Enabled', '已启用')} $enabled',
                  ),
                ),
                ButtonSegment(
                  value: _TaskStatusFilter.running,
                  label: Text(
                    '${_localized(context, 'Running', '运行中')} $running',
                  ),
                ),
                ButtonSegment(
                  value: _TaskStatusFilter.error,
                  label: Text('${_localized(context, 'Error', '异常')} $error'),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _ContentMeta extends StatelessWidget {
  final int visibleCount;

  const _ContentMeta({required this.visibleCount});

  @override
  Widget build(BuildContext context) {
    return Text(
      _localized(
        context,
        'Showing $visibleCount tasks, sorted by next run and name',
        '当前显示 $visibleCount 个任务，按下次执行时间和名称排序',
      ),
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _TaskCardWrap extends StatelessWidget {
  final List<ManagedTask> tasks;
  final bool compact;
  final String? selectedTaskId;
  final Set<String> busyTaskIds;
  final Set<String> togglingTaskIds;
  final ValueChanged<ManagedTask> onOpen;
  final void Function(ManagedTask task, bool enabled) onToggle;
  final ValueChanged<ManagedTask> onRun;
  final ValueChanged<ManagedTask> onRuns;

  const _TaskCardWrap({
    required this.tasks,
    required this.compact,
    required this.selectedTaskId,
    required this.busyTaskIds,
    required this.togglingTaskIds,
    required this.onOpen,
    required this.onToggle,
    required this.onRun,
    required this.onRuns,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = !compact && constraints.maxWidth >= 1260 ? 2 : 1;
        const gap = 14.0;
        final cardWidth = columns == 1
            ? constraints.maxWidth
            : (constraints.maxWidth - gap) / 2;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final task in tasks)
              SizedBox(
                width: cardWidth,
                child: _TaskCard(
                  task: task,
                  selected: selectedTaskId == task.id,
                  isBusy: busyTaskIds.contains(task.id),
                  isToggleBusy: togglingTaskIds.contains(task.id),
                  onOpen: onOpen,
                  onToggle: onToggle,
                  onRun: onRun,
                  onRuns: onRuns,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _TaskCard extends StatelessWidget {
  final ManagedTask task;
  final bool selected;
  final bool isBusy;
  final bool isToggleBusy;
  final ValueChanged<ManagedTask> onOpen;
  final void Function(ManagedTask task, bool enabled) onToggle;
  final ValueChanged<ManagedTask> onRun;
  final ValueChanged<ManagedTask> onRuns;

  const _TaskCard({
    required this.task,
    required this.selected,
    required this.isBusy,
    required this.isToggleBusy,
    required this.onOpen,
    required this.onToggle,
    required this.onRun,
    required this.onRuns,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final statusColor = _statusColor(colorScheme, task);
    final accentColor = _taskAccentColor(colorScheme, task);
    return Material(
      key: ValueKey('task_card_${task.id}'),
      color: selected
          ? colorScheme.primaryContainer.withValues(alpha: 0.35)
          : colorScheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: () => onOpen(task),
        borderRadius: BorderRadius.circular(18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected
                  ? colorScheme.primary
                  : colorScheme.outlineVariant,
            ),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                colorScheme.surfaceContainerHighest.withValues(alpha: 0.62),
                colorScheme.surfaceContainerLowest,
              ],
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                left: 0,
                top: 16,
                bottom: 16,
                child: Container(
                  width: 3,
                  decoration: BoxDecoration(
                    color: accentColor,
                    borderRadius: const BorderRadius.horizontal(
                      right: Radius.circular(3),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(18),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final rightRail = constraints.maxWidth >= 980;
                    final icon = _TaskIcon(task: task, color: statusColor);
                    final main = _TaskCardMain(task: task);
                    final controls = _TaskControls(
                      key: ValueKey('task_card_controls_${task.id}'),
                      task: task,
                      color: statusColor,
                      vertical: rightRail,
                      isBusy: isBusy,
                      isToggleBusy: isToggleBusy,
                      onToggle: onToggle,
                      onRun: onRun,
                      onRuns: onRuns,
                    );

                    if (rightRail) {
                      return ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 160),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            icon,
                            const SizedBox(width: 18),
                            Expanded(child: main),
                            const SizedBox(width: 18),
                            SizedBox(width: 176, child: controls),
                          ],
                        ),
                      );
                    }

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            icon,
                            const SizedBox(width: 18),
                            Expanded(child: main),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Align(
                          alignment: Alignment.centerRight,
                          child: controls,
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TaskIcon extends StatelessWidget {
  final ManagedTask task;
  final Color color;

  const _TaskIcon({required this.task, required this.color});

  @override
  Widget build(BuildContext context) {
    final iconData = _taskIcon(task);
    return Container(
      key: ValueKey('task_card_icon_${task.id}'),
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(iconData, color: color, size: 26),
    );
  }
}

class _TaskCardMain extends StatelessWidget {
  final ManagedTask task;

  const _TaskCardMain({required this.task});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final schedule = task.scheduleText ?? task.schedule;
    return Column(
      key: ValueKey('task_card_main_${task.id}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 9,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              task.name.isEmpty ? task.id : task.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            if (schedule.isNotEmpty)
              _TaskTag(
                text: schedule,
                color: colorScheme.primary,
                filled: true,
              ),
            _TaskTag(
              text: _localized(context, 'Scheduled task', '定时任务'),
              color: colorScheme.onSurfaceVariant,
            ),
          ],
        ),
        const SizedBox(height: 9),
        Text(
          task.prompt,
          key: ValueKey('task_card_desc_${task.id}'),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurface.withValues(alpha: 0.86),
            height: 1.42,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        _TaskMetaLine(task: task),
      ],
    );
  }
}

class _TaskTag extends StatelessWidget {
  final String text;
  final Color color;
  final bool filled;

  const _TaskTag({
    required this.text,
    required this.color,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 25,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: filled
            ? color.withValues(alpha: 0.18)
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(13),
      ),
      alignment: Alignment.center,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: filled
              ? color
              : Theme.of(context).colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _TaskMetaLine extends StatelessWidget {
  final ManagedTask task;

  const _TaskMetaLine({required this.task});

  @override
  Widget build(BuildContext context) {
    final parts = <String>[
      if (task.nextRunAt != null && task.nextRunAt!.isNotEmpty)
        '${_localized(context, 'Next', '下次')} ${task.nextRunAt}'
      else if ((task.scheduleText ?? task.schedule).isNotEmpty)
        task.scheduleText ?? task.schedule
      else
        _localized(context, 'No schedule', '无定时计划'),
      if (task.lastRun != null)
        '${_localized(context, 'Last', '上次')}${_runStatusLabel(context, task.lastRun!.status)} ${task.lastRun!.startedAt}',
      if (task.skills.isNotEmpty)
        '${_localized(context, 'Skills', '技能')}：${task.skills.take(3).join(', ')}'
      else if (task.deliver != null && task.deliver!.isNotEmpty)
        '${_localized(context, 'Deliver', '交付')}：${task.deliver}',
    ];
    return Wrap(
      spacing: 11,
      runSpacing: 6,
      children: [
        for (final part in parts)
          Text(
            part,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
      ],
    );
  }
}

class _TaskControls extends StatelessWidget {
  final ManagedTask task;
  final Color color;
  final bool vertical;
  final bool isBusy;
  final bool isToggleBusy;
  final void Function(ManagedTask task, bool enabled) onToggle;
  final ValueChanged<ManagedTask> onRun;
  final ValueChanged<ManagedTask> onRuns;

  const _TaskControls({
    super.key,
    required this.task,
    required this.color,
    required this.vertical,
    required this.isBusy,
    required this.isToggleBusy,
    required this.onToggle,
    required this.onRun,
    required this.onRuns,
  });

  @override
  Widget build(BuildContext context) {
    final top = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StatusPill(label: _statusLabel(context, task), color: color),
        const SizedBox(width: 10),
        if (isBusy || isToggleBusy)
          const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else
          SizedBox(
            width: 50,
            height: 30,
            child: Transform.scale(
              scale: 0.82,
              child: Switch(
                value: task.enabled,
                onChanged: (value) => onToggle(task, value),
              ),
            ),
          ),
      ],
    );

    final actions = [
      _TaskActionButton(
        icon: Icons.play_arrow,
        label: _localized(context, 'Run now', '立即执行'),
        onPressed: isBusy ? null : () => onRun(task),
      ),
      _TaskActionButton(
        icon: Icons.receipt_long_outlined,
        label: _localized(context, 'Run History', '执行记录'),
        onPressed: isBusy ? null : () => onRuns(task),
        secondary: true,
      ),
    ];

    if (vertical) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          top,
          const SizedBox(height: 10),
          for (final action in actions) ...[
            SizedBox(width: double.infinity, child: action),
            if (action != actions.last) const SizedBox(height: 8),
          ],
        ],
      );
    }

    return Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 10,
      runSpacing: 8,
      children: [top, ...actions],
    );
  }
}

class _TaskActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool secondary;

  const _TaskActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.secondary = false,
  });

  @override
  Widget build(BuildContext context) {
    final child = Text(label);
    if (secondary) {
      return OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: child,
      );
    }
    return FilledButton.tonalIcon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: child,
    );
  }
}

class _TaskPageShell extends StatelessWidget {
  final String title;
  final VoidCallback onBack;
  final Widget? action;
  final List<Widget> children;

  const _TaskPageShell({
    required this.title,
    required this.onBack,
    required this.children,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _TaskSubPageAppBar(title: title, onBack: onBack, action: action),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      ],
    );
  }
}

class _TaskSubPageAppBar extends StatelessWidget {
  final String title;
  final VoidCallback onBack;
  final Widget? action;

  const _TaskSubPageAppBar({
    required this.title,
    required this.onBack,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('task_page_app_bar'),
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final sideWidth = constraints.maxWidth < 560 ? 112.0 : 180.0;
          return Row(
            children: [
              SizedBox(
                width: sideWidth,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    key: const ValueKey('task_app_bar_back'),
                    onPressed: onBack,
                    icon: const Icon(Icons.arrow_back),
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: sideWidth,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: action ?? const SizedBox.shrink(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TaskAppBarAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  const _TaskAppBarAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return TextButton.icon(
      key: const ValueKey('task_app_bar_action'),
      onPressed: busy ? null : onPressed,
      style: TextButton.styleFrom(
        foregroundColor: colorScheme.primary,
        textStyle: Theme.of(
          context,
        ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
      ),
      icon: busy
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colorScheme.primary,
              ),
            )
          : Icon(icon, size: 20),
      label: Text(label),
    );
  }
}

class _TaskDetailPage extends StatelessWidget {
  final ManagedTask task;
  final VoidCallback onBack;
  final VoidCallback onEdit;
  final VoidCallback onRun;
  final VoidCallback onRuns;

  const _TaskDetailPage({
    required this.task,
    required this.onBack,
    required this.onEdit,
    required this.onRun,
    required this.onRuns,
  });

  @override
  Widget build(BuildContext context) {
    return _TaskPageShell(
      title: _localized(context, 'Task Detail', '任务详情'),
      onBack: onBack,
      action: _TaskAppBarAction(
        icon: Icons.edit_outlined,
        label: _localized(context, 'Edit Task', '编辑任务'),
        onPressed: onEdit,
      ),
      children: [
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton.tonalIcon(
              onPressed: onRun,
              icon: const Icon(Icons.play_arrow),
              label: Text(_localized(context, 'Run now', '立即执行')),
            ),
            OutlinedButton.icon(
              onPressed: onRuns,
              icon: const Icon(Icons.receipt_long_outlined),
              label: Text(_localized(context, 'Run History', '执行记录')),
            ),
          ],
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 760;
            final definition = _DetailPanel(
              key: const ValueKey('task_detail_definition'),
              title: _localized(context, 'Task Definition', '任务定义'),
              child: _KeyValueList(
                rows: [
                  (
                    _localized(context, 'Name', '名称'),
                    task.name.isEmpty ? task.id : task.name,
                  ),
                  (
                    _localized(context, 'Gateway', 'Gateway'),
                    '${task.agent} / ${task.accountId}',
                  ),
                  (
                    _localized(context, 'Status', '状态'),
                    _statusLabel(context, task),
                  ),
                  (
                    _localized(context, 'Schedule', '计划'),
                    task.scheduleText ?? task.schedule,
                  ),
                  (
                    _localized(context, 'Next Run', '下次运行'),
                    task.nextRunAt ??
                        _localized(context, 'Not scheduled', '未计划'),
                  ),
                  (
                    _localized(context, 'Enabled', '启用'),
                    task.enabled
                        ? _localized(context, 'Yes', '是')
                        : _localized(context, 'No', '否'),
                  ),
                ],
              ),
            );
            final recent = _DetailPanel(
              key: const ValueKey('task_detail_recent'),
              title: _localized(context, 'Latest State', '最近状态'),
              child: _KeyValueList(
                rows: [
                  (
                    _localized(context, 'Latest Run', '最近执行'),
                    task.lastRun?.startedAt ??
                        _localized(context, 'No runs yet', '暂无执行'),
                  ),
                  (
                    _localized(context, 'Result', '结果'),
                    task.lastRun == null
                        ? _localized(context, 'Unknown', '未知')
                        : _runStatusLabel(context, task.lastRun!.status),
                  ),
                  (
                    _localized(context, 'Output', '输出'),
                    task.lastRun?.outputPreview ??
                        _localized(context, 'No output preview', '暂无输出摘要'),
                  ),
                  (
                    _localized(context, 'Updated', '更新时间'),
                    task.updatedAt ?? _localized(context, 'Unknown', '未知'),
                  ),
                ],
              ),
            );

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (wide)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: definition),
                      const SizedBox(width: 16),
                      Expanded(child: recent),
                    ],
                  )
                else ...[
                  definition,
                  const SizedBox(height: 16),
                  recent,
                ],
                const SizedBox(height: 16),
                _DetailPanel(
                  key: const ValueKey('task_detail_execution'),
                  title: _localized(context, 'Execution Task', '执行任务'),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 220),
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                    child: SelectableText(
                      task.prompt,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _TaskRunsPage extends StatelessWidget {
  final ManagedTask task;
  final TasksState state;
  final VoidCallback onBack;
  final ValueChanged<TaskRun> onOpenOutput;

  const _TaskRunsPage({
    required this.task,
    required this.state,
    required this.onBack,
    required this.onOpenOutput,
  });

  @override
  Widget build(BuildContext context) {
    return _TaskPageShell(
      title: _localized(context, 'Run History', '执行记录'),
      onBack: onBack,
      children: [
        _DetailPanel(
          title: _localized(context, 'Task Summary', '任务摘要'),
          child: _KeyValueList(
            rows: [
              (_localized(context, 'Name', '名称'), task.name),
              (
                _localized(context, 'Gateway', 'Gateway'),
                '${task.agent} / ${task.accountId}',
              ),
              (
                _localized(context, 'Schedule', '计划'),
                task.scheduleText ?? task.schedule,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (state.isLoadingRuns)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(48),
              child: CircularProgressIndicator(),
            ),
          )
        else if (state.runs.isEmpty)
          _StatePanel(
            icon: Icons.receipt_long_outlined,
            title: _localized(context, 'No runs yet', '暂无执行记录'),
            message: _localized(
              context,
              'Run this task to inspect execution output.',
              '执行任务后即可查看执行结果。',
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: state.runs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final run = state.runs[index];
              return _RunTile(run: run, onTap: () => onOpenOutput(run));
            },
          ),
      ],
    );
  }
}

class _TaskRunOutputPage extends StatelessWidget {
  final ManagedTask task;
  final TaskRun run;
  final String? output;
  final VoidCallback onBack;

  const _TaskRunOutputPage({
    required this.task,
    required this.run,
    required this.output,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final body = output == null || output!.isEmpty
        ? _localized(context, 'Loading output...', '正在加载结果...')
        : output!;
    return _TaskPageShell(
      title: _localized(context, 'Run Output', '执行结果'),
      onBack: onBack,
      children: [
        _DetailPanel(
          title: _localized(context, 'Run Metadata', '执行信息'),
          child: _KeyValueList(
            rows: [
              (_localized(context, 'Task', '任务'), task.name),
              (
                _localized(context, 'Status', '状态'),
                _runStatusLabel(context, run.status),
              ),
              (_localized(context, 'Started', '开始时间'), run.startedAt),
              if (run.finishedAt != null && run.finishedAt!.isNotEmpty)
                (_localized(context, 'Finished', '结束时间'), run.finishedAt!),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          constraints: const BoxConstraints(minHeight: 360),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: SelectableText(
            body,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
          ),
        ),
      ],
    );
  }
}

class _DetailPanel extends StatelessWidget {
  final String title;
  final Widget child;

  const _DetailPanel({super.key, required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _KeyValueList extends StatelessWidget {
  final List<(String, String)> rows;

  const _KeyValueList({required this.rows});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 96,
                  child: Text(
                    row.$1,
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    row.$2,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _RunTile extends StatelessWidget {
  final TaskRun run;
  final VoidCallback onTap;

  const _RunTile({required this.run, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = _runColor(colorScheme, run.status);
    return Material(
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(8),
      child: ListTile(
        onTap: onTap,
        leading: Icon(Icons.circle, color: color, size: 12),
        title: Text(_runStatusLabel(context, run.status)),
        subtitle: Text(
          [
            run.startedAt,
            if (run.outputPreview != null && run.outputPreview!.isNotEmpty)
              run.outputPreview!,
            if (run.error != null && run.error!.isNotEmpty) run.error!,
          ].join('\n'),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.circle, size: 9, color: color),
        const SizedBox(width: 7),
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _TaskEditPage extends StatefulWidget {
  final String accountId;
  final ManagedTask? initial;
  final bool isSaving;
  final ValueChanged<TaskDraft> onSave;
  final VoidCallback onCancel;
  final VoidCallback? onDelete;

  const _TaskEditPage({
    required this.accountId,
    required this.initial,
    required this.isSaving,
    required this.onSave,
    required this.onCancel,
    required this.onDelete,
  });

  @override
  State<_TaskEditPage> createState() => _TaskEditPageState();
}

class _TaskEditPageState extends State<_TaskEditPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _scheduleController;
  late final TextEditingController _promptController;
  late final TextEditingController _skillsController;
  late final TextEditingController _deliverController;
  late bool _enabled;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _nameController = TextEditingController(text: initial?.name ?? '');
    _scheduleController = TextEditingController(text: initial?.schedule ?? '');
    _promptController = TextEditingController(text: initial?.prompt ?? '');
    _skillsController = TextEditingController(
      text: initial?.skills.join(', ') ?? '',
    );
    _deliverController = TextEditingController(text: initial?.deliver ?? '');
    _enabled = initial?.enabled ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _scheduleController.dispose();
    _promptController.dispose();
    _skillsController.dispose();
    _deliverController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final title = widget.initial == null
        ? _localized(context, 'New Task', '新建任务')
        : _localized(context, 'Edit Task', '编辑任务');
    return _TaskPageShell(
      title: title,
      onBack: widget.onCancel,
      action: _TaskAppBarAction(
        icon: widget.initial == null ? Icons.add : Icons.save_outlined,
        label: widget.initial == null
            ? _localized(context, 'Create', '创建')
            : _localized(context, 'Save', '保存'),
        onPressed: _submit,
        busy: widget.isSaving,
      ),
      children: [
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _DetailPanel(
                title: _localized(context, 'Basic Info', '基础信息'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      widget.accountId,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        labelText: _localized(context, 'Name', '名称'),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _scheduleController,
                            decoration: InputDecoration(
                              labelText: _localized(context, 'Schedule', '计划'),
                              hintText: '0 9 * * *',
                              border: const OutlineInputBorder(),
                            ),
                            validator: (value) =>
                                value == null || value.trim().isEmpty
                                ? _localized(context, 'Required', '必填')
                                : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _deliverController,
                            decoration: InputDecoration(
                              labelText: _localized(
                                context,
                                'Delivery',
                                '交付方式',
                              ),
                              hintText: _localized(context, 'Optional', '可选'),
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _skillsController,
                      decoration: InputDecoration(
                        labelText: _localized(context, 'Skills', '技能'),
                        hintText: _localized(
                          context,
                          'Comma separated skill ids',
                          '用逗号分隔技能 ID',
                        ),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _DetailPanel(
                title: _localized(context, 'Task Prompt', '任务提示词'),
                child: TextFormField(
                  controller: _promptController,
                  minLines: 10,
                  maxLines: 16,
                  decoration: InputDecoration(
                    labelText: _localized(context, 'Prompt Content', '提示词内容'),
                    alignLabelWithHint: true,
                    border: const OutlineInputBorder(),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? _localized(context, 'Required', '必填')
                      : null,
                ),
              ),
            ],
          ),
        ),
        if (widget.initial != null && widget.onDelete != null) ...[
          const SizedBox(height: 16),
          _DetailPanel(
            key: const ValueKey('task_edit_danger_zone'),
            title: _localized(context, 'Danger Zone', '危险操作'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _localized(
                    context,
                    'Deleting this task removes its definition and schedule. This action cannot be undone.',
                    '删除任务后，任务定义和执行计划会被移除，此操作不可撤销。',
                  ),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: widget.isSaving ? null : widget.onDelete,
                    icon: const Icon(Icons.delete_outline),
                    label: Text(_localized(context, 'Delete Task', '删除任务')),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colorScheme.error,
                      side: BorderSide(
                        color: colorScheme.error.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final skills = _skillsController.text
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    widget.onSave(
      TaskDraft(
        accountId: widget.accountId,
        name: _nameController.text,
        schedule: _scheduleController.text,
        prompt: _promptController.text,
        enabled: _enabled,
        skills: skills,
        deliver: _deliverController.text.trim().isEmpty
            ? null
            : _deliverController.text.trim(),
      ),
    );
  }
}

class _DisconnectedPanel extends StatelessWidget {
  const _DisconnectedPanel();

  @override
  Widget build(BuildContext context) {
    return _StatePanel(
      icon: Icons.hub_outlined,
      title: _localized(context, 'No gateway connected', '暂无已连接 Gateway'),
      message: _localized(
        context,
        'Task management becomes available after Hermes or OpenClaw connects.',
        'Hermes 或 OpenClaw 连接后即可管理任务。',
      ),
    );
  }
}

class _LoadingPanel extends StatelessWidget {
  const _LoadingPanel();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(48),
        child: CircularProgressIndicator(),
      ),
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel();

  @override
  Widget build(BuildContext context) {
    return _StatePanel(
      icon: Icons.task_alt,
      title: _localized(context, 'No tasks', '暂无任务'),
      message: _localized(
        context,
        'Create an agent-side task to manage its schedule and runs.',
        '新建一个 agent 侧任务后，可以在这里管理计划和执行记录。',
      ),
    );
  }
}

class _StatePanel extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _StatePanel({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return EmptyStatePanel(icon: icon, title: title, message: message);
  }
}

Color _statusColor(ColorScheme colorScheme, ManagedTask task) {
  if (!task.enabled) return colorScheme.outline;
  if (_isTaskError(task)) return colorScheme.error;
  if (task.status == 'paused' || task.status == 'disabled') {
    return colorScheme.outline;
  }
  if (_isTaskRunning(task)) return colorScheme.tertiary;
  return colorScheme.primary;
}

Color _taskAccentColor(ColorScheme colorScheme, ManagedTask task) {
  if (_isTaskError(task)) return colorScheme.error;
  if (_isTaskRunning(task)) return colorScheme.tertiary;
  if (!task.enabled || task.status == 'paused' || task.status == 'disabled') {
    return colorScheme.outline;
  }
  return colorScheme.primary;
}

IconData _taskIcon(ManagedTask task) {
  if (_isTaskError(task)) return Icons.priority_high;
  if (_isTaskRunning(task)) return Icons.play_arrow;
  if (!task.enabled || task.status == 'paused' || task.status == 'disabled') {
    return Icons.pause;
  }
  return Icons.task_alt;
}

bool _isTaskRunning(ManagedTask task) {
  return task.status == 'running' || task.lastRun?.status == 'running';
}

bool _isTaskError(ManagedTask task) {
  return task.status == 'error' || task.lastRun?.status == 'failed';
}

Color _runColor(ColorScheme colorScheme, String status) {
  return switch (status) {
    'failed' => colorScheme.error,
    'cancelled' => colorScheme.outline,
    'running' => colorScheme.tertiary,
    _ => colorScheme.primary,
  };
}

String _statusLabel(BuildContext context, ManagedTask task) {
  if (!task.enabled) return _localized(context, 'Paused', '已暂停');
  return switch (task.status) {
    'error' => _localized(context, 'Error', '异常'),
    'running' => _localized(context, 'Running', '运行中'),
    'paused' || 'disabled' => _localized(context, 'Paused', '已暂停'),
    _ => switch (task.lastRun?.status) {
      'running' => _localized(context, 'Running', '运行中'),
      'failed' => _localized(context, 'Error', '异常'),
      _ => _localized(context, 'Active', '已启用'),
    },
  };
}

String _runStatusLabel(BuildContext context, String status) {
  return switch (status) {
    'running' => _localized(context, 'Running', '运行中'),
    'failed' => _localized(context, 'Failed', '失败'),
    'cancelled' => _localized(context, 'Cancelled', '已取消'),
    _ => _localized(context, 'Success', '成功'),
  };
}

String _localized(BuildContext context, String en, String zh) {
  return Localizations.localeOf(context).languageCode == 'zh' ? zh : en;
}
