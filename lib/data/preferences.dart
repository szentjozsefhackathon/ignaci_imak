import 'package:flutter/foundation.dart' show ChangeNotifier, kIsWeb;
import 'package:provider/provider.dart' show ChangeNotifierProvider;
import 'package:shared_preferences/shared_preferences.dart';

import '../theme.dart' show AppThemeMode;
import 'versions.dart';

class Preferences extends ChangeNotifier {
  Preferences(this._p);

  static const _kVersions = 'versions';
  static const _kLastSync = 'lastSync';
  static const _kThemeMode = 'themeMode';
  static const _kDnd = 'dnd';
  static const _kReminderNotifications = 'reminderNotifications';
  static const _kAutoPageTurn = 'autoPageTurn';
  static const _kPrayerLength = 'prayerLength';
  static const _kPrayerSoundEnabled = 'prayerSoundEnabled';
  static const _kVoiceChoice = 'voiceChoice';

  final SharedPreferencesWithCache _p;

  Versions? get versions {
    final list = _p.getStringList(_kVersions);
    final ts = _p.getInt(_kLastSync);
    if (list == null || ts == null) {
      return null;
    }
    final [data, images, voices] = list;
    return Versions(
      data: data,
      images: images,
      voices: voices,
      timestamp: DateTime.fromMillisecondsSinceEpoch(ts, isUtc: true),
    );
  }

  Future<void> setVersions(Versions v) async {
    await _p.setStringList(_kVersions, [v.data, v.images, v.voices]);
    await _p.setInt(_kLastSync, v.timestamp.toUtc().millisecondsSinceEpoch);
    notifyListeners();
  }

  Future<void> deleteVersions() async {
    await _p.remove(_kVersions);
    await _p.remove(_kLastSync);
    notifyListeners();
  }

  AppThemeMode get themeMode {
    final index = _p.getInt(_kThemeMode);
    if (index != null) {
      return AppThemeMode.values[index];
    }
    return AppThemeMode.system;
  }

  Future<void> setThemeMode(AppThemeMode mode) async {
    await _p.setInt(_kThemeMode, mode.index);
    notifyListeners();
  }

  bool get dnd => _p.getBool(_kDnd) ?? !kIsWeb;

  Future<void> setDnd(bool enabled) async {
    if (kIsWeb) {
      return;
    }
    await _p.setBool(_kDnd, enabled);
    notifyListeners();
  }

  bool get reminderNotifications =>
      _p.getBool(_kReminderNotifications) ?? !kIsWeb;

  Future<void> setReminderNotifications(bool enabled) async {
    if (kIsWeb) {
      return;
    }
    await _p.setBool(_kReminderNotifications, enabled);
    notifyListeners();
  }

  bool get autoPageTurn => _p.getBool(_kAutoPageTurn) ?? true;

  Future<void> setAutoPageTurn(bool enabled) async {
    await _p.setBool(_kAutoPageTurn, enabled);
    notifyListeners();
  }

  Duration get prayerLength =>
      Duration(minutes: _p.getInt(_kPrayerLength) ?? 30);

  Future<void> setPrayerLength(Duration length) async {
    await _p.setInt(_kPrayerLength, length.inMinutes);
    notifyListeners();
  }

  bool get prayerSoundEnabled => _p.getBool(_kPrayerSoundEnabled) ?? true;

  Future<void> setPrayerSoundEnabled(bool enabled) async {
    await _p.setBool(_kPrayerSoundEnabled, enabled);
    notifyListeners();
  }

  String get voiceChoice => _p.getString(_kVoiceChoice) ?? 'Férfi 2';

  Future<void> setVoiceChoice(String voice) async {
    await _p.setString(_kVoiceChoice, voice);
    notifyListeners();
  }
}

class PreferencesProvider extends ChangeNotifierProvider<Preferences> {
  PreferencesProvider(SharedPreferencesWithCache prefs, {super.key})
    : super.value(value: Preferences(prefs));
}
