import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart' show Consumer, SelectContext;
import 'package:relative_time/relative_time.dart';

import '../data/preferences.dart';
import '../data/versions.dart';
import '../services.dart';

class DataSyncPage extends StatelessWidget {
  const DataSyncPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Adatok kezelése')),
    body: Consumer<SyncService>(
      builder: (context, srv, _) => RefreshIndicator(
        onRefresh: srv.checkForUpdates,
        triggerMode: RefreshIndicatorTriggerMode.anywhere,
        child: ListView(
          children: [
            _DataSyncListItem(
              title: 'Imák',
              srv: srv,
              getVersion: (v) => v?.data,
              downloadAll: srv.downloadData,
              updateExisting: srv.downloadData,
              isSyncing: srv.status == SyncStatus.dataDownload,
            ),
            _DataSyncListItem(
              title: 'Képek',
              srv: srv,
              getVersion: (v) => v?.images,
              downloadAll: () => srv.downloadImages(stopOnError: true),
              updateExisting: () => srv.updateImages(stopOnError: true),
              isSyncing: srv.status == SyncStatus.imageDownload,
            ),
            _DataSyncListItem(
              title: 'Hangok',
              srv: srv,
              getVersion: (v) => v?.voices,
              downloadAll: () => srv.downloadVoices(stopOnError: true),
              updateExisting: () => srv.updateImages(stopOnError: true),
              isSyncing: srv.status == SyncStatus.voiceDownload,
            ),
            if (srv.latestVersions != null)
              ListTile(
                title: const Text('Legutóbbi szinkronizálás'),
                subtitle: Text(
                  RelativeTime(
                    context,
                    timeUnits: [TimeUnit.minute, TimeUnit.hour, TimeUnit.day],
                  ).format(srv.latestVersions!.timestamp.toLocal()),
                ),
                onTap: srv.checkForUpdates,
              ),
            if (kDebugMode)
              ListTile(
                title: const Text('Adatok törlése'),
                enabled:
                    srv.status == SyncStatus.idle && srv.latestVersions != null,
                onTap:
                    srv.status != SyncStatus.idle || srv.latestVersions == null
                    ? null
                    : () async {
                        await srv.deleteAllData();
                        if (context.mounted) {
                          Navigator.pop(context);
                        }
                      },
              ),
          ],
        ),
      ),
    ),
  );
}

class _DataSyncListItem extends StatelessWidget {
  const _DataSyncListItem({
    required this.title,
    required this.srv,
    required this.getVersion,
    required this.downloadAll,
    required this.updateExisting,
    required this.isSyncing,
  });

  final String title;
  final SyncService srv;
  final String? Function(Versions? v) getVersion;
  final Future<bool> Function() downloadAll;
  final Future<bool> Function() updateExisting;
  final bool isSyncing;

  @override
  Widget build(BuildContext context) {
    final serverVersion = getVersion(srv.latestVersions);
    final localVersion = getVersion(
      context.select<Preferences, Versions?>((p) => p.versions),
    );

    final Widget? subtitle;
    VoidCallback? onTap;
    if (localVersion == null || serverVersion == null) {
      subtitle = null;
    } else if (isSyncing && localVersion.isEmpty) {
      subtitle = const Text('Letöltés folyamatban...');
    } else if (isSyncing && localVersion.isNotEmpty) {
      subtitle = const Text('Frissítés folyamatban...');
    } else if (serverVersion.isNotEmpty &&
        localVersion.isEmpty &&
        serverVersion != localVersion) {
      subtitle = const Text('Érintsd meg a letöltéshez');
      onTap = () async {
        final success = await downloadAll.call();
        if (!context.mounted) {
          return;
        }
        if (success) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('$title letöltve')));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('A letöltés nem sikerült')),
          );
        }
      };
    } else if (serverVersion.isNotEmpty &&
        localVersion.isNotEmpty &&
        serverVersion != localVersion) {
      subtitle = Text('Frissítés elérhető: $localVersion -> $serverVersion');
      onTap = () async {
        final success = await updateExisting.call();
        if (!context.mounted) {
          return;
        }
        if (success) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('$title frissítve')));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('A frissítés nem sikerült')),
          );
        }
      };
    } else if (localVersion.isNotEmpty) {
      subtitle = Text(localVersion);
    } else {
      subtitle = const Text('Nincs letöltve');
    }

    return ListTile(
      title: Text(title),
      subtitle: subtitle,
      enabled: !isSyncing && onTap != null,
      trailing: isSyncing
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 3),
            )
          : null,
      onTap: onTap,
    );
  }
}
