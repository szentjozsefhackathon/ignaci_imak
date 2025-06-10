import 'dart:async';
import 'dart:io' show Platform;

import 'package:alarm/alarm.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../alarm_service/screens/edit_alarm.dart';
import '../alarm_service/screens/ring.dart';
import '../alarm_service/services/permission.dart';
import '../alarm_service/widgets/tile.dart';
import '../data/settings_data.dart';
import '../routes.dart';
import 'dnd.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  List<AlarmSettings> _alarms = [];

  static final _alarmRingStream = Alarm.ringStream.stream.asBroadcastStream();
  static final _alarmUpdateStream = Alarm.updateStream.stream
      .asBroadcastStream();

  late final StreamSubscription<AlarmSettings> _ringSubscription;
  late final StreamSubscription<int> _updateSubscription;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      AlarmPermissions.checkNotificationPermission();
      if (Platform.isAndroid) {
        AlarmPermissions.checkAndroidScheduleExactAlarmPermission();
      }
    }
    _ringSubscription = _alarmRingStream.listen(_navigateToRingScreen);
    _updateSubscription = _alarmUpdateStream.listen((_) => _loadAlarms());
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAlarms());
  }

  @override
  void dispose() {
    _ringSubscription.cancel();
    _updateSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsData>();

    return Scaffold(
      appBar: AppBar(title: const Text('Beállítások')),
      body: ListView(
        children: [
          if (!kIsWeb)
            DndSwitchListTile(
              value: settings.dnd,
              onChanged: (v) => settings.dnd = v,
            ),
          if (settings.dnd)
            ListTile(
              title: const Text('Ne zavarjanak további beállításai'),
              trailing: const Icon(Icons.open_in_new_rounded),
              onTap: () => context.read<DndProvider>().openSettings(),
            ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text('Téma'),
          ),
          ...ThemeMode.values.map(
            (mode) => RadioListTile(
              title: Text(switch (mode) {
                ThemeMode.system => 'rendszer',
                ThemeMode.light => 'világos',
                ThemeMode.dark => 'sötét',
                // ignore: require_trailing_commas
              }),
              value: mode,
              groupValue: settings.themeMode,
              onChanged: (v) {
                if (v != null) {
                  settings.themeMode = v;
                }
              },
            ),
          ),
          if (!kIsWeb)
            SwitchListTile(
              title: const Text('Napi emlékeztetők'),
              value: settings.dailyNotifier,
              onChanged: (v) {
                settings.dailyNotifier = v;
                if (!v) {
                  Alarm.stopAll();
                }
              },
            ),
          if (!kIsWeb)
            ListTile(
              title: const Text('Emlékeztető hozzáadása'),
              leading: const Icon(Icons.add_rounded),
              // TODO: do we need dailyNotifierTime (we have alarms)?
              //subtitle: Text(settings.dailyNotifierTime.format(context)),
              enabled: settings.dailyNotifier,
              onTap: () => _navigateToAlarmScreen(null),
            ),
          if (_alarms.isNotEmpty)
            SafeArea(
              child: Column(
                children: _alarms
                    .map(
                      (a) => AlarmTile(
                        key: Key(a.id.toString()),
                        title: TimeOfDay(
                          hour: a.dateTime.hour,
                          minute: a.dateTime.minute,
                        ).format(context),
                        onPressed: () => _navigateToAlarmScreen(a),
                        onDismissed: () async {
                          await Alarm.stop(a.id);
                          await _loadAlarms();
                        },
                      ),
                    )
                    .toList(),
              ),
            ),
          if (!kIsWeb)
            ListTile(
              title: const Text('Adatok kezelése'),
              onTap: () => Navigator.pushNamed(context, Routes.dataSync),
            ),
          ListTile(
            title: const Text('Impresszum'),
            onTap: () => Navigator.pushNamed(context, Routes.impressum),
          ),
        ],
      ),
    );
  }

  Future<void> _loadAlarms() async {
    final updatedAlarms = await Alarm.getAlarms();
    updatedAlarms.sort((a, b) => a.dateTime.isBefore(b.dateTime) ? 0 : 1);
    setState(() => _alarms = updatedAlarms);
  }

  Future<void> _navigateToRingScreen(AlarmSettings alarmSettings) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (context) => AlarmRingScreen(alarmSettings: alarmSettings),
      ),
    );
    unawaited(_loadAlarms());
  }

  Future<void> _navigateToAlarmScreen(AlarmSettings? settings) async {
    final res = await showModalBottomSheet<bool?>(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.85,
        child: AlarmEditScreen(alarmSettings: settings),
      ),
    );

    if (res != null && res == true) unawaited(_loadAlarms());
  }
}
