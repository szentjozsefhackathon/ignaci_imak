import 'dart:io' show Platform;

import 'package:app_settings/app_settings.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/settings_data.dart';
import '../notifications.dart';
import '../routes.dart';
import 'dnd.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

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
          if (!kIsWeb) ...[
            NotificationsSwitchListTile(
              value: settings.reminderNotifications,
              onChanged: (v) => settings.reminderNotifications = v,
            ),
            if (settings.reminderNotifications) ...[
              if (Platform.isAndroid || Platform.isIOS)
                ListTile(
                  title: const Text('Értesítések további beállításai'),
                  trailing: const Icon(Icons.open_in_new_rounded),
                  onTap: () => AppSettings.openAppSettings(
                    type: AppSettingsType.notification,
                  ),
                ),
              const NotificationsList(),
              if (kDebugMode)
                Selector<Notifications, bool?>(
                  selector: (context, notifications) =>
                      notifications.hasPermission,
                  builder: (context, hasPermission, _) => ListTile(
                    title: const Text('Értesítés teszt'),
                    enabled: hasPermission ?? false,
                    onTap: () => context.read<Notifications>().showTest(),
                  ),
                ),
            ],
            ListTile(
              title: const Text('Adatok kezelése'),
              onTap: () => Navigator.pushNamed(context, Routes.dataSync),
            ),
          ],
          ListTile(
            title: const Text('Impresszum'),
            onTap: () => Navigator.pushNamed(context, Routes.impressum),
          ),
        ],
      ),
    );
  }
}
