import Cocoa
import FlutterMacOS
import UserNotifications

@main
class AppDelegate: FlutterAppDelegate, UNUserNotificationCenterDelegate {
  private var pushChannel: FlutterMethodChannel?
  private var pendingPushTokenResult: FlutterResult?
  private var pendingRemotePushPayloads: [[String: Any]] = []

  override func applicationDidFinishLaunching(_ notification: Notification) {
    UNUserNotificationCenter.current().delegate = self
    enqueueLaunchNotificationPayload(notification.userInfo)
    super.applicationDidFinishLaunching(notification)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  func setupPushChannel(binaryMessenger: FlutterBinaryMessenger) {
    pushChannel = FlutterMethodChannel(
      name: "clawke/push",
      binaryMessenger: binaryMessenger
    )
    pushChannel?.setMethodCallHandler { call, result in
      switch call.method {
      case "registerForRemoteNotifications":
        self.pendingPushTokenResult = result
        DispatchQueue.main.async {
          NSApplication.shared.registerForRemoteNotifications(matching: [.alert, .badge])
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
    _ application: NSApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    let token = deviceToken.map { String(format: "%02x", $0) }.joined()
    pendingPushTokenResult?(["token": token, "platform": "macos"])
    pendingPushTokenResult = nil
  }

  override func application(
    _ application: NSApplication,
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
    _ application: NSApplication,
    didReceiveRemoteNotification userInfo: [String: Any]
  ) {
    enqueueRemotePushPayload(userInfo, eventType: "delivery")
  }

  func userNotificationCenter(
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

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    enqueueRemotePushPayload(
      notification.request.content.userInfo,
      eventType: "delivery"
    )
    if #available(macOS 11.0, *) {
      completionHandler([.banner, .list, .badge])
    } else {
      completionHandler([.alert, .badge])
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

  private func enqueueLaunchNotificationPayload(_ launchUserInfo: [AnyHashable: Any]?) {
    guard let launchValue = launchUserInfo?[NSApplication.launchUserNotificationUserInfoKey] else {
      return
    }

    if let response = launchValue as? UNNotificationResponse {
      enqueueRemotePushPayload(
        response.notification.request.content.userInfo,
        eventType: "notification_tap"
      )
      return
    }

    if let notification = launchValue as? UNNotification {
      enqueueRemotePushPayload(
        notification.request.content.userInfo,
        eventType: "notification_tap"
      )
      return
    }

    if let notification = launchValue as? NSUserNotification,
       let userInfo = notification.userInfo {
      enqueueRemotePushPayload(userInfo, eventType: "notification_tap")
      return
    }

    if let userInfo = launchValue as? [AnyHashable: Any] {
      enqueueRemotePushPayload(userInfo, eventType: "notification_tap")
      return
    }

    if let userInfo = launchValue as? [String: Any] {
      let normalized = userInfo.reduce(into: [AnyHashable: Any]()) { result, item in
        result[AnyHashable(item.key)] = item.value
      }
      enqueueRemotePushPayload(normalized, eventType: "notification_tap")
    }
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
}
