import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:universal_io/universal_io.dart' show Platform;
import 'package:url_launcher/url_launcher.dart';

import '../data/database.dart';
import '../data/preferences.dart';
import '../routes.dart';
import '../services.dart';
import '../settings/dnd.dart';
import '../settings/focus_status.dart';
import 'prayer_page.dart';
import 'sync.dart';

class PrayerSettingsPage extends StatelessWidget {
  const PrayerSettingsPage({super.key, required this.prayer});

  final Prayer prayer;

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<Preferences>();

    return Scaffold(
      appBar: AppBar(title: Text(prayer.title)),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('Automatikus lapozás'),
            value: prefs.autoPageTurn,
            onChanged: prefs.setAutoPageTurn,
          ),
          if (Platform.isAndroid)
            DndSwitchListTile(value: prefs.dnd, onChanged: prefs.setDnd),
          if (Platform.isIOS)
            Selector<FocusStatus, bool?>(
              selector: (context, fs) => fs.status,
              builder: (context, isFocused, _) {
                if (isFocused == true) {
                  return const SizedBox.shrink();
                }
                return _FocusHint();
              },
            ),
          if (prayer.voiceOptions.isEmpty)
            const SwitchListTile(
              title: Text('Hang'),
              subtitle: Text('Nincs ehhez az imához'),
              value: false,
              onChanged: null,
            )
          else
            StreamBuilder(
              stream: context.read<Database>().mediaDao.watchVoiceOptionsOf(
                prayer,
              ),
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
                  groupValue: prefs.voiceChoice,
                  onChanged: (v) {
                    if (v != null) {
                      prefs.setVoiceChoice(v);
                    }
                  },
                  child: Column(
                    children: [
                      SwitchListTile(
                        title: const Text('Hang'),
                        value:
                            prefs.prayerSoundEnabled &&
                            (kIsWeb || data.isNotEmpty),
                        onChanged: kIsWeb || data.isNotEmpty
                            ? prefs.setPrayerSoundEnabled
                            : null,
                      ),
                      ...prayer.voiceOptions.mapIndexed((voiceIndex, voice) {
                        final available = kIsWeb || data[voice]!;
                        return RadioListTile(
                          title: Text(voice),
                          subtitle: available
                              ? null
                              : const Text('Nincs letöltve'),
                          value: available ? voice : '',
                          enabled: available && prefs.prayerSoundEnabled,
                          secondary: available || !prefs.prayerSoundEnabled
                              ? null
                              : _DownloadVoiceButton(
                                  prayer: prayer,
                                  voiceIndex: voiceIndex,
                                ),
                        );
                      }),
                    ],
                  ),
                );
              },
            ),
          ListTile(
            title: const Text('Ima hossza'),
            subtitle: Text('${prefs.prayerLength.inMinutes} perc'),
            trailing: const Icon(Icons.edit),
            onTap: () {
              showDialog(
                context: context,
                builder: (context) {
                  Duration length = prefs.prayerLength;
                  return AlertDialog(
                    title: const Text('Ima hossza'),
                    contentPadding: const EdgeInsets.fromLTRB(8, 32, 8, 0),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        StatefulBuilder(
                          builder: (context, setState) => Slider(
                            value: length.inMinutes.toDouble(),
                            min: prayer.minTime.inMinutes.toDouble(),
                            max: 60,
                            divisions: 60 - prayer.minTime.inMinutes,
                            label: '$length perc',
                            onChanged: (v) => setState(
                              () => length = Duration(minutes: v.toInt()),
                            ),
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
                        onPressed: () async {
                          await prefs.setPrayerLength(length);
                          if (context.mounted) {
                            Navigator.pop(context);
                          }
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
        onPressed: () async {
          final steps = await context.read<Database>().prayersDao.prayerStepsOf(
            prayer,
          );
          if (!context.mounted) {
            return;
          }
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) =>
                  PrayerPage(data: (prayer: prayer, steps: steps)),
            ),
          );
        },
        tooltip: 'Ima indítása',
        child: const Icon(Icons.play_arrow_rounded),
      ),
    );
  }
}

class _DownloadVoiceButton extends StatefulWidget {
  const _DownloadVoiceButton({required this.prayer, required this.voiceIndex});

  final Prayer prayer;
  final int voiceIndex;

  @override
  State<_DownloadVoiceButton> createState() => _DownloadVoiceButtonState();
}

class _DownloadVoiceButtonState extends State<_DownloadVoiceButton> {
  bool _downloading = false;

  @override
  Widget build(BuildContext context) {
    if (_downloading) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 12),
        child: ListItemProgressIndicator(),
      );
    }
    return IconButton(
      icon: const Icon(Icons.file_download_outlined),
      color: Theme.of(context).colorScheme.onSurface,
      onPressed: () async {
        setState(() => _downloading = true);
        final steps = await context.read<Database>().prayersDao.prayerStepsOf(
          widget.prayer,
        );
        if (!context.mounted) {
          return;
        }
        if (steps.isEmpty) {
          setState(() => _downloading = false);
          return;
        }
        await context.read<SyncService>().downloadVoices(
          voices: steps.map(
            (step) => (name: step.voices[widget.voiceIndex], etag: null),
          ),
        );
        if (!mounted) {
          return;
        }
        setState(() => _downloading = false);
      },
    );
  }
}

class _FocusHint extends StatelessWidget {
  _FocusHint();

  // Using the shortcut's identifier is more reliable than its name,
  final _shortcutId = '58ff4546eaa9497a93fdf9635011e64d';
  final _shortcutName = 'Ignáci fókusz';

  late final _shortcutLink = 'https://www.icloud.com/shortcuts/$_shortcutId';
  late final _runShortcutLink =
      'shortcuts://run-shortcut?name=${Uri.encodeComponent(_shortcutName)}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Selector<FocusStatus, FocusAuthorizationStatus?>(
      selector: (context, fs) => fs.authStatus,
      builder: (context, authStatus, _) {
        final colorScheme = theme.colorScheme;

        // User has explicitly denied permission.
        if (authStatus == FocusAuthorizationStatus.denied) {
          return Card(
            color: colorScheme.tertiaryContainer,
            margin: const EdgeInsets.all(12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
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
                    'Fókusz mód detektálásához engedélyre van szüksége az applikációnak, kapcsold be a jogosultságot a beállításokban.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onTertiaryContainer,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton(
                      onPressed: FocusStatus.openFocusSettings,
                      child: Text('Beállítások'),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        // For all other states (authorized, not determined, or unknown), show the standard hint.
        return Card(
          color: colorScheme.tertiaryContainer,
          margin: const EdgeInsets.all(12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 8,
              children: [
                Text(
                  'Az elmélyüléshez javasolt a Fókusz mód (pl. Ne zavarjanak) használata',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onTertiaryContainer,
                  ),
                ),
                Text(
                  'Kapcsold be a Fókusz módot, hogy semmi ne zavarjon imádság közben.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onTertiaryContainer,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton(
                      onPressed: () => launchUrl(Uri.parse(_runShortcutLink)),
                      child: const Text('Ignáci fókusz bekapcsolása'),
                    ),
                  ),
                ),
                Text(
                  'Ha a fenti gomb nem működik ("A(z) "$_shortcutName" parancs nem található"), add hozzá a parancsaidhoz a gomb segítségével.',
                  textAlign: TextAlign.left,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onTertiaryContainer,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton(
                      onPressed: () => launchUrl(
                        Uri.parse(_shortcutLink),
                        mode: LaunchMode.externalApplication,
                      ),
                      child: const Text('Parancs hozzáadása'),
                    ),
                  ),
                ),
                Text(
                  'A továbbiakban ezt a parancsot kedved szerint módosíthatod. Fontos hogy az "Ignáci fókusz bekapcsolása" gomb csak akkor működik, ha a parancs neve pontosan „$_shortcutName”.',
                  textAlign: TextAlign.left,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onTertiaryContainer,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
