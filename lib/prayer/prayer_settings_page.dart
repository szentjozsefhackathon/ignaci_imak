import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/prayer.dart';
import '../data/settings_data.dart';
import '../routes.dart';
import '../settings/dnd.dart';
import 'prayer_page.dart';

class PrayerSettingsPage extends StatefulWidget {
  const PrayerSettingsPage({super.key, required this.prayer});

  final Prayer prayer;

  @override
  State<PrayerSettingsPage> createState() => _PrayerSettingsPageState();
}

class _PrayerSettingsPageState extends State<PrayerSettingsPage> {
  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsData>();

    return Scaffold(
      appBar: AppBar(title: Text(widget.prayer.title)),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('Automatikus lapozás'),
            value: settings.autoPageTurn,
            onChanged: (v) => settings.autoPageTurn = v,
          ),
          if (!kIsWeb)
            DndSwitchListTile(
              value: settings.dnd,
              onChanged: (v) => settings.dnd = v,
            ),
          if (widget.prayer.voiceOptions.isEmpty)
            const SwitchListTile(
              title: Text('Hang'),
              subtitle: Text('Nincs ehhez az imához'),
              value: false,
              onChanged: null,
            )
          else
            FutureBuilder(
              future: widget.prayer.availableVoiceOptions,
              builder: (context, snapshot) {
                final data = snapshot.data;
                if (data == null) {
                  return const SwitchListTile(
                    title: Text('Hang'),
                    subtitle: Text('Betöltés...'),
                    value: false,
                    onChanged: null,
                  );
                }
                return Column(
                  children: [
                    SwitchListTile(
                      title: const Text('Hang'),
                      value: settings.prayerSoundEnabled && data.isNotEmpty,
                      onChanged: data.isNotEmpty
                          ? (v) => settings.prayerSoundEnabled = v
                          : null,
                    ),
                    ...widget.prayer.voiceOptions.map((voice) {
                      final available = data.contains(voice);
                      return RadioListTile(
                        title: Text(voice),
                        subtitle: available
                            ? null
                            : const Text('Nincs letöltve'),
                        value: voice,
                        groupValue: settings.voiceChoice,
                        onChanged: settings.prayerSoundEnabled && available
                            ? (String? v) {
                                if (v != null) {
                                  settings.voiceChoice = v;
                                }
                              }
                            : null,
                      );
                    }),
                  ],
                );
              },
            ),
          ListTile(
            title: const Text('Ima hossza'),
            subtitle: Text('${settings.prayerLength} perc'),
            trailing: const Icon(Icons.edit),
            onTap: () {
              showDialog(
                context: context,
                builder: (context) {
                  var length = settings.prayerLength;
                  return AlertDialog(
                    title: const Text('Ima hossza'),
                    contentPadding: const EdgeInsets.fromLTRB(8, 32, 8, 0),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        StatefulBuilder(
                          builder: (context, setState) => Slider(
                            value: length.toDouble(),
                            min: widget.prayer.minTimeInMinutes.toDouble(),
                            max: 60,
                            divisions: 60 - widget.prayer.minTimeInMinutes,
                            label: '$length perc',
                            onChanged: (v) =>
                                setState(() => length = v.toInt()),
                          ),
                        ),
                      ],
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Mégsem'),
                      ),
                      TextButton(
                        onPressed: () {
                          settings.prayerLength = length;
                          Navigator.pop(context);
                        },
                        child: const Text('Beállítás'),
                      ),
                    ],
                  );
                },
              );
            },
          ),
          ListTile(
            title: const Text('További beállítások'),
            onTap: () => Navigator.pushNamed(context, Routes.settings),
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PrayerPage(prayer: widget.prayer),
          ),
        ),
        tooltip: 'Ima indítása',
        child: const Icon(Icons.play_arrow_rounded),
      ),
    );
  }
}
