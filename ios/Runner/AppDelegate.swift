import Flutter
import UIKit
import Intents // Needed for INFocusStatusCenter
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  var focusChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self

      // Request notification authorization here, NOT in viewDidLoad
      UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
        if granted {
          print("[FocusStatus] Notification access granted")
        } else {
          print("[FocusStatus] Notification access denied: \(String(describing: error))")
        }
      }
    }
    GeneratedPluginRegistrant.register(with: self)

    // Resolve FlutterViewController for both pre/post iOS 13 scenes
    let controller: FlutterViewController? = {
      if let c = window?.rootViewController as? FlutterViewController { return c }
      if #available(iOS 13.0, *) {
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
          return scene.windows.first?.rootViewController as? FlutterViewController
        }
      } else {
        return UIApplication.shared.keyWindow?.rootViewController as? FlutterViewController
      }
      return nil
    }()

    if let controller = controller {
      let channel = FlutterMethodChannel(name: "focus_status", binaryMessenger: controller.binaryMessenger)
      self.focusChannel = channel

      channel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
        switch call.method {
        case "getFocusStatus":
          self?.getFocusStatus(result: result)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
      print("[FocusStatus] method channel registered")

      // Observe focus changes so we get updates even when the change happens while app is backgrounded.
      if #available(iOS 15.0, *) {
        INFocusStatusCenter.default.addObserver(self, forKeyPath: "focusStatus", options: [.new], context: nil)
      }
    } else {
      print("[FocusStatus] WARNING: FlutterViewController not found, method channel not registered")
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // KVO callback for focusStatus changes
  override func observeValue(forKeyPath keyPath: String?,
                             of object: Any?,
                             change: [NSKeyValueChangeKey : Any]?,
                             context: UnsafeMutableRawPointer?) {
    if keyPath == "focusStatus" {
      if #available(iOS 15.0, *) {
        let focused = INFocusStatusCenter.default.focusStatus.isFocused
        print("[FocusStatus] observed focusStatus change -> \(focused)")
        DispatchQueue.main.async {
          self.focusChannel?.invokeMethod("focusChanged", arguments: focused)
        }
      } else {
        DispatchQueue.main.async {
          self.focusChannel?.invokeMethod("focusChanged", arguments: nil)
        }
      }
    } else {
      super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
    }
  }

  private func getFocusStatus(result: @escaping FlutterResult) {
    print("[FocusStatus] getFocusStatus called")
    if #available(iOS 15.0, *) {
      INFocusStatusCenter.default.requestAuthorization { authStatus in
        print("[FocusStatus] authorization: \(authStatus.rawValue)")
        if authStatus == .authorized {
          let focused = INFocusStatusCenter.default.focusStatus.isFocused
          print("[FocusStatus] isFocused: \(focused)")
          result(focused)
        } else {
          print("[FocusStatus] NOT AUTHORIZED")
          // return an explicit error so Dart can treat it differently
          result(FlutterError(code: "UNAUTHORIZED", message: "Focus access not authorized", details: nil))
        }
      }
    } else {
      print("[FocusStatus] unsupported iOS version")
      result(FlutterError(code: "UNSUPPORTED", message: "iOS 15+ required", details: nil))
    }
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    print("[FocusStatus] applicationDidBecomeActive")
    if #available(iOS 15.0, *) {
      INFocusStatusCenter.default.requestAuthorization { authStatus in
        var isFocused: Bool? = nil
        if authStatus == .authorized {
          isFocused = INFocusStatusCenter.default.focusStatus.isFocused
        }
        print("[FocusStatus] broadcasting focusChanged: \(String(describing: isFocused))")
        DispatchQueue.main.async {
          self.focusChannel?.invokeMethod("focusChanged", arguments: isFocused)
        }
      }
    } else {
      DispatchQueue.main.async {
        self.focusChannel?.invokeMethod("focusChanged", arguments: nil)
      }
    }
  }

  @available(iOS 10.0, *)
  override func userNotificationCenter(_ center: UNUserNotificationCenter,
                                        willPresent notification: UNNotification,
                                        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
    completionHandler([.alert, .sound, .badge])
  }

  // make sure to remove observer when terminating (best-effort)
  override func applicationWillTerminate(_ application: UIApplication) {
    if #available(iOS 15.0, *) {
      INFocusStatusCenter.default.removeObserver(self, forKeyPath: "focusStatus")
    }
    super.applicationWillTerminate(application)
  }
}
