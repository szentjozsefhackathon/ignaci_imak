import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart' show ChangeNotifierProvider;
import 'package:universal_io/universal_io.dart' show Platform;

/// see INFocusStatusAuthorizationStatus
enum FocusAuthorizationStatus { notDetermined, restricted, denied, authorized }

class FocusStatus extends ChangeNotifier {
  FocusStatus._() {
    if (kIsWeb || !Platform.isIOS) {
      return;
    }
    _channel.setMethodCallHandler((MethodCall call) async {
      if (call.method == 'focusChanged') {
        final arg = call.arguments;
        _updateStatus(arg is bool ? arg : null, _authStatus);
      }
    });
    _getFocusStatus().then((r) {
      if (r == null) {
        _updateStatus(null, null);
      } else {
        final (status, authStatus) = r;
        _updateStatus(status, authStatus);
      }
    });
  }

  static const _channel = MethodChannel('focus_status');

  /// null = unsupported/unknown, true = focused, false = not focused
  bool? get status => _status;
  bool? _status;

  void _updateStatus(bool? status, FocusAuthorizationStatus? authStatus) {
    if (_status == status && _authStatus == authStatus) {
      return;
    }
    _status = status;
    _authStatus = authStatus;
    notifyListeners();
  }

  /// null = not an iOS device or status not yet known
  FocusAuthorizationStatus? get authStatus => _authStatus;
  FocusAuthorizationStatus? _authStatus;

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

  static Future<(bool, FocusAuthorizationStatus)?> _getFocusStatus() async {
    if (kIsWeb || !Platform.isIOS) {
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
      if (isFocused is bool) {
        return (isFocused, FocusAuthorizationStatus.authorized);
      }
    } on PlatformException catch (e) {
      if (e.code == 'UNAUTHORIZED') {
        // App not granted Focus access — treat as "not focused" so UI can offer Settings
        return (false, FocusAuthorizationStatus.values[e.details as int]);
      }
      // For other errors (like 'UNSUPPORTED'), status remains null.
    }
    return null;
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

class FocusStatusProvider extends ChangeNotifierProvider<FocusStatus> {
  FocusStatusProvider({super.key})
    : super(create: (context) => FocusStatus._());
}
