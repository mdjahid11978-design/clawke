import 'package:flutter/material.dart';

class NotificationPermissionIntroDialog extends StatelessWidget {
  const NotificationPermissionIntroDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('开启系统通知'),
      content: const Text('Clawke 可以在收到新消息时显示系统通知，并同步未读提醒。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('稍后'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('开启通知'),
        ),
      ],
    );
  }
}

class NotificationPermissionSettingsGuideDialog extends StatelessWidget {
  final VoidCallback onOpenSettings;

  const NotificationPermissionSettingsGuideDialog({
    super.key,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('需要开启系统通知'),
      content: const Text('请在系统设置 > 通知 > Clawke 中打开“允许通知”。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('稍后'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop();
            onOpenSettings();
          },
          child: const Text('打开系统设置'),
        ),
      ],
    );
  }
}
