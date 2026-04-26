import 'package:client/models/gateway_info.dart';
import 'package:client/widgets/gateway_selector_pane.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const hermes = GatewayInfo(
    gatewayId: 'hermes',
    displayName: 'Hermes',
    gatewayType: 'hermes',
    status: GatewayConnectionStatus.online,
    capabilities: ['tasks'],
  );
  const openclaw = GatewayInfo(
    gatewayId: 'openclaw',
    displayName: 'OpenClaw',
    gatewayType: 'openclaw',
    status: GatewayConnectionStatus.online,
    capabilities: ['tasks'],
  );

  testWidgets('keeps unavailable gateways visible and selects disconnected gateways', (
    tester,
  ) async {
    final selected = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GatewaySelectorPane(
            gateways: const [
              GatewayInfo(
                gatewayId: 'hermes',
                displayName: 'Hermes',
                gatewayType: 'hermes',
                status: GatewayConnectionStatus.online,
                capabilities: ['tasks'],
              ),
              GatewayInfo(
                gatewayId: 'skills-only',
                displayName: 'Skills',
                gatewayType: 'hermes',
                status: GatewayConnectionStatus.online,
                capabilities: ['skills'],
              ),
              GatewayInfo(
                gatewayId: 'offline',
                displayName: 'Offline',
                gatewayType: 'hermes',
                status: GatewayConnectionStatus.disconnected,
                capabilities: ['tasks'],
              ),
            ],
            selectedGatewayId: 'hermes',
            capability: 'tasks',
            onSelected: selected.add,
            onRename: (_, __) async {},
          ),
        ),
      ),
    );

    expect(find.text('Hermes'), findsOneWidget);
    expect(find.text('Skills'), findsOneWidget);
    expect(find.text('Offline'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('gateway_issue_skills-only')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('gateway_issue_offline')), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsNWidgets(2));

    await tester.tap(find.text('Skills'));
    await tester.pumpAndSettle();

    expect(selected, isEmpty);
    await tester.tap(find.text('Offline'));
    await tester.pumpAndSettle();

    expect(selected, ['offline']);
    expect(find.text('Gateway 未连接，无法显示相关信息。'), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('mobile selector keeps unavailable gateways visible', (
    tester,
  ) async {
    final selected = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GatewayMobileSelectorButton(
            gateways: const [
              hermes,
              openclaw,
              GatewayInfo(
                gatewayId: 'offline',
                displayName: 'Offline',
                gatewayType: 'hermes',
                status: GatewayConnectionStatus.disconnected,
                capabilities: ['tasks'],
              ),
              GatewayInfo(
                gatewayId: 'skills-only',
                displayName: 'Skills',
                gatewayType: 'hermes',
                status: GatewayConnectionStatus.online,
                capabilities: ['skills'],
              ),
            ],
            selectedGatewayId: 'hermes',
            capability: 'tasks',
            onSelected: selected.add,
          ),
        ),
      ),
    );

    expect(find.widgetWithText(OutlinedButton, 'Hermes'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Hermes'));
    await tester.pumpAndSettle();
    expect(find.text('Skills'), findsOneWidget);

    await tester.tap(find.text('Skills').last);
    await tester.pumpAndSettle();

    expect(selected, isEmpty);
    expect(find.text('当前 Gateway 不支持此页面功能。'), findsNothing);
    expect(find.byType(SnackBar), findsNothing);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Hermes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Offline').last);
    await tester.pumpAndSettle();

    expect(selected, ['offline']);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Hermes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OpenClaw').last);
    await tester.pumpAndSettle();

    expect(selected, ['offline', 'openclaw']);
  });

  testWidgets('desktop selector opens rename menu', (tester) async {
    final renamed = <String, String>{};
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GatewaySelectorPane(
            gateways: const [hermes],
            selectedGatewayId: 'hermes',
            capability: 'tasks',
            onSelected: (_) {},
            onRename: (gatewayId, displayName) async {
              renamed[gatewayId] = displayName;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Hermes'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('重命名'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Personal Hermes');
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();

    expect(renamed, {'hermes': 'Personal Hermes'});
  });

  testWidgets('desktop selector resizes by dragging right edge', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              GatewaySelectorPane(
                gateways: const [hermes],
                selectedGatewayId: 'hermes',
                capability: 'tasks',
                onSelected: (_) {},
                onRename: (_, __) async {},
              ),
              const Expanded(child: SizedBox()),
            ],
          ),
        ),
      ),
    );

    final pane = find.byKey(const ValueKey('gateway_selector_pane'));
    final handle = find.byKey(const ValueKey('gateway_selector_resize_handle'));

    expect(tester.getSize(pane).width, 260);
    expect(handle, findsOneWidget);

    await tester.drag(handle, const Offset(80, 0));
    await tester.pumpAndSettle();

    expect(tester.getSize(pane).width, 340);
  });
}
