import 'package:client/models/gateway_info.dart';
import 'package:flutter/material.dart';

class GatewayUnavailablePanel extends StatelessWidget {
  final String title;
  final String message;
  final String footnote;

  const GatewayUnavailablePanel({
    super.key,
    required this.title,
    required this.message,
    required this.footnote,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _DisconnectedMark(color: colorScheme.primary),
              const SizedBox(height: 22),
              Text(
                title,
                textAlign: TextAlign.center,
                style: textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                message,
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                footnote,
                textAlign: TextAlign.center,
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.72),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DisconnectedMark extends StatelessWidget {
  final Color color;

  const _DisconnectedMark({required this.color});

  @override
  Widget build(BuildContext context) {
    final faded = color.withValues(alpha: 0.26);
    return SizedBox(
      width: 108,
      height: 58,
      child: CustomPaint(painter: _DisconnectedMarkPainter(color, faded)),
    );
  }
}

class _DisconnectedMarkPainter extends CustomPainter {
  final Color color;
  final Color faded;

  const _DisconnectedMarkPainter(this.color, this.faded);

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = faded
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final active = Paint()..color = color;
    final muted = Paint()..color = faded;
    final cut = Paint()
      ..color = color
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    final left = Offset(size.width * 0.22, size.height * 0.55);
    final center = Offset(size.width * 0.50, size.height * 0.32);
    final right = Offset(size.width * 0.78, size.height * 0.55);
    canvas.drawLine(left, center, line);
    canvas.drawLine(center, right, line);
    canvas.drawCircle(left, 8, active);
    canvas.drawCircle(center, 10, muted);
    canvas.drawCircle(right, 8, muted);
    canvas.drawLine(
      Offset(size.width * 0.39, size.height * 0.76),
      Offset(size.width * 0.61, size.height * 0.54),
      cut,
    );
  }

  @override
  bool shouldRepaint(covariant _DisconnectedMarkPainter oldDelegate) {
    return color != oldDelegate.color || faded != oldDelegate.faded;
  }
}

bool gatewayUnavailableFor(GatewayInfo gateway, String capability) {
  return gateway.status != GatewayConnectionStatus.online ||
      !gateway.supports(capability);
}

List<GatewayInfo> orderGatewaysForSelection(
  List<GatewayInfo> gateways,
  String capability, {
  String? currentGatewayId,
}) {
  final capable = gateways
      .where((gateway) => gateway.supports(capability))
      .toList();
  capable.sort((a, b) {
    if (a.gatewayId == currentGatewayId) return -1;
    if (b.gatewayId == currentGatewayId) return 1;
    final aOnline = a.status == GatewayConnectionStatus.online;
    final bOnline = b.status == GatewayConnectionStatus.online;
    if (aOnline != bOnline) return aOnline ? -1 : 1;
    return a.displayName.compareTo(b.displayName);
  });
  return capable;
}

GatewayInfo? gatewayForSelection(
  List<GatewayInfo> gateways,
  String capability, {
  String? currentGatewayId,
}) {
  final ordered = orderGatewaysForSelection(
    gateways,
    capability,
    currentGatewayId: currentGatewayId,
  );
  return ordered.isEmpty ? null : ordered.first;
}

GatewayInfo? gatewayById(List<GatewayInfo> gateways, String? gatewayId) {
  if (gatewayId == null) return null;
  for (final gateway in gateways) {
    if (gateway.gatewayId == gatewayId) return gateway;
  }
  return null;
}

String gatewayUnavailableTitle(
  BuildContext context,
  GatewayInfo gateway, {
  required String capability,
  required String capabilityNameZh,
  required String capabilityNameEn,
}) {
  final name = gatewayDisplayName(gateway);
  if (!gateway.supports(capability)) {
    return _isZh(context)
        ? '$name Gateway 不支持$capabilityNameZh'
        : '$name Gateway does not support $capabilityNameEn';
  }
  return _isZh(context) ? '$name Gateway 未连接' : '$name Gateway disconnected';
}

String gatewayUnavailableStateMessage(
  BuildContext context,
  GatewayInfo gateway,
) {
  final detail = gateway.lastErrorMessage?.trim();
  if (detail != null && detail.isNotEmpty) return detail;
  return _isZh(context)
      ? 'Gateway 未连接，无法显示相关信息。'
      : 'Gateway disconnected. Related information is unavailable.';
}

String gatewayDisplayName(GatewayInfo gateway) {
  return switch (gateway.gatewayType.toLowerCase()) {
    'openclaw' => 'OpenClaw',
    'hermes' => 'Hermes',
    _ => gateway.displayName,
  };
}

double gatewayUnavailablePanelHeight(BuildContext context, bool compact) {
  final height = MediaQuery.sizeOf(context).height;
  final target = height * (compact ? 0.46 : 0.52);
  return target.clamp(320.0, 560.0);
}

bool _isZh(BuildContext context) {
  return Localizations.localeOf(context).languageCode == 'zh';
}
