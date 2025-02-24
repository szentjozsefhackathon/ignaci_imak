import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../data/common.dart';
import '../data/prayer_group.dart';
import '../data_handlers/data_manager.dart';
import '../prayer/prayer_image.dart';
import '../routes.dart';

class PrayerGroupsPage extends StatefulWidget {
  const PrayerGroupsPage({super.key});

  @override
  State<PrayerGroupsPage> createState() => _PrayerGroupsPageState();
}

enum _DataSyncNotification { none, download, update }

class _PrayerGroupsPageState extends State<PrayerGroupsPage> {
  DataList<PrayerGroup>? _items;
  _DataSyncNotification _notification = _DataSyncNotification.none;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
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
      final error = e.toString();
      debugPrintStack(label: error, stackTrace: s);
      if (!mounted) {
        return;
      }
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Hiba történt'),
          content: Text(error),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Bezárás'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final Widget body;
    final items = _items?.items;
    if (items == null) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      final grid = GridView.builder(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 350,
          mainAxisSpacing: 8,
          mainAxisExtent: 200,
          crossAxisSpacing: 8,
        ),
        padding: const EdgeInsets.all(8),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          return Card(
            semanticContainer: true,
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
                  Positioned.fill(
                    child: PrayerImage(name: item.image),
                  ),
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
        title: const Text('Ignáci imák'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
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
  ) =>
      Column(
        children: [
          MaterialBanner(
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => setState(
                  () => _notification = _DataSyncNotification.none,
                ),
                child: const Text('Elrejtés'),
              ),
              TextButton(
                onPressed: () async {
                  setState(() => _notification = _DataSyncNotification.none);
                  await Navigator.pushNamed(context, Routes.dataSync);
                  if (mounted) {
                    _loadData();
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
