import Flutter
import Foundation
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var appBadgeChannel: FlutterMethodChannel?
  private var pushChannel: FlutterMethodChannel?
  private var pendingPushTokenResult: FlutterResult?
  private var pendingRemotePushPayloads: [[String: Any]] = []

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    logNative("iOS app didFinishLaunching")
    enqueueLaunchRemotePushPayload(launchOptions)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    setupAppBadgeChannel(binaryMessenger: engineBridge.applicationRegistrar.messenger())
    setupPushChannel(binaryMessenger: engineBridge.applicationRegistrar.messenger())
  }

  private func setupAppBadgeChannel(binaryMessenger: FlutterBinaryMessenger) {
    appBadgeChannel = FlutterMethodChannel(
      name: "clawke/app_badge",
      binaryMessenger: binaryMessenger
    )
    appBadgeChannel?.setMethodCallHandler { call, result in
      switch call.method {
      case "setBadgeCount":
        let args = call.arguments as? [String: Any]
        let rawCount: Int
        if let number = args?["count"] as? NSNumber {
          rawCount = number.intValue
        } else {
          rawCount = args?["count"] as? Int ?? 0
        }
        self.updateAppBadgeCount(max(rawCount, 0))
        result(nil)
      case "openNotificationSettings":
        self.openNotificationSettings()
        result(nil)
      case "checkNotificationsEnabled":
        self.checkNotificationsEnabled(result: result)
      case "checkNotificationSettingsDetails":
        self.checkNotificationSettingsDetails(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func setupPushChannel(binaryMessenger: FlutterBinaryMessenger) {
    pushChannel = FlutterMethodChannel(
      name: "clawke/push",
      binaryMessenger: binaryMessenger
    )
    pushChannel?.setMethodCallHandler { call, result in
      switch call.method {
      case "registerForRemoteNotifications":
        self.logNative("Remote push registration requested")
        self.pendingPushTokenResult = result
        DispatchQueue.main.async {
          UIApplication.shared.registerForRemoteNotifications()
        }
      case "takeRemotePushPayloads":
        result(self.pendingRemotePushPayloads)
        self.pendingRemotePushPayloads.removeAll()
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    let token = deviceToken.map { String(format: "%02x", $0) }.joined()
    logNative("Remote push token registered: token_len=\(token.count)")
    pendingPushTokenResult?(["token": token, "platform": "ios"])
    pendingPushTokenResult = nil
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    logNative("Remote push token registration failed: \(error.localizedDescription)")
    pendingPushTokenResult?(
      FlutterError(
        code: "apns_registration_failed",
        message: error.localizedDescription,
        details: nil
      )
    )
    pendingPushTokenResult = nil
  }

  override func application(
    _ application: UIApplication,
    didReceiveRemoteNotification userInfo: [AnyHashable: Any],
    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
  ) {
    logNative("Remote push delivered to app")
    enqueueRemotePushPayload(userInfo, eventType: "delivery")
    completionHandler(.newData)
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    logNative("Notification tapped")
    enqueueRemotePushPayload(
      response.notification.request.content.userInfo,
      eventType: "notification_tap"
    )
    completionHandler()
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    logNative("Notification will present: id=\(notification.request.identifier)")
    enqueueRemotePushPayload(
      notification.request.content.userInfo,
      eventType: "delivery"
    )
    if #available(iOS 14.0, *) {
      completionHandler([.banner, .list, .sound, .badge])
    } else {
      completionHandler([.alert, .sound, .badge])
    }
  }

  private func enqueueRemotePushPayload(_ userInfo: [AnyHashable: Any], eventType: String) {
    let payload = normalizeRemotePushPayload(userInfo, eventType: eventType)
    if payload.isEmpty {
      logNative("Remote push payload ignored: no Clawke keys")
      return
    }
    logNative(
      "Remote push received: event=\(eventType) conv=\(payload["conversation_id"] ?? "-") msg=\(payload["message_id"] ?? "-") seq=\(payload["seq"] ?? "-")"
    )
    pendingRemotePushPayloads.append(payload)
    pushChannel?.invokeMethod("remotePushReceived", arguments: payload)
  }

  private func enqueueLaunchRemotePushPayload(
    _ launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) {
    guard let userInfo = launchOptions?[.remoteNotification] as? [AnyHashable: Any] else {
      return
    }
    enqueueRemotePushPayload(userInfo, eventType: "notification_tap")
  }

  private func normalizeRemotePushPayload(_ userInfo: [AnyHashable: Any], eventType: String) -> [String: Any] {
    var payload: [String: Any] = [:]
    for (key, value) in userInfo {
      guard let key = key as? String else { continue }
      if key == "conversation_id" || key == "message_id" || key == "gateway_id" {
        payload[key] = "\(value)"
      } else if key == "seq" {
        if let number = value as? NSNumber {
          payload[key] = number.intValue
        } else {
          payload[key] = Int("\(value)") ?? 0
        }
      }
    }
    if !payload.isEmpty {
      payload["event_type"] = eventType
    }
    return payload
  }

  private func updateAppBadgeCount(_ count: Int) {
    if #available(iOS 16.0, *) {
      UNUserNotificationCenter.current().setBadgeCount(count) { error in
        if let error = error {
          self.logNative("App badge count failed: \(error.localizedDescription)")
        }
      }
    } else {
      UIApplication.shared.applicationIconBadgeNumber = count
    }
  }

  private func openNotificationSettings() {
    guard let url = URL(string: UIApplication.openSettingsURLString) else {
      return
    }
    UIApplication.shared.open(url)
  }

  private func checkNotificationsEnabled(result: @escaping FlutterResult) {
    UNUserNotificationCenter.current().getNotificationSettings { settings in
      self.logNotificationSettings(settings)
      let enabled: Bool
      if #available(iOS 14.0, *) {
        enabled = settings.authorizationStatus == .authorized ||
          settings.authorizationStatus == .provisional ||
          settings.authorizationStatus == .ephemeral
      } else {
        enabled = settings.authorizationStatus == .authorized ||
          settings.authorizationStatus == .provisional
      }
      result(enabled)
    }
  }

  private func checkNotificationSettingsDetails(result: @escaping FlutterResult) {
    UNUserNotificationCenter.current().getNotificationSettings { settings in
      self.logNotificationSettings(settings)
      result([
        "authorization": settings.authorizationStatus.rawValue,
        "alert": settings.alertSetting.rawValue,
        "alertStyle": settings.alertStyle.rawValue,
        "badge": settings.badgeSetting.rawValue,
        "sound": settings.soundSetting.rawValue,
        "lockScreen": settings.lockScreenSetting.rawValue,
        "notificationCenter": settings.notificationCenterSetting.rawValue,
        "showPreviews": settings.showPreviewsSetting.rawValue,
        "timeSensitive": self.timeSensitiveSettingValue(settings),
        "scheduledDelivery": self.scheduledDeliverySettingValue(settings),
        "directMessages": self.directMessagesSettingValue(settings)
      ])
    }
  }

  private func logNotificationSettings(_ settings: UNNotificationSettings) {
    logNative(
      "Notification settings: authorization=\(settings.authorizationStatus.rawValue) alert=\(settings.alertSetting.rawValue) alertStyle=\(settings.alertStyle.rawValue) badge=\(settings.badgeSetting.rawValue) sound=\(settings.soundSetting.rawValue) lockScreen=\(settings.lockScreenSetting.rawValue) notificationCenter=\(settings.notificationCenterSetting.rawValue) showPreviews=\(settings.showPreviewsSetting.rawValue) timeSensitive=\(timeSensitiveSettingValue(settings)) scheduledDelivery=\(scheduledDeliverySettingValue(settings)) directMessages=\(directMessagesSettingValue(settings))"
    )
  }

  private func timeSensitiveSettingValue(_ settings: UNNotificationSettings) -> Int {
    if #available(iOS 15.0, *) {
      return settings.timeSensitiveSetting.rawValue
    }
    return -1
  }

  private func scheduledDeliverySettingValue(_ settings: UNNotificationSettings) -> Int {
    if #available(iOS 15.0, *) {
      return settings.scheduledDeliverySetting.rawValue
    }
    return -1
  }

  private func directMessagesSettingValue(_ settings: UNNotificationSettings) -> Int {
    if #available(iOS 15.0, *) {
      return settings.directMessagesSetting.rawValue
    }
    return -1
  }

  private func logNative(_ message: String) {
    let formatted = "[Clawke] \(message)"
    NSLog("%@", formatted)

    guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
      return
    }
    let logDirectory = documents.appendingPathComponent("logs", isDirectory: true)
    do {
      try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
      let fileURL = logDirectory.appendingPathComponent("ios-native-\(Self.nativeLogDate()).log")
      let line = "[\(Self.nativeLogTimestamp())] \(formatted)\n"
      guard let data = line.data(using: .utf8) else {
        return
      }
      if FileManager.default.fileExists(atPath: fileURL.path) {
        let handle = try FileHandle(forWritingTo: fileURL)
        defer { try? handle.close() }
        handle.seekToEndOfFile()
        handle.write(data)
      } else {
        try data.write(to: fileURL, options: .atomic)
      }
    } catch {
      NSLog("[Clawke] Native log write failed: %@", error.localizedDescription)
    }
  }

  private static func nativeLogDate() -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone.current
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: Date())
  }

  private static func nativeLogTimestamp() -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone.current
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ"
    return formatter.string(from: Date())
  }
}
