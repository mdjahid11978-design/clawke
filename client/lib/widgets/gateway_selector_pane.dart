import 'dart:async';

import 'package:client/models/gateway_info.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kGatewayPaneWidthKey = 'clawke_gateway_selector_width';
const _kDefaultGatewayPaneWidth = 260.0;
const _kMinGatewayPaneWidth = 180.0;
const _kMaxGatewayPaneWidth = 500.0;

class GatewaySelectorPane extends StatefulWidget {
  final List<GatewayInfo> gateways;
  final String? selectedGatewayId;
  final String capability;
  final ValueChanged<String> onSelected;
  final Future<void> Function(String gatewayId, String displayName) onRename;
  final String? errorGatewayId;
  final String issueKeyPrefix;

  const GatewaySelectorPane({
    super.key,
    required this.gateways,
    required this.selectedGatewayId,
    required this.capability,
    required this.onSelected,
    required this.onRename,
    this.errorGatewayId,
    this.issueKeyPrefix = 'gateway_issue',
  });

  @override
  State<GatewaySelectorPane> createState() => _GatewaySelectorPaneState();
}

class _GatewaySelectorPaneState extends State<GatewaySelectorPane> {
  double _width = _kDefaultGatewayPaneWidth;

  @override
  void initState() {
    super.initState();
    unawaited(_loadWidth());
  }

  Future<void> _loadWidth() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getDouble(_kGatewayPaneWidthKey);
    if (saved != null && mounted) {
      setState(
        () =>
            _width = saved.clamp(_kMinGatewayPaneWidth, _kMaxGatewayPaneWidth),
      );
    }
  }

  Future<void> _saveWidth() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kGatewayPaneWidthKey, _width);
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleGateways(widget.gateways);
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      key: const ValueKey('gateway_selector_pane'),
      width: _width,
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLowest,
              border: Border(
                right: BorderSide(color: colorScheme.outlineVariant),
              ),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Gateway 列表',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                if (visible.isEmpty)
                  Text(
                    '暂无 Gateway',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  )
                else
                  for (final gateway in visible)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _GatewayTile(
                        gateway: gateway,
                        selected: gateway.gatewayId == widget.selectedGatewayId,
                        hasIssue: _hasGatewayIssue(
                          gateway,
                          widget.capability,
                          widget.errorGatewayId,
                        ),
                        canSelect: _canSelectGateway(
                          gateway,
                          widget.capability,
                        ),
                        unavailableMessage: _gatewayIssueMessage(
                          gateway,
                          widget.capability,
                        ),
                        issueKeyPrefix: widget.issueKeyPrefix,
                        onSelected: widget.onSelected,
                        onRename: widget.onRename,
                      ),
                    ),
              ],
            ),
          ),
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeColumn,
              child: GestureDetector(
                key: const ValueKey('gateway_selector_resize_handle'),
                behavior: HitTestBehavior.opaque,
                onHorizontalDragUpdate: (details) {
                  setState(() {
                    _width = (_width + details.delta.dx).clamp(
                      _kMinGatewayPaneWidth,
                      _kMaxGatewayPaneWidth,
                    );
                  });
                },
                onHorizontalDragEnd: (_) => unawaited(_saveWidth()),
                child: const SizedBox(width: 5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class GatewayMobileSelectorButton extends StatelessWidget {
  final List<GatewayInfo> gateways;
  final String? selectedGatewayId;
  final String capability;
  final ValueChanged<String> onSelected;
  final String? errorGatewayId;
  final String issueKeyPrefix;

  const GatewayMobileSelectorButton({
    super.key,
    required this.gateways,
    required this.selectedGatewayId,
    required this.capability,
    required this.onSelected,
    this.errorGatewayId,
    this.issueKeyPrefix = 'gateway_issue',
  });

  @override
  Widget build(BuildContext context) {
    final visible = _visibleGateways(gateways);
    if (visible.isEmpty) return const SizedBox.shrink();
    final selected = _selectedGateway(visible, selectedGatewayId);
    final hasIssue =
        selected != null &&
        _hasGatewayIssue(selected, capability, errorGatewayId);
    final label = selected?.displayName ?? 'Gateway';
    final colorScheme = Theme.of(context).colorScheme;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _showSheet(context, visible),
            icon: const Icon(Icons.hub_outlined),
            label: Row(
              children: [
                Text(
                  'Gateway',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const Icon(Icons.expand_more, size: 18),
              ],
            ),
          ),
        ),
        if (hasIssue)
          Positioned(
            right: -6,
            bottom: -4,
            child: Tooltip(
              message: _gatewayIssueMessage(selected, capability),
              child: Icon(
                key: ValueKey('${issueKeyPrefix}_${selected.gatewayId}'),
                Icons.warning_amber_rounded,
                size: 18,
                color: colorScheme.error,
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _showSheet(
    BuildContext context,
    List<GatewayInfo> gateways,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                '切换 Gateway',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            for (final gateway in gateways)
              ListTile(
                leading: const Icon(Icons.hub_outlined),
                title: Text(gateway.displayName),
                subtitle: _showsGatewayId(gateway)
                    ? Text(gateway.gatewayId)
                    : null,
                trailing: gateway.gatewayId == selectedGatewayId
                    ? const Icon(Icons.check)
                    : null,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  if (_canSelectGateway(gateway, capability)) {
                    onSelected(gateway.gatewayId);
                  }
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _GatewayTile extends StatelessWidget {
  final GatewayInfo gateway;
  final bool selected;
  final bool hasIssue;
  final bool canSelect;
  final String unavailableMessage;
  final String issueKeyPrefix;
  final ValueChanged<String> onSelected;
  final Future<void> Function(String gatewayId, String displayName) onRename;

  const _GatewayTile({
    required this.gateway,
    required this.selected,
    required this.hasIssue,
    required this.canSelect,
    required this.unavailableMessage,
    required this.issueKeyPrefix,
    required this.onSelected,
    required this.onRename,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onSecondaryTapUp: (details) => _showMenu(context, details.globalPosition),
      onLongPressStart: (details) => _showMenu(context, details.globalPosition),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Material(
            color: selected
                ? colorScheme.primaryContainer
                : colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              onTap: () {
                if (canSelect) {
                  onSelected(gateway.gatewayId);
                }
              },
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(
                      Icons.hub_outlined,
                      color: selected
                          ? colorScheme.onPrimaryContainer
                          : colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            gateway.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: selected
                                      ? colorScheme.onPrimaryContainer
                                      : colorScheme.onSurface,
                                ),
                          ),
                          if (_showsGatewayId(gateway)) ...[
                            const SizedBox(height: 3),
                            Text(
                              gateway.gatewayId,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: selected
                                        ? colorScheme.onPrimaryContainer
                                        : colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (hasIssue)
            Positioned(
              right: 8,
              bottom: 8,
              child: Tooltip(
                message: unavailableMessage,
                child: Icon(
                  key: ValueKey('${issueKeyPrefix}_${gateway.gatewayId}'),
                  Icons.warning_amber_rounded,
                  size: 18,
                  color: colorScheme.error,
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showMenu(BuildContext context, Offset position) {
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: const [PopupMenuItem(value: 'rename', child: Text('重命名'))],
    ).then((value) {
      if (value == 'rename' && context.mounted) {
        _showRename(context);
      }
    });
  }

  void _showRename(BuildContext context) {
    final controller = TextEditingController(text: gateway.displayName);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名 Gateway'),
        content: TextField(
          controller: controller,
          autofocus: true,
          onSubmitted: (_) => _submitRename(ctx, controller),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => _submitRename(ctx, controller),
            child: const Text('确认'),
          ),
        ],
      ),
    );
  }

  void _submitRename(BuildContext ctx, TextEditingController controller) {
    final value = controller.text.trim();
    if (value.isEmpty) return;
    unawaited(onRename(gateway.gatewayId, value));
    Navigator.of(ctx).pop();
  }
}

List<GatewayInfo> _visibleGateways(List<GatewayInfo> gateways) => gateways;

bool _hasGatewayIssue(
  GatewayInfo gateway,
  String capability,
  String? errorGatewayId,
) {
  return gateway.gatewayId == errorGatewayId ||
      gateway.status != GatewayConnectionStatus.online ||
      !gateway.supports(capability);
}

bool _canSelectGateway(GatewayInfo gateway, String capability) {
  return gateway.supports(capability);
}

String _gatewayIssueMessage(GatewayInfo gateway, String capability) {
  if (gateway.status != GatewayConnectionStatus.online) {
    final detail = gateway.lastErrorMessage?.trim();
    if (gateway.status == GatewayConnectionStatus.error &&
        detail != null &&
        detail.isNotEmpty) {
      return detail;
    }
    return 'Gateway 未连接，无法显示相关信息。';
  }
  if (!gateway.supports(capability)) {
    return '当前 Gateway 不支持此页面功能。';
  }
  return 'Gateway 异常，无法显示相关信息。';
}

GatewayInfo? _selectedGateway(List<GatewayInfo> gateways, String? selectedId) {
  if (selectedId != null) {
    for (final gateway in gateways) {
      if (gateway.gatewayId == selectedId) return gateway;
    }
  }
  return gateways.firstOrNull;
}

bool _showsGatewayId(GatewayInfo gateway) {
  return gateway.gatewayId != gateway.displayName;
}
