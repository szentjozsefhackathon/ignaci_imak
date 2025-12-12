import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class FocusStatus {
  static const MethodChannel _channel = MethodChannel('focus_status');

  // null = unsupported/unknown, true = focused, false = not focused
  static final ValueNotifier<bool?> status = ValueNotifier<bool?>(null);

  // Based on INFocusStatusAuthorizationStatus: 0=notDetermined, 1=restricted, 2=denied, 3=authorized
  // null = not an iOS device or status not yet known.
  static final ValueNotifier<int?> authorizationStatus = ValueNotifier<int?>(null);

  /// Initializes the FocusStatus service.
  ///
  /// This must be called once at app startup. It sets up the method channel,
  /// requests the initial focus status from the native side, and waits for the
  /// first value to be broadcasted.
  static Future<bool?> init() async {
    if (!Platform.isIOS) return null;
    _channel.setMethodCallHandler(_handleMethodCall);
    // Request the initial status and wait for the first 'focusChanged' call.
    await getFocusStatus();
    return status.value;
  }

  static Future<void> _handleMethodCall(MethodCall call) async {
    if (call.method == 'focusChanged') {
      final arg = call.arguments;
      if (arg is bool) {
        status.value = arg;
      } else {
        status.value = null;
      }
    }
  }

  static Future<bool?> getFocusStatus() async {
    if (!Platform.isIOS) {
      status.value = null;
      return null;
    }
    final iosInfo = await DeviceInfoPlugin().iosInfo;
    final version = iosInfo.systemVersion?.split(".").first ?? "0";
    final major = int.tryParse(version) ?? 0;
    if (major < 15) {
      debugPrint("Focus status not supported below iOS 15");
      return null;
    }
    try {
      // This call's primary purpose is to trigger the authorization prompt if needed.
      // The native side now returns the current focus state upon authorization.
      final isFocused = await _channel.invokeMethod('getFocusStatus');
      // If successful, we know we are authorized.
      authorizationStatus.value = 3;
      if (isFocused is bool) {
        status.value = isFocused;
      }
    } on PlatformException catch (e) {
      if (e.code == 'UNAUTHORIZED') {
        // App not granted Focus access — treat as "not focused" so UI can offer Settings
        authorizationStatus.value = e.details as int?;
        status.value = false;
      }
      // For other errors (like 'UNSUPPORTED'), status remains null.
    }
    return status.value;
  }

  static Future<bool> openFocusSettings() async {
    if (!Platform.isIOS) {
      return false;
    }
    final iosInfo = await DeviceInfoPlugin().iosInfo;
    final version = iosInfo.systemVersion?.split(".").first ?? "0";
    final major = int.tryParse(version) ?? 0;
    if (major < 16) {
      debugPrint("Focus settings not available below iOS 16");
      return false;
    }
    try {
      return await _channel.invokeMethod('openFocusSettings') == true;
    } on PlatformException {
      return false;
    }
  }
}