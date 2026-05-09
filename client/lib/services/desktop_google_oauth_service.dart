import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

class DesktopGoogleAccount {
  const DesktopGoogleAccount({
    required this.id,
    required this.email,
    required this.idToken,
    required this.accessToken,
    this.displayName,
    this.photoUrl,
  });

  final String id;
  final String email;
  final String idToken;
  final String accessToken;
  final String? displayName;
  final String? photoUrl;
}

class DesktopGoogleOAuthService {
  DesktopGoogleOAuthService({
    required this.clientId,
    this.clientSecret = '',
    Dio? dio,
    Future<bool> Function(Uri, {LaunchMode mode})? launcher,
    String Function(int length)? randomString,
  }) : _dio = dio ?? Dio(),
       _launcher = launcher ?? launchUrl,
       _randomString = randomString ?? _secureRandomString;

  final String clientId;
  final String clientSecret;
  final Dio _dio;
  final Future<bool> Function(Uri, {LaunchMode mode}) _launcher;
  final String Function(int length) _randomString;

  static const _authorizationEndpoint =
      'https://accounts.google.com/o/oauth2/v2/auth';
  static const _tokenEndpoint = 'https://oauth2.googleapis.com/token';

  Future<DesktopGoogleAccount> signIn() async {
    if (clientId.trim().isEmpty) {
      throw const DesktopGoogleOAuthException(
        'Google Desktop OAuth client id 未配置',
      );
    }

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final redirectUri = 'http://127.0.0.1:${server.port}';
    final state = _randomString(32);
    final codeVerifier = _randomString(64);
    final codeChallenge = _base64UrlNoPadding(
      sha256.convert(utf8.encode(codeVerifier)).bytes,
    );

    try {
      final authUri = Uri.parse(_authorizationEndpoint).replace(
        queryParameters: {
          'client_id': clientId,
          'redirect_uri': redirectUri,
          'response_type': 'code',
          'scope': 'openid email profile',
          'state': state,
          'code_challenge': codeChallenge,
          'code_challenge_method': 'S256',
          'access_type': 'offline',
          'prompt': 'select_account',
        },
      );

      debugPrint('[Auth] Opening desktop Google OAuth: $authUri');
      final launched = await _launcher(
        authUri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        throw const DesktopGoogleOAuthException('无法打开系统浏览器');
      }

      final request = await server.first.timeout(
        const Duration(minutes: 5),
        onTimeout: () {
          throw const DesktopGoogleOAuthException('Google 登录超时');
        },
      );
      await _respondToBrowser(request);

      final params = request.uri.queryParameters;
      if (params['state'] != state) {
        throw const DesktopGoogleOAuthException('Google 登录状态校验失败');
      }
      if (params['error'] != null) {
        throw DesktopGoogleOAuthException('Google 登录失败：${params['error']}');
      }

      final code = params['code'];
      if (code == null || code.isEmpty) {
        throw const DesktopGoogleOAuthException('Google 未返回授权码');
      }

      final token = await _exchangeCode(
        code: code,
        redirectUri: redirectUri,
        codeVerifier: codeVerifier,
      );
      return _accountFromToken(token);
    } finally {
      await server.close(force: true);
    }
  }

  Future<Map<String, dynamic>> _exchangeCode({
    required String code,
    required String redirectUri,
    required String codeVerifier,
  }) async {
    final form = {
      'client_id': clientId,
      'code': code,
      'code_verifier': codeVerifier,
      'grant_type': 'authorization_code',
      'redirect_uri': redirectUri,
      if (clientSecret.trim().isNotEmpty) 'client_secret': clientSecret.trim(),
    };

    final response = await _dio.post<Map<String, dynamic>>(
      _tokenEndpoint,
      data: form,
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        validateStatus: (_) => true,
      ),
    );

    final data = response.data;
    if (data == null) {
      throw const DesktopGoogleOAuthException('Google token 响应为空');
    }
    if (response.statusCode != null && response.statusCode! >= 400) {
      final error = data['error']?.toString() ?? 'HTTP ${response.statusCode}';
      final description = data['error_description']?.toString();
      throw DesktopGoogleOAuthException(
        description == null || description.isEmpty
            ? 'Google token 交换失败：$error'
            : 'Google token 交换失败：$error - $description',
      );
    }
    if (data['error'] != null) {
      throw DesktopGoogleOAuthException('Google token 交换失败：${data['error']}');
    }
    return data;
  }

  static DesktopGoogleAccount accountFromTokenForTest(
    Map<String, dynamic> token,
  ) => _accountFromToken(token);

  static DesktopGoogleAccount _accountFromToken(Map<String, dynamic> token) {
    final idToken = token['id_token']?.toString();
    final accessToken = token['access_token']?.toString();
    if (idToken == null || idToken.isEmpty) {
      throw const DesktopGoogleOAuthException('Google 未返回 idToken');
    }
    if (accessToken == null || accessToken.isEmpty) {
      throw const DesktopGoogleOAuthException('Google 未返回 accessToken');
    }

    final claims = decodeJwtPayloadForTest(idToken);
    final id = claims['sub']?.toString();
    final email = claims['email']?.toString();
    if (id == null || id.isEmpty || email == null || email.isEmpty) {
      throw const DesktopGoogleOAuthException('Google 用户信息不完整');
    }

    return DesktopGoogleAccount(
      id: id,
      email: email,
      idToken: idToken,
      accessToken: accessToken,
      displayName: claims['name']?.toString(),
      photoUrl: claims['picture']?.toString(),
    );
  }

  static Map<String, dynamic> decodeJwtPayloadForTest(String jwt) {
    final parts = jwt.split('.');
    if (parts.length < 2) {
      throw const DesktopGoogleOAuthException('Google idToken 格式无效');
    }

    try {
      final normalized = base64Url.normalize(parts[1]);
      final jsonText = utf8.decode(base64Url.decode(normalized));
      return jsonDecode(jsonText) as Map<String, dynamic>;
    } catch (_) {
      throw const DesktopGoogleOAuthException('Google idToken 解析失败');
    }
  }

  static Future<void> _respondToBrowser(HttpRequest request) async {
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.html
      ..write('''
<!doctype html>
<html>
  <head><meta charset="utf-8"><title>Clawke</title></head>
  <body>
    <p>Google 登录已完成，可以返回 Clawke。</p>
    <p>Google sign-in is complete. You can return to Clawke.</p>
  </body>
</html>
''');
    await request.response.close();
  }

  static String _base64UrlNoPadding(List<int> bytes) =>
      base64UrlEncode(bytes).replaceAll('=', '');

  static String _secureRandomString(int length) {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => chars[random.nextInt(chars.length)],
    ).join();
  }
}

class DesktopGoogleOAuthException implements Exception {
  const DesktopGoogleOAuthException(this.message);

  final String message;

  @override
  String toString() => message;
}
