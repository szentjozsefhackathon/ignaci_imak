import 'dart:convert' show json;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'common.dart';

part 'settings_data.g.dart';

const _kUserSettings = 'userData';

@JsonSerializable()
class SettingsData extends ChangeNotifier implements DataDescriptor {
  SettingsData({
    ThemeMode themeMode = ThemeMode.system,
    bool dnd = !kIsWeb,
    bool reminderNotifications = !kIsWeb,
    bool autoPageTurn = true,
    int prayerLength = 30,
    bool prayerSoundEnabled = true,
    String voiceChoice = 'Férfi 2',
  }) : _themeMode = themeMode,
       _dnd = dnd,
       _reminderNotifications = reminderNotifications,
       _autoPageTurn = autoPageTurn,
       _prayerLength = prayerLength,
       _prayerSoundEnabled = prayerSoundEnabled,
       _voiceChoice = voiceChoice;

  factory SettingsData.fromJson(Json json) => _$SettingsDataFromJson(json);

  static final log = Logger('UserSettingsData');

  ThemeMode _themeMode;
  ThemeMode get themeMode => _themeMode;
  set themeMode(ThemeMode newValue) {
    if (_themeMode != newValue) {
      _themeMode = newValue;
      save();
      notifyListeners();
    }
  }

  bool _dnd;
  bool get dnd => _dnd;
  set dnd(bool newValue) {
    if (kIsWeb) {
      return;
    }
    if (_dnd != newValue) {
      _dnd = newValue;
      save();
      notifyListeners();
    }
  }

  bool _reminderNotifications;
  bool get reminderNotifications => _reminderNotifications;
  set reminderNotifications(bool newValue) {
    if (kIsWeb) {
      return;
    }
    if (_reminderNotifications != newValue) {
      _reminderNotifications = newValue;
      save();
      notifyListeners();
    }
  }

  bool _autoPageTurn;
  bool get autoPageTurn => _autoPageTurn;
  set autoPageTurn(bool newValue) {
    if (_autoPageTurn != newValue) {
      _autoPageTurn = newValue;
      save();
      notifyListeners();
    }
  }

  int _prayerLength;
  int get prayerLength => _prayerLength;
  set prayerLength(int newValue) {
    if (_prayerLength != newValue) {
      _prayerLength = newValue;
      save();
      notifyListeners();
    }
  }

  bool _prayerSoundEnabled;
  bool get prayerSoundEnabled => _prayerSoundEnabled;
  set prayerSoundEnabled(bool newValue) {
    if (_prayerSoundEnabled != newValue) {
      _prayerSoundEnabled = newValue;
      save();
      notifyListeners();
    }
  }

  String _voiceChoice;
  String get voiceChoice => _voiceChoice;
  set voiceChoice(String newValue) {
    if (_voiceChoice != newValue) {
      _voiceChoice = newValue;
      save();
      notifyListeners();
    }
  }

  @override
  Json toJson() => _$SettingsDataToJson(this);

  Future<void> load() async {
    log.info('Reading user preferences from storage');
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonData = prefs.getString(_kUserSettings);

      final SettingsData newData;
      if (jsonData == null) {
        log.info(
          'No saved user preferences are found, initializing with defaults',
        );
        newData = SettingsData();
      } else {
        newData = SettingsData.fromJson(json.decode(jsonData));
      }
      _themeMode = newData.themeMode;
      _dnd = newData.dnd;
      _reminderNotifications = newData.reminderNotifications;
      _autoPageTurn = newData.autoPageTurn;
      _prayerLength = newData.prayerLength;
      _prayerSoundEnabled = newData.prayerSoundEnabled;
      _voiceChoice = newData.voiceChoice;
      notifyListeners();
    } catch (e, s) {
      log.severe('Error reading user preferences: $e', e, s);
      rethrow;
    }
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = json.encode(toJson());
    await prefs.setString(_kUserSettings, jsonString);
    log.info('User preferences are saved to storage');
  }
}
