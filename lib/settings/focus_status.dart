import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:universal_io/universal_io.dart' show Platform;

/// see INFocusStatusAuthorizationStatus
enum FocusAuthorizationStatus { notDetermined, restricted, denied, authorized }

class FocusStatus {
  static const _channel = MethodChannel('focus_status');

  /// null = unsupported/unknown, true = focused, false = not focused
  static final status = ValueNotifier<bool?>(null);

  /// null = not an iOS device or status not yet known
  static final authorizationStatus = ValueNotifier<FocusAuthorizationStatus?>(
    null,
  );

  /// Initializes the FocusStatus service.
  ///
  /// This must be called once at app startup. It sets up the method channel,
  /// requests the initial focus status from the native side, and waits for the
  /// first value to be broadcasted.
  static Future<bool?> init() async {
    if (kIsWeb || !Platform.isIOS) {
      return null;
    }
    _channel.setMethodCallHandler(_handleMethodCall);
    // Request the initial status and wait for the first 'focusChanged' call.
    await getFocusStatus();
    return status.value;
  }

  static Future<void> _handleMethodCall(MethodCall call) async {
    if (call.method == 'focusChanged') {
      final arg = call.arguments;
      status.value = arg is bool ? arg : null;
    }
  }

  static Future<bool> _isSystemVersionAtLeast(int version) async {
    final iosInfo = await DeviceInfoPlugin().iosInfo;
    final major = int.tryParse(iosInfo.systemVersion.split('.').first);
    if (major == null) {
      throw FormatException(
        "Failed to parse iOS version from '${iosInfo.systemVersion}'",
      );
    }
    return major >= version;
  }

  static Future<bool?> getFocusStatus() async {
    if (kIsWeb || !Platform.isIOS) {
      status.value = null;
      return null;
    }
    if (!await _isSystemVersionAtLeast(15)) {
      debugPrint('Focus status not supported below iOS 15');
      return null;
    }

    try {
      // This call's primary purpose is to trigger the authorization prompt if needed.
      // The native side now returns the current focus state upon authorization.
      final isFocused = await _channel.invokeMethod('getFocusStatus');
      // If successful, we know we are authorized.
      authorizationStatus.value = FocusAuthorizationStatus.authorized;
      if (isFocused is bool) {
        status.value = isFocused;
      }
    } on PlatformException catch (e) {
      if (e.code == 'UNAUTHORIZED') {
        // App not granted Focus access — treat as "not focused" so UI can offer Settings
        authorizationStatus.value =
            FocusAuthorizationStatus.values[e.details as int];
        status.value = false;
      }
      // For other errors (like 'UNSUPPORTED'), status remains null.
    }
    return status.value;
  }

  static Future<bool> openFocusSettings() async {
    if (kIsWeb || !Platform.isIOS) {
      return false;
    }
    if (!await _isSystemVersionAtLeast(16)) {
      debugPrint('Focus settings not available below iOS 16');
      return false;
    }
    try {
      return await _channel.invokeMethod('openFocusSettings') == true;
    } on PlatformException {
      return false;
    }
  }
}
