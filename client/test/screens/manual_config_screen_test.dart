import 'package:client/l10n/app_localizations.dart';
import 'package:client/screens/manual_config_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _buildManualConfigScreen() {
  return const ProviderScope(
    child: MaterialApp(
      locale: Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ManualConfigScreen(),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ManualConfigScreen', () {
    testWidgets('keeps server address empty when no saved config exists', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(_buildManualConfigScreen());
      await tester.pumpAndSettle();

      final urlField = tester.widget<TextField>(find.byType(TextField).first);
      expect(urlField.controller?.text, isEmpty);
    });

    testWidgets('does not write default address into empty field on connect', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(_buildManualConfigScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.link));
      await tester.pump();

      final urlField = tester.widget<TextField>(find.byType(TextField).first);
      expect(urlField.controller?.text, isEmpty);

      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
    });

    testWidgets('prefills saved server address and token', (tester) async {
      SharedPreferences.setMockInitialValues({
        'clawke_http_url': 'https://relay.example.com',
        'clawke_ws_url': 'wss://relay.example.com/ws',
        'clawke_token': 'saved-token',
      });

      await tester.pumpWidget(_buildManualConfigScreen());
      await tester.pumpAndSettle();

      final fields = find.byType(TextField);
      final urlField = tester.widget<TextField>(fields.first);
      final tokenField = tester.widget<TextField>(fields.at(1));
      expect(urlField.controller?.text, 'https://relay.example.com');
      expect(tokenField.controller?.text, 'saved-token');
    });
  });
}
