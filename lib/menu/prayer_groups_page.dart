import 'dart:async' show TimeoutException;

import 'package:app_settings/app_settings.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:sentry_flutter/sentry_flutter.dart' show SentryFlutter;
import 'package:universal_io/universal_io.dart';

import '../data/database.dart';
import '../prayer/prayer_card.dart';
import '../prayer/search.dart';
import '../routes.dart';
import '../services.dart';
import 'common.dart';

class PrayerGroupsPage extends StatefulWidget {
  const PrayerGroupsPage({super.key});

  @override
  State<PrayerGroupsPage> createState() => _PrayerGroupsPageState();
}

class _PrayerGroupsPageState extends State<PrayerGroupsPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _trySync());
    SentryFlutter.currentDisplay()?.reportFullyDisplayed();
  }

  Future<void> _trySync() async {
    final success = await context.read<SyncService>().trySync();
    if (kIsWeb || !success || !mounted) {
      return;
    }
    final groups = await context.read<Database>().prayersDao.getPrayerGroups();
    if (!mounted) {
      return;
    }
    await downloadMissingImages(context, groups.map((g) => g.image));
  }

  @override
  Widget build(BuildContext context) => StreamBuilder(
    stream: context.read<Database>().prayersDao.watchPrayerGroups(),
    builder: (context, snapshot) {
      final Widget body;
      if (snapshot.hasError) {
        body = _buildError(snapshot.error!);
      } else if (snapshot.connectionState == ConnectionState.waiting) {
        body = const Center(child: CircularProgressIndicator());
      } else {
        final items = snapshot.data!;
        body = Column(
          children: [
            Selector<SyncService, SyncStatus>(
              selector: (context, srv) => srv.status,
              builder: (context, syncStatus, _) => switch (syncStatus) {
                SyncStatus.updateAvailable => _buildSyncNotification(
                  'A korábban letöltött adatok egy újabb verziója elérhető, szeretnéd most frissíteni ezeket?',
                  'Frissítés',
                  () => context.read<SyncService>().ignoreUpdate(),
                ),
                SyncStatus.mediaNotComplete => _buildSyncNotification(
                  'Le szeretnéd most tölteni az összes imához tartozó képet és hangot?\n\nKésőbb a beállítások oldalról is megteheted ezt.',
                  'Letöltés',
                  () => context.read<SyncService>().ignoreMediaNotComplete(),
                ),
                _ => const SizedBox(),
              },
            ),
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  mainAxisExtent: 200,
                  mainAxisSpacing: 8,
                  maxCrossAxisExtent: 200,
                  crossAxisSpacing: 8,
                ),
                padding: const EdgeInsets.all(16),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  return PrayerCard(
                    title: item.title,
                    image: item.image,
                    onTap: () => Navigator.pushNamed(
                      context,
                      Routes.prayers(item),
                      arguments: item,
                    ),
                  );
                },
              ),
            ),
          ],
        );
      }
      return Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('Ignáci imák'),
          titleSpacing: NavigationToolbar.kMiddleSpacing,
          actions: [
            if (snapshot.data?.isNotEmpty ?? false)
              const PrayerSearchIconButton(),
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: 'Beállítások',
              onPressed: () => Navigator.pushNamed(context, Routes.settings),
            ),
          ],
        ),
        body: body,
      );
    },
  );

  Widget _buildError(Object error) => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      spacing: 16,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Hiba történt',
          style: Theme.of(context).textTheme.bodyLarge,
          textAlign: TextAlign.center,
        ),
        Text(switch (error) {
          final SocketException e when e.osError?.errorCode == 101 =>
            'Nincs internetkapcsolat',
          final TimeoutException e =>
            e.message ??
                'Időtúllépés${e.duration == null ? '' : ' (${e.duration})'}',
          _ => error.toString(),
        }, textAlign: TextAlign.center),
        if (error case final SocketException e
            when e.osError?.errorCode == 101 && Platform.isAndroid)
          Center(
            child: ElevatedButton(
              onPressed: () =>
                  AppSettings.openAppSettings(type: AppSettingsType.wireless),
              child: const Text('Beállítások'),
            ),
          ),
        Center(
          child: ElevatedButton(onPressed: _trySync, child: const Text('Újra')),
        ),
      ],
    ),
  );

  Widget _buildSyncNotification(
    String message,
    String positiveButton,
    VoidCallback onHidePressed,
  ) => MaterialBanner(
    content: Text(message),
    actions: [
      TextButton(onPressed: onHidePressed, child: const Text('Elrejtés')),
      TextButton(
        onPressed: () => Navigator.pushNamed(context, Routes.dataSync),
        child: Text(positiveButton),
      ),
    ],
    backgroundColor: Colors.transparent,
    dividerColor: Colors.transparent,
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
  );
}
