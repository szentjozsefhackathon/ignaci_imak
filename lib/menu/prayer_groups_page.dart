import 'dart:async' show TimeoutException;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../data/common.dart';
import '../data/prayer_group.dart';
import '../data_handlers/data_manager.dart';
import '../prayer/prayer_image.dart';
import '../prayer/search.dart';
import '../routes.dart';

class PrayerGroupsPage extends StatefulWidget {
  const PrayerGroupsPage({super.key});

  @override
  State<PrayerGroupsPage> createState() => _PrayerGroupsPageState();
}

enum _DataSyncNotification { none, download, update }

class _PrayerGroupsPageState extends State<PrayerGroupsPage> {
  DataList<PrayerGroup>? _items;
  Object? _error;
  _DataSyncNotification _notification = _DataSyncNotification.none;

  @override
  void initState() {
    super.initState();
    _loadData();
    SentryFlutter.currentDisplay()?.reportFullyDisplayed();
  }

  Future<void> _loadData() async {
    if (!mounted) {
      return;
    }
    setState(() {
      _error = null;
      _items = null;
    });

    // trigger reloading images
    imageCache.clear();
    imageCache.clearLiveImages();

    try {
      if (!kIsWeb) {
        final hasData = await DataManager.instance.versions.localDataExists;
        final server = await DataManager.instance.checkForUpdates(
          stopOnError: true,
        );
        if (!hasData) {
          // there was no local data before checkForUpdates
          _notification = _DataSyncNotification.download;
        } else {
          final local = await DataManager.instance.versions.data;
          if (local.isUpdateAvailable(server)) {
            _notification = _DataSyncNotification.update;
          }
        }
      }

      final prayerGroups = await DataManager.instance.prayerGroups.data;
      if (mounted) {
        setState(() => _items = prayerGroups);
      }
    } catch (e, s) {
      debugPrintStack(label: e.toString(), stackTrace: s);
      if (!mounted) {
        return;
      }
      setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (_error != null) {
      body = Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          spacing: 16,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Hiba történt', style: Theme.of(context).textTheme.bodyLarge),
            Text(switch (_error) {
              final TimeoutException timeout =>
                timeout.message ??
                    'Időtúllépés${timeout.duration == null ? '' : ' (${timeout.duration})'}',
              _ => _error.toString(),
            }),
            ElevatedButton(onPressed: _loadData, child: const Text('Újra')),
          ],
        ),
      );
    } else if (_items?.items == null) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      final items = _items!.items;
      final grid = GridView.builder(
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
          return Card(
            clipBehavior: Clip.antiAliasWithSaveLayer,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            elevation: 4,
            child: InkWell(
              onTap: () => Navigator.pushNamed(
                context,
                Routes.prayers(item),
                arguments: item,
              ),
              child: Stack(
                children: [
                  Positioned.fill(child: PrayerImage(name: item.image)),
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      color: Colors.black54,
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        item.title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );

      body = switch (_notification) {
        _DataSyncNotification.none => grid,
        _DataSyncNotification.download => _buildSyncNotification(
          grid,
          'Le szeretnéd most tölteni az imákhoz tartozó képeket és hangokat?\n\nKésőbb a beállítások oldalról is megteheted ezt.',
          'Letöltés',
        ),
        _DataSyncNotification.update => _buildSyncNotification(
          grid,
          'Szeretnéd most frissíteni az imákhoz tartozó képeket és/vagy hangokat?',
          'Frissítés',
        ),
      };
    }

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Ignáci imák'),
        titleSpacing: NavigationToolbar.kMiddleSpacing,
        actions: [
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
  }

  Widget _buildSyncNotification(
    Widget content,
    String message,
    String positiveButton,
  ) => Column(
    children: [
      MaterialBanner(
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () =>
                setState(() => _notification = _DataSyncNotification.none),
            child: const Text('Elrejtés'),
          ),
          TextButton(
            onPressed: () async {
              setState(() => _notification = _DataSyncNotification.none);
              await Navigator.pushNamed(context, Routes.dataSync);
              if (mounted) {
                await _loadData();
              }
            },
            child: Text(positiveButton),
          ),
        ],
        backgroundColor: Colors.transparent,
        dividerColor: Colors.transparent,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      ),
      Expanded(child: content),
    ],
  );
}
