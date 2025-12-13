import 'package:app_settings/app_settings.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:universal_io/universal_io.dart' show Platform;

import '../data/settings_data.dart';
import '../notifications.dart';
import '../routes.dart';
import '../theme.dart' show AppThemeMode;
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
          if (!kIsWeb) ...[
            if (Platform.isAndroid)
              DndSwitchListTile(
                value: settings.dnd,
                onChanged: (v) => settings.dnd = v,
              ),
            if (Platform.isAndroid && settings.dnd)
              ListTile(
                title: const Text('Ne zavarjanak további beállításai'),
                trailing: const Icon(Icons.open_in_new_rounded),
                onTap: () => context.read<DndProvider>().openSettings(),
              ),
          ],
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text('Téma'),
          ),
          RadioGroup(
            groupValue: settings.themeMode,
            onChanged: (v) {
              if (v != null) {
                settings.themeMode = v;
              }
            },
            child: Column(
              children: [
                for (final mode in AppThemeMode.values)
                  RadioListTile(
                    title: Text(switch (mode) {
                      AppThemeMode.system => 'Rendszer',
                      AppThemeMode.light => 'Világos',
                      AppThemeMode.dark => 'Sötét',
                      AppThemeMode.oled => 'Fekete (OLED)',
                    }),
                    value: mode,
                  ),
              ],
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
          if (Sentry.isEnabled)
            ListTile(
              title: const Text('Visszajelzés'),
              onTap: () => SentryFeedbackWidget.show(context),
            ),
          ListTile(
            title: const Text('Impresszum'),
            onTap: () => Navigator.pushNamed(context, Routes.impressum),
          ),
        ],
      ),
    );
  }
}
