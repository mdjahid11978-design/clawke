import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('macOS AppDelegate captures notification launch response', () {
    final source = File('macos/Runner/AppDelegate.swift').readAsStringSync();

    expect(source, contains('NSApplication.launchUserNotificationUserInfoKey'));
    expect(source, contains('UNNotificationResponse'));
    expect(source, contains('enqueueLaunchNotificationPayload'));
    expect(source, contains('eventType: "notification_tap"'));
    expect(source, contains('eventType: "delivery"'));
  });

  test('macOS AppDelegate routes local notification payload taps', () {
    final source = File('macos/Runner/AppDelegate.swift').readAsStringSync();

    expect(source, contains('userInfo["payload"]'));
    expect(source, contains('JSONSerialization.jsonObject'));
    expect(source, contains('eventType == "notification_tap"'));
  });

  test('iOS AppDelegate captures remote notification launch options', () {
    final source = File('ios/Runner/AppDelegate.swift').readAsStringSync();

    expect(source, contains('enqueueLaunchRemotePushPayload'));
    expect(source, contains('.remoteNotification'));
    expect(source, contains('pendingRemotePushPayloads'));
    expect(source, contains('eventType: "notification_tap"'));
    expect(source, contains('eventType: "delivery"'));
  });

  test('macOS remote notifications are silent while iOS remains audible', () {
    final macSource = File('macos/Runner/AppDelegate.swift').readAsStringSync();
    final iosSource = File('ios/Runner/AppDelegate.swift').readAsStringSync();

    expect(macSource, isNot(contains('.sound')));
    expect(iosSource, contains('.sound'));
  });
}
