import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart' show Consumer, SelectContext, Selector;
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
              stats: null,
              getVersion: (v) => v?.data,
              downloadAll: srv.downloadData,
              updateExisting: srv.downloadData,
              isSyncing: srv.status == SyncStatus.dataDownload,
            ),
            _DataSyncListItem(
              title: 'Képek',
              srv: srv,
              stats: (all: srv.allImages, downloaded: srv.downloadedImages),
              getVersion: (v) => v?.images,
              downloadAll: () => srv.downloadImages(stopOnError: true),
              updateExisting: () => srv.updateImages(stopOnError: true),
              isSyncing: srv.status == SyncStatus.imageDownload,
            ),
            _DataSyncListItem(
              title: 'Hangok',
              srv: srv,
              stats: (all: srv.allVoices, downloaded: srv.downloadedVoices),
              getVersion: (v) => v?.voices,
              downloadAll: () => srv.downloadVoices(stopOnError: true),
              updateExisting: () => srv.updateImages(stopOnError: true),
              isSyncing: srv.status == SyncStatus.voiceDownload,
            ),
            if (srv.latestVersions != null)
              Selector<SyncService, SyncStatus>(
                selector: (context, srv) => srv.status,
                builder: (context, status, _) => ListTile(
                  title: const Text('Legutóbbi szinkronizálás'),
                  subtitle: status == SyncStatus.versionCheck
                      ? null
                      : Text(
                          RelativeTime(
                            context,
                            timeUnits: [
                              TimeUnit.minute,
                              TimeUnit.hour,
                              TimeUnit.day,
                            ],
                          ).format(srv.latestVersions!.timestamp.toLocal()),
                        ),
                  trailing: status == SyncStatus.versionCheck
                      ? const _DataSyncListItemProgressIndicator()
                      : const Icon(Icons.sync_rounded),
                  onTap: status == SyncStatus.versionCheck
                      ? null
                      : srv.checkForUpdates,
                ),
              ),
            if (kDebugMode)
              Selector<SyncService, bool>(
                selector: (context, srv) =>
                    (srv.status == SyncStatus.idle ||
                        srv.status == SyncStatus.updateAvailable) &&
                    srv.latestVersions != null,
                builder: (context, canDelete, _) => ListTile(
                  title: const Text('Adatok törlése'),
                  enabled: canDelete,
                  trailing: canDelete
                      ? null
                      : const Icon(Icons.delete_outline_rounded),
                  onTap: canDelete
                      ? () async {
                          await srv.deleteAllData();
                          if (context.mounted) {
                            Navigator.pop(context);
                          }
                        }
                      : null,
                ),
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
    required this.stats,
    required this.getVersion,
    required this.downloadAll,
    required this.updateExisting,
    required this.isSyncing,
  });

  final String title;
  final SyncService srv;
  final String? Function(Versions? v) getVersion;
  final ({int all, int downloaded})? stats;
  final Future<bool> Function() downloadAll;
  final Future<bool> Function() updateExisting;
  final bool isSyncing;

  @override
  Widget build(BuildContext context) {
    final serverVersion = getVersion(srv.latestVersions);
    final localVersion = getVersion(
      context.select<Preferences, Versions?>((p) => p.versions),
    );
    final hasServer = serverVersion?.isNotEmpty ?? false;
    final hasLocal = localVersion?.isNotEmpty ?? false;

    Widget? trailing;
    final Text? subtitle;
    VoidCallback? onTap;
    if (isSyncing) {
      trailing = const _DataSyncListItemProgressIndicator();
      subtitle = hasLocal
          ? const Text('Frissítés folyamatban...')
          : const Text('Letöltés folyamatban...');
    } else if (hasServer && !hasLocal) {
      trailing = const Icon(Icons.file_download_outlined);
      subtitle = kDebugMode
          ? Text('Érintsd meg a letöltéshez ($serverVersion)')
          : const Text('Érintsd meg a letöltéshez');
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
    } else if (hasServer && hasLocal && serverVersion != localVersion) {
      trailing = const Icon(Icons.sync_rounded);
      subtitle = kDebugMode
          ? Text('Frissítés elérhető ($localVersion -> $serverVersion)')
          : const Text('Frissítés elérhető, érintsd meg a letöltéshez');
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
    } else if (hasLocal) {
      trailing = const Icon(Icons.check_rounded);
      subtitle = Text(
        '${(stats?.all == stats?.downloaded ? 'Letöltve' : '${stats!.all}/${stats!.downloaded} letöltve')}${kDebugMode ? ' ($localVersion)' : ''}',
      );
    } else {
      subtitle = null;
    }

    return ListTile(
      title: Text(title),
      subtitle: subtitle,
      enabled: !isSyncing,
      trailing: trailing,
      onTap: onTap,
    );
  }
}

class _DataSyncListItemProgressIndicator extends StatelessWidget {
  const _DataSyncListItemProgressIndicator();

  @override
  Widget build(BuildContext context) => const SizedBox(
    width: 24,
    height: 24,
    child: CircularProgressIndicator(strokeWidth: 3),
  );
}
