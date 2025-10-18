import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class FocusStatus {
  static const MethodChannel _channel = MethodChannel('focus_status');

  // null = unsupported, true = focused, false = not focused / unauthorized
  static final ValueNotifier<bool?> status = ValueNotifier<bool?>(null);

  static Future<void> init() async {
    _channel.setMethodCallHandler(_handleMethodCall);
    await _refresh();
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
    if (Platform.isIOS) {
      final iosInfo = await DeviceInfoPlugin().iosInfo;
      final version = iosInfo.systemVersion?.split(".").first ?? "0";
      final major = int.tryParse(version) ?? 0;

      if (major < 15) {
        print("Focus status not supported below iOS 15");
        return null;
      }
    }

    try {
      final dynamic res = await _channel.invokeMethod('getFocusStatus');
      if (res is bool) {
        status.value = res;
        return res;
      }
      status.value = null;
      return null;
    } on PlatformException catch (e) {
      if (e.code == 'UNSUPPORTED') {
        status.value = null;
        return null;
      }
      // treat UNAUTHORIZED and others as "not focused" so UI can offer Settings
      status.value = false;
      return false;
    } catch (_) {
      status.value = null;
      return null;
    }
  }

  static Future<bool> openFocusSettings() async {
    if (Platform.isIOS) {
      final iosInfo = await DeviceInfoPlugin().iosInfo;
      final version = iosInfo.systemVersion?.split(".").first ?? "0";
      final major = int.tryParse(version) ?? 0;

      if (major < 15) {
        print("Focus settings not available below iOS 15");
        return false;
      }
    }

    try {
      final dynamic res = await _channel.invokeMethod('openFocusSettings');
      return res == true;
    } on PlatformException {
      return false;
    }
  }

  static Future<void> _refresh() async {
    await getFocusStatus();
  }
}