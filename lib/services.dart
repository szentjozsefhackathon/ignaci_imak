import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show ChangeNotifier, kDebugMode;
import 'package:flutter/widgets.dart' show imageCache;
import 'package:logging/logging.dart';
import 'package:provider/provider.dart' show ListenableProxyProvider2;
import 'package:sentry_dio/sentry_dio.dart';
import 'package:sentry_flutter/sentry_flutter.dart' show SentryStatusCode;
import 'package:universal_io/universal_io.dart' show HttpHeaders, HttpStatus;

import 'data/database.dart';
import 'data/preferences.dart';
import 'data/versions.dart';
import 'env.dart';

enum SyncStatus {
  idle,
  versionCheck,
  updateAvailable,
  dataDownload,
  imageDownload,
  voiceDownload,
  delete,
}

class SyncService extends ChangeNotifier {
  SyncService() {
    _client = Dio(
      BaseOptions(
        baseUrl: Env.serverUrl,
        connectTimeout: const Duration(seconds: 3),
        receiveTimeout: const Duration(seconds: 5),
        followRedirects: false,
      ),
    );
    if (kDebugMode) {
      _client.interceptors.add(LogInterceptor(logPrint: _log.finer));
    }
    _client.addSentry(
      captureFailedRequests: true,
      failedRequestStatusCodes: [
        SentryStatusCode.range(400, 404),
        const SentryStatusCode.defaultRange(),
      ],
    );
  }

  static final _log = Logger('SyncService');
  late final Dio _client;
  late Preferences _prefs;
  late Database _db;

  SyncStatus _status = SyncStatus.idle;
  SyncStatus get status => _status;

  void _setStatus(SyncStatus s) {
    if (s != _status) {
      if (_status == SyncStatus.updateAvailable && s == SyncStatus.idle) {
        _log.warning('$_status -> $s');
      } else {
        _log.fine('$_status -> $s');
      }
      _status = s;
      notifyListeners();
    }
  }

  Versions? _latestVersions;
  Versions? get latestVersions => _latestVersions;

  void ignoreUpdate() {
    if (_status == SyncStatus.updateAvailable) {
      _setStatus(SyncStatus.idle);
    }
  }

  Future<void> deleteAllData() async {
    _setStatus(SyncStatus.delete);
    try {
      await Future.wait(_db.allTables.map((t) => t.deleteAll()));
      await _prefs.deleteVersions();
      _latestVersions = null;

      // trigger reloading images
      imageCache.clear();
      imageCache.clearLiveImages();
    } catch (e, s) {
      _log.severe('Failed to delete data', e, s);
      rethrow;
    } finally {
      _setStatus(SyncStatus.idle);
    }
  }

  Future<Response<T>?> _get<T>(String path, {String? etag}) => _client.get<T>(
    path,
    options: etag == null
        ? null
        : Options(headers: {HttpHeaders.ifNoneMatchHeader: etag}),
  );

  Future<bool> trySync({required bool stopOnError, bool? withMedia}) async {
    if (withMedia == null) {
      final c = await Connectivity().checkConnectivity();
      _log.fine(c);
      withMedia = !c.contains(ConnectivityResult.mobile);
    }
    if (!await checkForUpdates()) {
      return false;
    }
    if (_status == SyncStatus.updateAvailable) {
      if (!await downloadData()) {
        return false;
      }
      if (withMedia) {
        bool success = true;
        if (!await updateImages(stopOnError: stopOnError)) {
          if (stopOnError) {
            return false;
          }
          success = false;
        }
        if (!await updateVoices(stopOnError: stopOnError)) {
          if (stopOnError) {
            return false;
          }
          success = false;
        }
        return success;
      }
    }
    return true;
  }

  Future<bool> checkForUpdates() async {
    switch (_status) {
      case SyncStatus.idle:
      case SyncStatus.updateAvailable:
        // continue
        break;
      default:
        _log.warning('Cannot check for updates in $_status');
        return false;
    }
    _setStatus(SyncStatus.versionCheck);
    SyncStatus finalStatus = SyncStatus.idle;
    try {
      final response = await _get<Json>(Env.serverCheckVersionsPath);
      if (response?.data case final Json data
          when response?.statusCode == HttpStatus.ok) {
        final v = Versions.fromJson(data, timestamp: DateTime.now().toUtc());
        if (v != _latestVersions) {
          _log.fine('$_latestVersions -> $v');
          _latestVersions = v;
          if (_prefs.versions?.isUpdateAvailable(v) ?? true) {
            finalStatus = SyncStatus.updateAvailable;
          }
        }
        return true;
      } else {
        _log.warning('Version response: ${response?.data}');
      }
    } catch (e, s) {
      _log.severe('Failed to download versions', e, s);
      rethrow;
    } finally {
      _setStatus(finalStatus);
    }
    return false;
  }

  Future<bool> downloadData() async {
    switch (_status) {
      case SyncStatus.idle:
      case SyncStatus.updateAvailable:
        // continue
        break;
      default:
        _log.warning('Cannot download data in $_status');
        return false;
    }
    final v = _latestVersions;
    if (v == null) {
      _log.warning('Cannot download data without server versions');
      return false;
    }
    _setStatus(SyncStatus.dataDownload);
    try {
      final response = await _get<List>(Env.serverDownloadDataPath);
      if (response?.data case final List data
          when response?.statusCode == HttpStatus.ok) {
        final groups = <PrayerGroup>[];
        final prayers = <Prayer>[];
        final steps = <PrayerStep>[];
        for (final group in data) {
          final g = PrayerGroup.fromJson(group);
          groups.add(g);
          for (final prayer in group['prayers']) {
            final p = Prayer.fromJson(prayer, group: g);
            prayers.add(p);
            int stepIndex = 0;
            for (final step in prayer['steps']) {
              steps.add(PrayerStep.fromJson(step, prayer: p, index: stepIndex));
              stepIndex++;
            }
          }
        }
        await _db.transaction(() async {
          await _db.managers.prayerGroups.bulkCreate(
            (create) => groups.map(
              (g) => create(slug: g.slug, title: g.title, image: g.image),
            ),
            mode: InsertMode.insertOrReplace,
          );
          await _db.managers.prayers.bulkCreate(
            (create) => prayers.map(
              (p) => create(
                slug: p.slug,
                title: p.title,
                image: p.image,
                description: p.description,
                minTime: p.minTime,
                voiceOptions: p.voiceOptions,
                group: p.group,
              ),
            ),
            mode: InsertMode.insertOrReplace,
          );
          await _db.managers.prayerSteps.bulkCreate(
            (create) => steps.map(
              (s) => create(
                index: s.index,
                description: s.description,
                time: s.time,
                type: s.type,
                voices: s.voices,
                prayer: s.prayer,
              ),
            ),
            mode: InsertMode.insertOrReplace,
          );
        });
        await _prefs.setVersions(
          _prefs.versions?.copyWith(data: v.data) ??
              Versions.downloaded(v, data: true),
        );
        _setStatus(SyncStatus.idle);
        return true;
      } else {
        _log.warning('Data response: ${response?.data}');
      }
    } catch (e, s) {
      _log.severe('Failed to download data', e, s);
      rethrow;
    } finally {
      _setStatus(SyncStatus.idle);
    }
    return false;
  }

  Future<int?> _downloadImage({
    required String name,
    required String? etag,
  }) async {
    final response = await _get<Uint8List>(
      Env.serverImagePath(name),
      etag: etag,
    );
    if (response?.data case final Uint8List data) {
      await _db.managers.images.create(
        (create) => create(
          name: name,
          data: data,
          etag: Value.absentIfNull(
            response?.headers.value(HttpHeaders.etagHeader),
          ),
        ),
        mode: InsertMode.insertOrReplace,
      );
    }
    return response?.statusCode;
  }

  Future<bool> downloadImages({
    Map<String, String?>? imagesWithEtag,
    required bool stopOnError,
  }) async {
    switch (_status) {
      case SyncStatus.idle:
      case SyncStatus.updateAvailable:
        // continue
        break;
      default:
        _log.warning('Cannot download images in $_status');
        return false;
    }
    final v = _latestVersions;
    if (v == null) {
      _log.warning('Cannot download images without server versions');
      return false;
    }
    bool success = true;
    _setStatus(SyncStatus.imageDownload);
    try {
      if (imagesWithEtag == null) {
        final etagMap = Map.fromEntries(
          await _db.managers.images.map((i) => MapEntry(i.name, i.etag)).get(),
        );
        imagesWithEtag = Map.fromIterable([
          ...await _db.managers.prayerGroups.map((g) => g.image).get(),
          ...await _db.managers.prayers.map((p) => p.image).get(),
        ], value: (name) => etagMap[name]);
      }
      success = await _db.transaction(() async {
        bool success = true;
        for (final entry in imagesWithEtag!.entries) {
          final status = await _downloadImage(
            name: entry.key,
            etag: entry.value,
          );
          if (status != HttpStatus.ok && status != HttpStatus.notModified) {
            success = false;
            if (stopOnError) {
              break;
            }
          }
        }
        if (success) {
          await _prefs.setVersions(
            _prefs.versions?.copyWith(images: v.data) ??
                Versions.downloaded(v, images: true),
          );
        }
        return success;
      });
    } catch (e, s) {
      _log.severe('Failed to download images', e, s);
      rethrow;
    } finally {
      _setStatus(SyncStatus.idle);
    }
    return success;
  }

  Future<bool> updateImages({required bool stopOnError}) async {
    final downloaded = Map.fromEntries(
      await _db.managers.images.map((i) => MapEntry(i.name, i.etag)).get(),
    );
    return downloadImages(imagesWithEtag: downloaded, stopOnError: stopOnError);
  }

  Future<int?> _downloadVoice({
    required String name,
    required String? etag,
  }) async {
    final response = await _get<Uint8List>(
      Env.serverVoicePath(name),
      etag: etag,
    );
    if (response?.data case final Uint8List data) {
      await _db.managers.voices.create(
        (create) => create(
          name: name,
          data: data,
          etag: Value.absentIfNull(
            response?.headers.value(HttpHeaders.etagHeader),
          ),
        ),
        mode: InsertMode.insertOrReplace,
      );
    }
    return response?.statusCode;
  }

  Future<bool> downloadVoices({
    Map<String, String?>? voicesWithEtag,
    required bool stopOnError,
  }) async {
    switch (_status) {
      case SyncStatus.idle:
      case SyncStatus.updateAvailable:
        // continue
        break;
      default:
        _log.warning('Cannot download voices in $_status');
        return false;
    }
    final v = _latestVersions;
    if (v == null) {
      _log.warning('Cannot download voices without server versions');
      return false;
    }
    bool success = true;
    _setStatus(SyncStatus.voiceDownload);
    try {
      if (voicesWithEtag == null) {
        final etagMap = Map.fromEntries(
          await _db.managers.voices.map((v) => MapEntry(v.name, v.etag)).get(),
        );
        voicesWithEtag = Map.fromIterable([
          for (final step in await _db.managers.prayerSteps.get())
            ...step.voices,
        ], value: (name) => etagMap[name]);
      }
      success = await _db.transaction(() async {
        bool success = true;
        for (final entry in voicesWithEtag!.entries) {
          final status = await _downloadVoice(
            name: entry.key,
            etag: entry.value,
          );
          if (status != HttpStatus.ok && status != HttpStatus.notModified) {
            success = false;
            if (stopOnError) {
              break;
            }
          }
        }
        if (success) {
          await _prefs.setVersions(
            _prefs.versions?.copyWith(voices: v.data) ??
                Versions.downloaded(v, voices: true),
          );
        }
        return success;
      });
    } catch (e, s) {
      _log.severe('Failed to download images', e, s);
      rethrow;
    } finally {
      _setStatus(SyncStatus.idle);
    }
    return success;
  }

  Future<bool> updateVoices({required bool stopOnError}) async {
    final downloaded = Map.fromEntries(
      await _db.managers.voices.map((v) => MapEntry(v.name, v.etag)).get(),
    );
    return downloadVoices(voicesWithEtag: downloaded, stopOnError: stopOnError);
  }
}

class SyncServiceProvider
    extends ListenableProxyProvider2<Preferences, Database, SyncService> {
  SyncServiceProvider({super.key})
    : super(
        update: (ctx, prefs, db, srv) => (srv ?? SyncService())
          .._prefs = prefs
          .._db = db,
        dispose: (ctx, srv) => srv.dispose(),
      );
}
