import Flutter
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
    pendingPushTokenResult?(["token": token, "platform": "ios"])
    pendingPushTokenResult = nil
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
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
    enqueueRemotePushPayload(userInfo, eventType: "delivery")
    completionHandler(.newData)
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
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
      return
    }
    NSLog("[Clawke] Remote push received")
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
          NSLog("[Clawke] App badge count failed: %@", error.localizedDescription)
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
}
