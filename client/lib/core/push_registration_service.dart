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
const _kPushProviderKey = 'clawke_push_provider';

enum PushPlatform { ios, macos, android }

enum PushProvider { apns, fcm }

enum RemotePushEventType { delivery, notificationTap }

extension PushPlatformWire on PushPlatform {
  String get wireName => switch (this) {
    PushPlatform.ios => 'ios',
    PushPlatform.macos => 'macos',
    PushPlatform.android => 'android',
  };
}

extension PushProviderWire on PushProvider {
  String get wireName => switch (this) {
    PushProvider.apns => 'apns',
    PushProvider.fcm => 'fcm',
  };
}

class PushDeviceToken {
  final String token;
  final PushPlatform platform;
  final PushProvider pushProvider;

  const PushDeviceToken({
    required this.token,
    required this.platform,
    this.pushProvider = PushProvider.apns,
  });
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
  static Future<bool>? _registerInFlight;

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
    PushRegistrationService? service,
  }) {
    final existing = _registerInFlight;
    if (existing != null) {
      debugPrint(
        '[PushRegistration] remote push device register already in progress',
      );
      return existing;
    }
    final future = (service ?? PushRegistrationService())
        .registerWithServer(appVersion: appVersion)
        .whenComplete(() {
          _registerInFlight = null;
        });
    _registerInFlight = future;
    return future;
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
    final provider = prefs.getString(_kPushProviderKey) ?? 'apns';
    try {
      final dio = Dio(
        BaseOptions(
          baseUrl: MediaResolver.baseUrl,
          headers: MediaResolver.authHeaders,
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
        ),
      );
      final response = await dio.delete(
        '/api/push/devices/$deviceId',
        queryParameters: {'push_provider': provider},
      );
      return (response.statusCode ?? 0) >= 200 &&
          (response.statusCode ?? 0) < 300;
    } catch (e) {
      debugPrint('[PushRegistration] APNs device disable failed: $e');
      return false;
    }
  }

  Future<bool> registerWithServer({String appVersion = 'unknown'}) async {
    debugPrint('[PushRegistration] remote push device register requested');
    final token = await _tokenProvider();
    if (token == null || token.token.isEmpty) {
      debugPrint('[PushRegistration] remote push token unavailable');
      return false;
    }
    final deviceId = await _deviceIdProvider();
    final payload = buildRegisterDevicePayload(
      deviceId: deviceId,
      platform: token.platform,
      pushProvider: token.pushProvider,
      deviceToken: token.token,
      appVersion: appVersion,
    );
    debugPrint(
      '[PushRegistration] remote push token received: '
      'platform=${token.platform.wireName}, provider=${token.pushProvider.wireName}, token_len=${token.token.length}',
    );
    final ok = await _postDevice(payload);
    if (ok) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kPushProviderKey, token.pushProvider.wireName);
    }
    return ok;
  }

  static Future<PushDeviceToken?> requestNativeToken() async {
    if (!Platform.isIOS && !Platform.isMacOS && !Platform.isAndroid) {
      return null;
    }
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'registerForRemoteNotifications',
      );
      final token = result?['token'] as String? ?? '';
      if (token.isEmpty) return null;
      final platform = switch (result?['platform'] as String?) {
        'macos' => PushPlatform.macos,
        'android' => PushPlatform.android,
        _ => PushPlatform.ios,
      };
      final pushProvider = switch (result?['push_provider'] as String?) {
        'fcm' => PushProvider.fcm,
        _ => PushProvider.apns,
      };
      return PushDeviceToken(
        token: token,
        platform: platform,
        pushProvider: pushProvider,
      );
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
    final nativeId = await _readNativeStableDeviceId();
    if (nativeId != null) return nativeId;
    return _readSharedPreferencesStableDeviceId();
  }

  static Future<String?> _readNativeStableDeviceId() async {
    try {
      final id = await _channel.invokeMethod<String>('readStableDeviceId');
      final trimmed = id?.trim() ?? '';
      return trimmed.isEmpty ? null : trimmed;
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      debugPrint(
        '[PushRegistration] native stable device id failed: ${e.message}',
      );
      return null;
    }
  }

  static Future<String> _readSharedPreferencesStableDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_kPushDeviceIdKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final id = const Uuid().v4();
    await prefs.setString(_kPushDeviceIdKey, id);
    return id;
  }

  @visibleForTesting
  static Map<String, dynamic> buildRegisterDevicePayload({
    required String deviceId,
    required PushPlatform platform,
    required PushProvider pushProvider,
    required String deviceToken,
    required String appVersion,
  }) {
    return <String, dynamic>{
      'device_id': deviceId,
      'platform': platform.wireName,
      'push_provider': pushProvider.wireName,
      'device_token': deviceToken,
      'app_bundle_id': _appBundleId,
      'app_version': appVersion,
    };
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
        '[PushRegistration] remote push device register: $ok '
        'status=${response.statusCode}',
      );
      return ok;
    } catch (e) {
      debugPrint('[PushRegistration] remote push device register failed: $e');
      return false;
    }
  }

  static const String _appBundleId = 'ai.clawke.app';
}
