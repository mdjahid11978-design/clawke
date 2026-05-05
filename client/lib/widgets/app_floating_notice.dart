import 'package:flutter/material.dart';
import 'package:client/widgets/app_notice_bar.dart';

class AppFloatingNotice extends StatelessWidget {
  final String message;
  final String? detail;
  final AppNoticeSeverity severity;
  final VoidCallback onDismiss;
  final VoidCallback? onAction;
  final IconData? actionIcon;
  final String? actionTooltip;
  final bool showProgress;
  final bool edgeToEdge;
  final double bottom;
  final double horizontalInset;

  const AppFloatingNotice({
    super.key,
    required this.message,
    this.detail,
    required this.severity,
    required this.onDismiss,
    this.onAction,
    this.actionIcon,
    this.actionTooltip,
    this.showProgress = false,
    this.edgeToEdge = false,
    this.bottom = 16,
    this.horizontalInset = 16,
  });

  const AppFloatingNotice.info({
    super.key,
    required this.message,
    this.detail,
    required this.onDismiss,
    this.onAction,
    this.actionIcon,
    this.actionTooltip,
    this.showProgress = false,
    this.edgeToEdge = false,
    this.bottom = 16,
    this.horizontalInset = 16,
  }) : severity = AppNoticeSeverity.info;

  const AppFloatingNotice.warning({
    super.key,
    required this.message,
    this.detail,
    required this.onDismiss,
    this.onAction,
    this.actionIcon,
    this.actionTooltip,
    this.showProgress = false,
    this.edgeToEdge = false,
    this.bottom = 16,
    this.horizontalInset = 16,
  }) : severity = AppNoticeSeverity.warning;

  const AppFloatingNotice.error({
    super.key,
    required this.message,
    this.detail,
    required this.onDismiss,
    this.onAction,
    this.actionIcon,
    this.actionTooltip,
    this.showProgress = false,
    this.edgeToEdge = false,
    this.bottom = 16,
    this.horizontalInset = 16,
  }) : severity = AppNoticeSeverity.error;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: horizontalInset,
      right: horizontalInset,
      bottom: bottom,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: AppNoticeBar(
          message: message,
          detail: detail,
          severity: severity,
          onDismiss: onDismiss,
          onAction: onAction,
          actionIcon: actionIcon,
          actionTooltip: actionTooltip,
          showProgress: showProgress,
          edgeToEdge: edgeToEdge,
        ),
      ),
    );
  }
}
