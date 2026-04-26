import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:client/providers/locale_provider.dart';

void main() {
  test('can inject non-persistent locale for ui e2e', () {
    final notifier = LocaleNotifier(
      initialLocale: const Locale('zh'),
      loadFromPrefs: false,
    );

    expect(notifier.state, const Locale('zh'));
  });
}
