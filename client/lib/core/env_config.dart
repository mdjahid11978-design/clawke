/// 环境配置 —— 修改此文件切换环境。
class EnvConfig {
  EnvConfig._();

  /// clawke.ai Web 服务地址
  static const String webBaseUrl = 'https://clawke.ai';

  /// 桌面端 Google OAuth client id — Google OAuth client id for desktop platforms.
  static const String googleDesktopClientId = String.fromEnvironment(
    'GOOGLE_DESKTOP_CLIENT_ID',
    defaultValue: '',
  );

  /// 桌面端 Google OAuth client secret — Google OAuth client secret for desktop platforms.
  static const String googleDesktopClientSecret = String.fromEnvironment(
    'GOOGLE_DESKTOP_CLIENT_SECRET',
    defaultValue: '',
  );

  /// 是否允许自签名证书（本地开发时设为 true）
  static const bool allowBadCertificates = false;
}
