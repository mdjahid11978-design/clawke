import 'package:client/providers/locale_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('defaults to Chinese when no locale is saved', () async {
    SharedPreferences.setMockInitialValues({});

    final notifier = LocaleNotifier();
    await Future<void>.delayed(Duration.zero);

    expect(notifier.state?.languageCode, 'zh');
  });

  test('uses saved locale when present', () async {
    SharedPreferences.setMockInitialValues({'clawke_locale': 'en'});

    final notifier = LocaleNotifier();
    await Future<void>.delayed(Duration.zero);

    expect(notifier.state?.languageCode, 'en');
  });
}
