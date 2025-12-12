import Flutter
import UIKit
import Intents // Needed for INFocusStatusCenter

// Define a unique KVO context to avoid potential conflicts.
private var focusStatusKVOContext = 0

public class FocusStatusPlugin: NSObject, FlutterPlugin {
    private var channel: FlutterMethodChannel

    init(channel: FlutterMethodChannel) {
        self.channel = channel
        super.init()

        if #available(iOS 15.0, *) {
            INFocusStatusCenter.default.focusStatus.addObserver(self, forKeyPath: "isFocused", options: [.new], context: &focusStatusKVOContext)
            print("[FocusStatusPlugin] KVO observer added for 'isFocused'")

            // Add an observer for when the app becomes active
            NotificationCenter.default.addObserver(self, selector: #selector(appDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)

            // Fetch initial status after a short delay to ensure accuracy
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.broadcastFocusStatus(isFocused: INFocusStatusCenter.default.focusStatus.isFocused, from: "initial fetch")
            }
        }
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "focus_status", binaryMessenger: registrar.messenger())
        let instance = FocusStatusPlugin(channel: channel)
        registrar.addMethodCallDelegate(instance, channel: channel)
        print("[FocusStatusPlugin] Registered with Flutter.")
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getFocusStatus":
            getFocusStatus(result: result)
        case "openFocusSettings":
            openFocusSettings(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // KVO callback for focusStatus changes
    override public func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if context == &focusStatusKVOContext {
            if #available(iOS 15.0, *) {
                print("[FocusStatusPlugin] KVO observeValue triggered for focusStatus")
                if let isFocused = (change?[.newKey] as? NSNumber)?.boolValue {
                    broadcastFocusStatus(isFocused: isFocused, from: "KVO")
                }
            }
        } else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }

    private func getFocusStatus(result: @escaping FlutterResult) {
        print("[FocusStatusPlugin] getFocusStatus called")
        if #available(iOS 15.0, *) {
            INFocusStatusCenter.default.requestAuthorization { [weak self] authStatus in
                print("[FocusStatusPlugin] authorization: \(authStatus.rawValue)")
                switch authStatus {
                case .authorized:
                    let isFocused = INFocusStatusCenter.default.focusStatus.isFocused
                    print("[FocusStatusPlugin] Authorization granted. Current isFocused state: \(isFocused)")
                    self?.broadcastFocusStatus(isFocused: isFocused, from: "getFocusStatus")
                    result(isFocused)
                case .denied, .notDetermined, .restricted:
                    result(FlutterError(code: "UNAUTHORIZED", message: "Focus access not authorized", details: authStatus.rawValue))
                @unknown default:
                    result(FlutterError(code: "UNKNOWN", message: "Unknown authorization status", details: nil))
                }
            }
        } else {
            print("[FocusStatusPlugin] unsupported iOS version")
            result(FlutterError(code: "UNSUPPORTED", message: "iOS 15+ required", details: nil))
        }
    }

    private func openFocusSettings(result: @escaping FlutterResult) {
        if #available(iOS 16.0, *) {
            if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                UIApplication.shared.open(url)
                result(true)
                return
            }
        }
        result(false)
    }

    private func broadcastFocusStatus(isFocused: Bool?, from source: String) {
        print("[FocusStatusPlugin] Broadcasting focusChanged=\(String(describing: isFocused)) from: \(source)")
        DispatchQueue.main.async {
            self.channel.invokeMethod("focusChanged", arguments: isFocused)
        }
    }

    @objc private func appDidBecomeActive() {
        print("[FocusStatusPlugin] App became active, re-checking status.")
        getFocusStatus(result: { _ in /* Result is ignored, broadcast handles the update */ })
    }

    deinit {
        if #available(iOS 15.0, *) {
            INFocusStatusCenter.default.focusStatus.removeObserver(self, forKeyPath: "isFocused", context: &focusStatusKVOContext)
        }
        NotificationCenter.default.removeObserver(self)
    }
}