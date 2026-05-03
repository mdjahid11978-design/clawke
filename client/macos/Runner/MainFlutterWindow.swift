import Cocoa
import FlutterMacOS
import UserNotifications

class MainFlutterWindow: NSWindow {
  private var appBadgeChannel: FlutterMethodChannel?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // 确保标题栏和红/黄/绿交通灯按钮可见（App Store 审核要求 Guideline 4）
    self.styleMask.insert([.titled, .closable, .miniaturizable, .resizable])
    self.titlebarAppearsTransparent = false
    self.titleVisibility = .visible

    // 最小窗口尺寸
    self.minSize = NSSize(width: 800, height: 500)

    // 从 UserDefaults 恢复窗口大小（仅大小，不记位置）
    let defaults = UserDefaults.standard
    let savedWidth = defaults.double(forKey: "ClawkeWindowWidth")
    let savedHeight = defaults.double(forKey: "ClawkeWindowHeight")

    let width: CGFloat = savedWidth >= 800 ? CGFloat(savedWidth) : 1024
    let height: CGFloat = savedHeight >= 500 ? CGFloat(savedHeight) : 768

    let size = NSSize(width: width, height: height)
    self.setContentSize(size)
    self.center()
    NSLog("[Clawke] Window init: saved=(%g, %g) → applied=(%g x %g)", savedWidth, savedHeight, width, height)

    RegisterGeneratedPlugins(registry: flutterViewController)
    setupAppBadgeChannel(binaryMessenger: flutterViewController.engine.binaryMessenger)
    (NSApp.delegate as? AppDelegate)?.setupPushChannel(
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )

    super.awakeFromNib()

    // 确保窗口在启动时获得焦点（否则 flutter run 时终端保持焦点，
    // macOS 会暂停 Dart 事件循环，导致 WebSocket 连接等 Dart 代码不执行）
    NSApp.activate(ignoringOtherApps: true)
    self.makeKeyAndOrderFront(nil)
  }

  // 关闭窗口时保存大小
  override func close() {
    let defaults = UserDefaults.standard
    defaults.set(Double(self.frame.width), forKey: "ClawkeWindowWidth")
    defaults.set(Double(self.frame.height), forKey: "ClawkeWindowHeight")
    NSLog("[Clawke] Window saved on close: %g x %g", self.frame.width, self.frame.height)
    super.close()
  }

  private func setupAppBadgeChannel(binaryMessenger: FlutterBinaryMessenger) {
    appBadgeChannel = FlutterMethodChannel(
      name: "clawke/app_badge",
      binaryMessenger: binaryMessenger
    )
    appBadgeChannel?.setMethodCallHandler { call, result in
      guard call.method == "setBadgeCount" || call.method == "openNotificationSettings" else {
        result(FlutterMethodNotImplemented)
        return
      }
      if call.method == "openNotificationSettings" {
        self.openNotificationSettings()
        result(nil)
        return
      }

      let args = call.arguments as? [String: Any]
      let rawCount: Int
      if let number = args?["count"] as? NSNumber {
        rawCount = number.intValue
      } else {
        rawCount = args?["count"] as? Int ?? 0
      }
      let count = max(rawCount, 0)

      DispatchQueue.main.async {
        self.updateAppBadgeCount(count)
        result(nil)
      }
    }
  }

  private func updateAppBadgeCount(_ count: Int) {
    let badgeLabel = count > 0 ? "\(count)" : nil
    NSApplication.shared.dockTile.badgeLabel = badgeLabel
    NSApplication.shared.dockTile.display()

    if #available(macOS 13.0, *) {
      UNUserNotificationCenter.current().setBadgeCount(count) { error in
        if let error = error {
          NSLog("[Clawke] App badge count failed: %@", error.localizedDescription)
        } else {
          NSLog("[Clawke] App badge count updated: %d", count)
        }
      }
    }
    NSLog("[Clawke] Dock badge updated: %@", badgeLabel ?? "none")
  }

  private func openNotificationSettings() {
    let settingsUrls = [
      "x-apple.systempreferences:com.apple.Notifications-Settings.extension",
      "x-apple.systempreferences:com.apple.preference.notifications"
    ]
    for value in settingsUrls {
      if let url = URL(string: value), NSWorkspace.shared.open(url) {
        NSLog("[Clawke] Opened notification settings")
        return
      }
    }
    if let url = URL(string: "x-apple.systempreferences:") {
      NSWorkspace.shared.open(url)
    }
  }
}
