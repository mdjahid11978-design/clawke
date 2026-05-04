import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'package:client/core/notification_event.dart';
import 'package:client/services/media_resolver.dart';

const _kPushDeviceIdKey = 'clawke_push_device_id';

enum PushPlatform { ios, macos }

enum RemotePushEventType { delivery, notificationTap }

extension PushPlatformWire on PushPlatform {
  String get wireName => switch (this) {
    PushPlatform.ios => 'ios',
    PushPlatform.macos => 'macos',
  };
}

class PushDeviceToken {
  final String token;
  final PushPlatform platform;

  const PushDeviceToken({required this.token, required this.platform});
}

typedef PushTokenProvider = Future<PushDeviceToken?> Function();
typedef PushDeviceIdProvider = Future<String> Function();
typedef PushDevicePoster = Future<bool> Function(Map<String, dynamic> payload);
typedef RemotePushHandler = FutureOr<void> Function(RemotePushPayload payload);

class RemotePushPayload {
  final String conversationId;
  final String messageId;
  final String gatewayId;
  final int seq;
  final RemotePushEventType eventType;

  const RemotePushPayload({
    required this.conversationId,
    required this.messageId,
    required this.gatewayId,
    required this.seq,
    required this.eventType,
  });

  bool get isNotificationTap =>
      eventType == RemotePushEventType.notificationTap;

  NotificationPayload? toNotificationTapPayload() {
    if (!isNotificationTap) return null;
    return NotificationPayload(
      conversationId: conversationId,
      messageId: messageId,
      gatewayId: gatewayId,
      seq: seq,
      source: NotificationEventSource.remotePush,
    );
  }

  static RemotePushPayload? fromMap(Map<dynamic, dynamic>? map) {
    if (map == null) return null;
    final conversationId = map['conversation_id']?.toString() ?? '';
    final messageId = map['message_id']?.toString() ?? '';
    final gatewayId = map['gateway_id']?.toString() ?? '';
    final rawSeq = map['seq'];
    final seq = rawSeq is num ? rawSeq.toInt() : int.tryParse('$rawSeq') ?? 0;
    if (conversationId.isEmpty || messageId.isEmpty || gatewayId.isEmpty) {
      return null;
    }
    return RemotePushPayload(
      conversationId: conversationId,
      messageId: messageId,
      gatewayId: gatewayId,
      seq: seq,
      eventType: _parseEventType(map['event_type']),
    );
  }

  static RemotePushEventType _parseEventType(dynamic raw) {
    return switch (raw?.toString()) {
      'notification_tap' => RemotePushEventType.notificationTap,
      _ => RemotePushEventType.delivery,
    };
  }
}

class PushRegistrationService {
  static const _channel = MethodChannel('clawke/push');
  static RemotePushHandler? _remotePushHandler;
  static bool _remotePushConfigured = false;

  final PushTokenProvider _tokenProvider;
  final PushDeviceIdProvider _deviceIdProvider;
  final PushDevicePoster _postDevice;

  PushRegistrationService({
    PushTokenProvider? tokenProvider,
    PushDeviceIdProvider? deviceIdProvider,
    PushDevicePoster? postDevice,
  }) : _tokenProvider = tokenProvider ?? requestNativeToken,
       _deviceIdProvider = deviceIdProvider ?? _readStableDeviceId,
       _postDevice = postDevice ?? _postDeviceToServer;

  static Future<bool> registerCurrentDeviceWithServer({
    String appVersion = 'unknown',
  }) {
    return PushRegistrationService().registerWithServer(appVersion: appVersion);
  }

  static Future<void> configureRemotePushHandling(
    RemotePushHandler? handler,
  ) async {
    _remotePushHandler = handler;
    if (!_remotePushConfigured) {
      _channel.setMethodCallHandler((call) async {
        if (call.method != 'remotePushReceived') return null;
        await _dispatchRemotePush(call.arguments);
        return null;
      });
      _remotePushConfigured = true;
    }

    try {
      final pending = await _channel.invokeListMethod<dynamic>(
        'takeRemotePushPayloads',
      );
      for (final item in pending ?? const []) {
        await _dispatchRemotePush(item);
      }
    } on MissingPluginException {
      return;
    } on PlatformException catch (e) {
      debugPrint('[PushRegistration] take remote push failed: ${e.message}');
    }
  }

  static Future<bool> disableCurrentDeviceOnServer() async {
    final prefs = await SharedPreferences.getInstance();
    final deviceId = prefs.getString(_kPushDeviceIdKey);
    if (deviceId == null || deviceId.isEmpty) return false;
    try {
      final dio = Dio(
        BaseOptions(
          baseUrl: MediaResolver.baseUrl,
          headers: MediaResolver.authHeaders,
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
        ),
      );
      final response = await dio.delete('/api/push/devices/$deviceId');
      return (response.statusCode ?? 0) >= 200 &&
          (response.statusCode ?? 0) < 300;
    } catch (e) {
      debugPrint('[PushRegistration] APNs device disable failed: $e');
      return false;
    }
  }

  Future<bool> registerWithServer({String appVersion = 'unknown'}) async {
    debugPrint('[PushRegistration] APNs device register requested');
    final token = await _tokenProvider();
    if (token == null || token.token.isEmpty) {
      debugPrint('[PushRegistration] APNs token unavailable');
      return false;
    }
    final deviceId = await _deviceIdProvider();
    final payload = <String, dynamic>{
      'device_id': deviceId,
      'platform': token.platform.wireName,
      'push_provider': 'apns',
      'device_token': token.token,
      'app_version': appVersion,
    };
    debugPrint(
      '[PushRegistration] APNs token received: '
      'platform=${token.platform.wireName}, token_len=${token.token.length}',
    );
    return _postDevice(payload);
  }

  static Future<PushDeviceToken?> requestNativeToken() async {
    if (!Platform.isIOS && !Platform.isMacOS) return null;
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'registerForRemoteNotifications',
      );
      final token = result?['token'] as String? ?? '';
      if (token.isEmpty) return null;
      final platform = switch (result?['platform'] as String?) {
        'macos' => PushPlatform.macos,
        _ => PushPlatform.ios,
      };
      return PushDeviceToken(token: token, platform: platform);
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      debugPrint('[PushRegistration] APNs token failed: ${e.message}');
      return null;
    }
  }

  static Future<void> _dispatchRemotePush(dynamic raw) async {
    if (raw is! Map<dynamic, dynamic>) return;
    final payload = RemotePushPayload.fromMap(raw);
    if (payload == null) return;
    final handler = _remotePushHandler;
    if (handler == null) return;
    await handler(payload);
  }

  static Future<String> _readStableDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_kPushDeviceIdKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final id = const Uuid().v4();
    await prefs.setString(_kPushDeviceIdKey, id);
    return id;
  }

  static Future<bool> _postDeviceToServer(Map<String, dynamic> payload) async {
    try {
      final dio = Dio(
        BaseOptions(
          baseUrl: MediaResolver.baseUrl,
          headers: MediaResolver.authHeaders,
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
        ),
      );
      final response = await dio.post('/api/push/devices', data: payload);
      final ok =
          (response.statusCode ?? 0) >= 200 && (response.statusCode ?? 0) < 300;
      debugPrint(
        '[PushRegistration] APNs device register: $ok '
        'status=${response.statusCode}',
      );
      return ok;
    } catch (e) {
      debugPrint('[PushRegistration] APNs device register failed: $e');
      return false;
    }
  }
}
