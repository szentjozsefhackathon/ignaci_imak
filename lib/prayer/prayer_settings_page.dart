import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/prayer.dart';
import '../data/settings_data.dart';
import '../routes.dart';
import '../settings/dnd.dart';
import '../settings/focus_status.dart';
import 'prayer_page.dart';

// file-local helpers: true only on Android / iOS (and false on web/etc.)
bool get _isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
bool get _isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;


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
          if (_isAndroid)
            DndSwitchListTile(
              value: settings.dnd,
              onChanged: (v) => settings.dnd = v,
            ),
          FutureBuilder<bool?>(
            future: FocusStatus.getFocusStatus(),
            builder: (context, snapshot) {
              // hide on non-iOS or when app-level DND is enabled
              if (!_isIOS) return const SizedBox.shrink();

              // while loading, don't show the hint
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SizedBox.shrink();
              }

              final isFocused = snapshot.data;
              // if system Focus/DND is active, hide the hint
              if (isFocused == true) return const SizedBox.shrink();

              // otherwise show the hint (isFocused == false or unsupported/null)
              return const MeditationFocusHint();
            },
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
                return RadioGroup(
                  groupValue: settings.voiceChoice,
                  onChanged: (v) {
                    if (v != null) {
                      settings.voiceChoice = v;
                    }
                  },
                  child: Column(
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
                          enabled: settings.prayerSoundEnabled && available,
                        );
                      }),
                    ],
                  ),
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

class MeditationFocusHint extends StatefulWidget {
  const MeditationFocusHint({super.key});

  @override
  State<MeditationFocusHint> createState() => _MeditationFocusHintState();
}

class _MeditationFocusHintState extends State<MeditationFocusHint> {
  final String shortcutLink = 'https://www.icloud.com/shortcuts/284faea7689f424e84aea99c8bf95edd';
  final String runShortcutLink = 'shortcuts://run-shortcut?name=Fókusz%20beállítása';
  bool? _canRunShortcut;

  @override
  void initState() {
    super.initState();
    _checkIfShortcutCanBeRun();
  }

  Future<void> _checkIfShortcutCanBeRun() async {
    final canRun = await canLaunchUrl(Uri.parse(runShortcutLink));
    if (mounted) {
      setState(() {
        _canRunShortcut = canRun;
      });
    }
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool?>(
    valueListenable: FocusStatus.status,
    builder: (context, isFocused, _) {
      if (isFocused == true) {
        return const SizedBox.shrink(); // Focus is active
      }

      final theme = Theme.of(context);
      final colorScheme = theme.colorScheme;

      return Card(
        color: colorScheme.tertiaryContainer,
        margin: const EdgeInsets.all(12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Az elmélyüléshez javasolt a Fókusz mód (pl. Ne zavarjanak) használata',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onTertiaryContainer,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Kapcsold be a Fókusz módot, hogy semmi ne zavarjon imádság közben.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onTertiaryContainer,
                ),
              ),
              const SizedBox(height: 12),
              if (_canRunShortcut == true)
                ElevatedButton(
                  onPressed: () => launchUrl(Uri.parse(runShortcutLink)),
                  child: const Text('Ne zavarjanak bekapcsolása'),
                )
              else if (_canRunShortcut == false)
                ElevatedButton(
                  onPressed: () => launchUrl(Uri.parse(shortcutLink),
                      mode: LaunchMode.externalApplication),
                  child: const Text('Parancsikon letöltése'),
                ),
            ],
          ),
        ),
      );
    },
  );
}
