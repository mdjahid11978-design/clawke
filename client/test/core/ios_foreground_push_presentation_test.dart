import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS foreground remote push updates badge without system alert', () {
    final appDelegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    final willPresentStart = appDelegate.indexOf('willPresent notification');
    final nextMethodStart = appDelegate.indexOf(
      'private func enqueueRemotePushPayload',
      willPresentStart,
    );

    expect(willPresentStart, greaterThanOrEqualTo(0));
    expect(nextMethodStart, greaterThan(willPresentStart));

    final willPresentBody = appDelegate.substring(
      willPresentStart,
      nextMethodStart,
    );

    expect(willPresentBody, contains('.badge'));
    expect(willPresentBody, isNot(contains('.banner')));
    expect(willPresentBody, isNot(contains('.alert')));
    expect(willPresentBody, isNot(contains('.sound')));
  });
}
