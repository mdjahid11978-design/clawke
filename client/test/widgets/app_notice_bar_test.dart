import 'package:client/widgets/app_notice_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('error constructor creates error notice', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppNoticeBar.error(
            message: '服务器已断开',
            detail: '请确认 Clawke Server 已启动并完成授权',
            onDismiss: () {},
          ),
        ),
      ),
    );

    final notice = tester.widget<AppNoticeBar>(find.byType(AppNoticeBar));
    expect(notice.severity, AppNoticeSeverity.error);
    expect(find.text('服务器已断开'), findsOneWidget);
    expect(find.text('请确认 Clawke Server 已启动并完成授权'), findsOneWidget);
  });

  testWidgets('error notice uses muted surface blended color', (tester) async {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF10B981),
      brightness: Brightness.dark,
      error: const Color(0xFFF87171),
      errorContainer: const Color(0xFFBA000D),
      surfaceContainerHighest: const Color(0xFF3A3A3A),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorScheme: scheme),
        home: Scaffold(
          body: AppNoticeBar(
            message: '当前网关未连接：Hermes',
            severity: AppNoticeSeverity.error,
            onDismiss: () {},
          ),
        ),
      ),
    );

    final material = tester.widget<Material>(
      find.byKey(const ValueKey('app_notice_bar')),
    );
    final expectedBackground = Color.alphaBlend(
      scheme.error.withValues(alpha: 0.18),
      scheme.surfaceContainerHighest,
    );

    expect(material.color, isNot(scheme.errorContainer));
    expect(material.color, expectedBackground);
  });
}
