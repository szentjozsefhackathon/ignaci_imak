import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:relative_time/relative_time.dart';

import '../data/versions.dart';
import '../data_handlers/data_manager.dart';

class DataSyncPage extends StatefulWidget {
  const DataSyncPage({super.key});

  @override
  State<DataSyncPage> createState() => _DataSyncPageState();
}

class _DataSyncPageState extends State<DataSyncPage> {
  Versions? _serverVersions;
  DateTime? _lastUpdate;

  @override
  void initState() {
    super.initState();
    _serverVersions = DataManager.instance.versions.cachedServerData;
    _lastUpdate = DataManager.instance.lastUpdateCheck;
  }

  Future<void> _checkForUpdates() async {
    setState(() => _serverVersions = null);
    final [v, _] = await Future.wait([
      DataManager.instance.checkForUpdates(stopOnError: true),
      Future.delayed(const Duration(seconds: 2)),
    ]);
    if (mounted) {
      setState(() {
        _serverVersions = v;
        _lastUpdate = DataManager.instance.lastUpdateCheck;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Adatok kezelése'),
          bottom: _serverVersions == null
              ? const PreferredSize(
                  preferredSize: Size.fromHeight(4),
                  child: LinearProgressIndicator(),
                )
              : null,
        ),
        body: RefreshIndicator(
          onRefresh: _checkForUpdates,
          child: ListView(
            children: [
              _DataSyncListItem(
                title: 'Imák',
                server: _serverVersions,
                getVersion: (v) => v.data,
                updater: null,
                onUpdated: () => setState(() {}),
              ),
              _DataSyncListItem(
                title: 'Képek',
                server: _serverVersions,
                getVersion: (v) => v.images,
                updater: DataManager.instance.updateImages,
                onUpdated: () => setState(() {}),
              ),
              _DataSyncListItem(
                title: 'Hangok',
                server: _serverVersions,
                getVersion: (v) => v.voices,
                updater: DataManager.instance.updateVoices,
                onUpdated: () => setState(() {}),
              ),
              if (_serverVersions != null && _lastUpdate != null)
                ListTile(
                  title: const Text('Verziók lekérdezve'),
                  subtitle: Text(
                    RelativeTime(
                      context,
                      timeUnits: [TimeUnit.minute, TimeUnit.hour, TimeUnit.day],
                    ).format(_lastUpdate!),
                  ),
                  onTap: _checkForUpdates,
                ),
              if (kDebugMode)
                ListTile(
                  title: const Text('Adatok törlése'),
                  enabled: _serverVersions != null,
                  onTap: _serverVersions == null
                      ? null
                      : () async {
                          setState(() => _serverVersions = null);
                          final dm = DataManager.instance;
                          await dm.versions.deleteLocalData();
                          await dm.images.deleteLocalData();
                          await dm.voices.deleteLocalData();
                          if (context.mounted) {
                            Navigator.pop(context);
                          }
                        },
                ),
            ],
          ),
        ),
      );
}

class _DataSyncListItem extends StatefulWidget {
  const _DataSyncListItem({
    required this.title,
    required this.getVersion,
    required this.updater,
    required this.server,
    required this.onUpdated,
  });

  final Versions? server;
  final String title;
  final String Function(Versions v) getVersion;
  final Future<bool> Function(Versions v)? updater;
  final VoidCallback onUpdated;

  @override
  State<_DataSyncListItem> createState() => _DataSyncListItemState();
}

class _DataSyncListItemState extends State<_DataSyncListItem> {
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    final updater = widget.updater;
    final server = widget.server;
    final local = DataManager.instance.versions.cachedLocalData;

    final Widget? subtitle;
    VoidCallback? onTap;

    if (server == null || local == null) {
      subtitle = null;
    } else {
      final serverVersion = widget.getVersion(server);
      if (serverVersion.isEmpty) {
        subtitle = const Text('Nem elérhető');
      } else {
        final localVersion = widget.getVersion(local);
        if (localVersion.isEmpty && updater != null) {
          if (_loading) {
            subtitle = const Text('Letöltés folyamatban...');
          } else {
            subtitle = const Text('Érintsd meg a letöltéshez');
            onTap = () async {
              setState(() => _loading = true);
              final success = await updater.call(server);
              if (!context.mounted) {
                return;
              }
              setState(() => _loading = false);
              if (success) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('${widget.title} letöltve')),
                );
                widget.onUpdated();
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('A letöltés nem sikerült')),
                );
              }
            };
          }
        } else if (localVersion != serverVersion && updater != null) {
          if (_loading) {
            subtitle = const Text('Frissítés folyamatban...');
          } else {
            subtitle = Text(
              'Frissítés elérhető: $localVersion -> $serverVersion',
            );
            onTap = () async {
              setState(() => _loading = true);
              final success = await updater(server);
              if (!context.mounted) {
                return;
              }
              setState(() => _loading = false);
              if (success) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('${widget.title} frissítve')),
                );
                widget.onUpdated();
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('A frissítés nem sikerült')),
                );
              }
            };
          }
        } else {
          subtitle = Text(localVersion);
        }
      }
    }
    return ListTile(
      title: Text(widget.title),
      subtitle: subtitle,
      enabled: !_loading && server != null && local != null,
      trailing: _loading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 3),
            )
          : null,
      onTap: onTap,
    );
  }
}
