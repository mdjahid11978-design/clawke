import 'package:client/widgets/notification_permission_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('intro dialog returns true when enabling notifications', (
    tester,
  ) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showDialog<bool>(
                context: context,
                builder: (_) => const NotificationPermissionIntroDialog(),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开启通知'));
    await tester.pumpAndSettle();

    expect(result, isTrue);
  });

  testWidgets('intro dialog returns false when postponed', (tester) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showDialog<bool>(
                context: context,
                builder: (_) => const NotificationPermissionIntroDialog(),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('稍后'));
    await tester.pumpAndSettle();

    expect(result, isFalse);
  });

  testWidgets('settings guide opens system settings from action', (
    tester,
  ) async {
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () {
              showDialog<void>(
                context: context,
                builder: (_) => NotificationPermissionSettingsGuideDialog(
                  onOpenSettings: () => opened = true,
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开系统设置'));
    await tester.pumpAndSettle();

    expect(opened, isTrue);
    expect(find.text('需要开启系统通知'), findsNothing);
  });
}
