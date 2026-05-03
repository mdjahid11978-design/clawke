import 'package:client/core/push_registration_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('registerWithServer posts APNs token and stable device id', () async {
    final posts = <Map<String, dynamic>>[];
    final service = PushRegistrationService(
      tokenProvider: () async => const PushDeviceToken(
        token: 'apns-token',
        platform: PushPlatform.ios,
      ),
      deviceIdProvider: () async => 'device-1',
      postDevice: (payload) async {
        posts.add(payload);
        return true;
      },
    );

    final ok = await service.registerWithServer(appVersion: '1.0.0');

    expect(ok, isTrue);
    expect(posts, hasLength(1));
    expect(posts.single, {
      'device_id': 'device-1',
      'platform': 'ios',
      'push_provider': 'apns',
      'device_token': 'apns-token',
      'app_version': '1.0.0',
    });
  });

  test('registerWithServer posts macOS APNs platform', () async {
    final posts = <Map<String, dynamic>>[];
    final service = PushRegistrationService(
      tokenProvider: () async => const PushDeviceToken(
        token: 'macos-token',
        platform: PushPlatform.macos,
      ),
      deviceIdProvider: () async => 'device-mac',
      postDevice: (payload) async {
        posts.add(payload);
        return true;
      },
    );

    final ok = await service.registerWithServer(appVersion: '1.0.0');

    expect(ok, isTrue);
    expect(posts.single, {
      'device_id': 'device-mac',
      'platform': 'macos',
      'push_provider': 'apns',
      'device_token': 'macos-token',
      'app_version': '1.0.0',
    });
  });

  test('registerWithServer no-ops when native token is unavailable', () async {
    var posted = false;
    final service = PushRegistrationService(
      tokenProvider: () async => null,
      deviceIdProvider: () async => 'device-1',
      postDevice: (_) async {
        posted = true;
        return true;
      },
    );

    final ok = await service.registerWithServer(appVersion: '1.0.0');

    expect(ok, isFalse);
    expect(posted, isFalse);
  });

  test('RemotePushPayload parses routing fields', () {
    final payload = RemotePushPayload.fromMap({
      'conversation_id': 'conv_1',
      'message_id': 'msg_1',
      'gateway_id': 'hermes',
      'seq': '42',
      'event_type': 'delivery',
    });

    expect(payload?.conversationId, 'conv_1');
    expect(payload?.messageId, 'msg_1');
    expect(payload?.gatewayId, 'hermes');
    expect(payload?.seq, 42);
    expect(payload?.isNotificationTap, isFalse);
    expect(payload?.toNotificationTapPayload(), isNull);
  });

  test('RemotePushPayload opens only for notification tap events', () {
    final payload = RemotePushPayload.fromMap({
      'conversation_id': 'conv_1',
      'message_id': 'msg_1',
      'gateway_id': 'hermes',
      'seq': 42,
      'event_type': 'notification_tap',
    });

    final tapPayload = payload?.toNotificationTapPayload();

    expect(payload?.isNotificationTap, isTrue);
    expect(tapPayload?.conversationId, 'conv_1');
    expect(tapPayload?.messageId, 'msg_1');
    expect(tapPayload?.gatewayId, 'hermes');
    expect(tapPayload?.seq, 42);
    expect(tapPayload?.source.name, 'remotePush');
  });

  test('configureRemotePushHandling drains pending native payloads', () async {
    const channel = MethodChannel('clawke/push');
    final seen = <RemotePushPayload>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'takeRemotePushPayloads') {
            return [
              {
                'conversation_id': 'conv_1',
                'message_id': 'msg_1',
                'gateway_id': 'hermes',
                'seq': 7,
              },
            ];
          }
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    await PushRegistrationService.configureRemotePushHandling(seen.add);

    expect(seen, hasLength(1));
    expect(seen.single.conversationId, 'conv_1');
    expect(seen.single.seq, 7);
  });
}
