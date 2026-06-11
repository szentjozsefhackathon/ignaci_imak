import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart'
    show ChangeNotifier, kDebugMode, kIsWeb;
import 'package:flutter/widgets.dart' show imageCache;
import 'package:logging/logging.dart';
import 'package:provider/provider.dart' show ChangeNotifierProxyProvider2;
import 'package:sentry_dio/sentry_dio.dart';
import 'package:sentry_flutter/sentry_flutter.dart' show SentryStatusCode;
import 'package:universal_io/universal_io.dart' show HttpHeaders, HttpStatus;

import '../data/database.dart';
import '../data/preferences.dart';
import '../data/versions.dart';
import '../env.dart';

enum SyncStatus {
  idle,
  versionCheck,
  updateAvailable,
  dataDownload,
  mediaNotComplete,
  imageDownload,
  voiceDownload,
  delete,
}

typedef MediaWithEtag = ({String name, String? etag});
typedef _DownloadResult = ({
  MediaWithEtag file,
  int? statusCode,
  Uint8List? data,
  String? etag,
  Object? error,
});

class SyncService extends ChangeNotifier {
  SyncService() {
    _client = Dio(
      BaseOptions(
        baseUrl: Env.serverUrl,
        connectTimeout: const Duration(seconds: 3),
        receiveTimeout: const Duration(seconds: 5),
        followRedirects: false,
        validateStatus: (status) =>
            status != null && !_kFailedStatusCodeRange.isInRange(status),
      ),
    );
    if (kDebugMode) {
      _client.interceptors.add(
        LogInterceptor(
          request: false,
          responseHeader: false,
          logPrint: _log.finer,
        ),
      );
    }
    _client.addSentry(
      captureFailedRequests: true,
      failedRequestStatusCodes: [_kFailedStatusCodeRange],
    );
  }

  static final _log = Logger('SyncService');
  static final _kFailedStatusCodeRange = SentryStatusCode.range(
    HttpStatus.badRequest,
    HttpStatus.networkConnectTimeoutError,
  );
  late final Dio _client;
  late Preferences _prefs;
  late Database _db;

  SyncStatus _status = SyncStatus.idle;
  SyncStatus get status => _status;

  void _setStatus(SyncStatus s, {bool notify = true}) {
    if (s != _status) {
      if (_status != SyncStatus.idle && s == SyncStatus.idle) {
        _log.warning('$_status -> $s');
      } else {
        _log.fine('$_status -> $s');
      }
      _status = s;
      if (notify) {
        notifyListeners();
      }
    }
  }

  Versions? _latestVersions;
  Versions? get latestVersions => _latestVersions;

  int _allImages = 0, _allVoices = 0;
  int get allImages => _allImages;
  int get allVoices => _allVoices;

  int _downloadedImages = 0, _downloadedVoices = 0;
  int get downloadedImages => _downloadedImages;
  int get downloadedVoices => _downloadedVoices;

  int get downloadableImages => _allImages - _downloadedImages;
  int get downloadableVoices => _allVoices - _downloadedVoices;

  Future<void> updateStats() async {
    if (kIsWeb) {
      return;
    }

    _allImages =
        await _db.managers.prayerGroups.count() +
        await _db.managers.prayers.count();
    _allVoices = 0;
    for (final step in await _db.managers.prayerSteps.get()) {
      _allVoices += step.voices.length;
    }
    _allVoices += 1; // csengo.mp3

    _downloadedImages = await _db.managers.images.count();
    _downloadedVoices = await _db.managers.voices.count();
    _log.fine(
      'Stats: $_allImages/$_downloadedImages image(s) and $_allVoices/$_downloadedVoices voice(s) downloaded',
    );

    if (downloadableImages > 0 || downloadableVoices > 0) {
      _setStatus(SyncStatus.mediaNotComplete, notify: false);
    }
    notifyListeners();
  }

  void ignoreUpdate() {
    if (_status == SyncStatus.updateAvailable) {
      _latestVersions = _prefs.versions;
      _setStatus(SyncStatus.idle);
    }
  }

  void ignoreMediaNotComplete() {
    if (_status == SyncStatus.mediaNotComplete) {
      _setStatus(SyncStatus.idle);
    }
  }

  Future<void> deleteAllData() async {
    _setStatus(SyncStatus.delete);
    try {
      await Future.wait(_db.allTables.map((t) => t.deleteAll()));
      await _prefs.deleteVersions();
      _latestVersions = null;

      imageCache.clear();
      imageCache.clearLiveImages();
    } catch (e, s) {
      _log.severe('Failed to delete data', e, s);
      rethrow;
    } finally {
      _setStatus(SyncStatus.idle);
    }
  }

  Future<Response<T>?> _get<T>(
    String path, {
    String? etag,
    ResponseType? responseType,
  }) => _client.get<T>(
    path,
    options: Options(
      headers: {HttpHeaders.ifNoneMatchHeader: ?etag},
      responseType: responseType,
    ),
  );

  SyncStatus get _isStatusIdleOrUpdate {
    final v = _latestVersions;
    if (v != null && (_prefs.versions?.isUpdateAvailable(v) ?? true)) {
      return SyncStatus.updateAvailable;
    }
    return SyncStatus.idle;
  }

  Future<bool> trySync({bool stopOnError = true, bool? withMedia}) async {
    if (kIsWeb) {
      withMedia = false;
    } else if (withMedia == null) {
      final c = await Connectivity().checkConnectivity();
      _log.fine(c);
      withMedia = !c.contains(ConnectivityResult.mobile);
    }
    if (!await _checkForUpdates()) {
      return false;
    }
    bool success = true;
    if (_status == SyncStatus.updateAvailable) {
      if (!await downloadData()) {
        return false;
      }
      if (withMedia) {
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
      }
    }
    if (success) {
      await updateStats();
    }
    return success;
  }

  Future<void> checkForUpdates() async {
    if (!await _checkForUpdates()) {
      return;
    }
    await updateStats();
  }

  Future<bool> _checkForUpdates() async {
    switch (_status) {
      case SyncStatus.idle:
      case SyncStatus.updateAvailable:
      case SyncStatus.mediaNotComplete:
        break;
      default:
        _log.warning('Cannot check for updates in $_status');
        return false;
    }
    bool success = false;
    SyncStatus finalStatus = _status;
    _setStatus(SyncStatus.versionCheck);
    try {
      final response = await _get<Json>(Env.serverCheckVersionsPath);
      if (response?.data case final Json data
          when response?.statusCode == HttpStatus.ok) {
        final v = Versions.fromJson(data, timestamp: DateTime.now().toUtc());
        if (v != _latestVersions) {
          _log.fine('$_latestVersions -> $v');
          _latestVersions = v;
          finalStatus = _isStatusIdleOrUpdate;
        }
        success = true;
      } else {
        _log.warning('Version response: ${response?.data}');
      }
    } catch (e, s) {
      _log.severe('Failed to download versions', e, s);
      rethrow;
    } finally {
      _setStatus(finalStatus);
    }
    return success;
  }

  Future<bool> downloadData() async {
    switch (_status) {
      case SyncStatus.idle:
      case SyncStatus.updateAvailable:
      case SyncStatus.mediaNotComplete:
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
    bool success = false;
    SyncStatus finalStatus = _status;
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
        finalStatus = _isStatusIdleOrUpdate;
        success = true;
      } else {
        _log.warning('Data response: ${response?.data}');
      }
    } catch (e, s) {
      _log.severe('Failed to download data', e, s);
      rethrow;
    } finally {
      _setStatus(finalStatus);
    }
    return success;
  }

  Future<List<T>> _runBatched<T>(
    List<MediaWithEtag> items,
    Future<T> Function(MediaWithEtag) task, {
    int batchSize = 5,
  }) async {
    final results = <T>[];
    for (var i = 0; i < items.length; i += batchSize) {
      final batch = items.skip(i).take(batchSize).toList();
      results.addAll(await Future.wait(batch.map(task)));
    }
    return results;
  }

  Future<_DownloadResult> _fetchImageFile(MediaWithEtag image) async {
    try {
      final response = await _get<List<int>>(
        Env.serverImagePath(image.name),
        etag: image.etag,
        responseType: ResponseType.bytes,
      );
      final data = response?.data;
      final statusCode = response?.statusCode;
      return (
        file: image,
        statusCode: statusCode,
        data: data is List<int> && statusCode == HttpStatus.ok
            ? Uint8List.fromList(data)
            : null,
        etag: response?.headers.value(HttpHeaders.etagHeader),
        error: null,
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == HttpStatus.notFound) {
        return (
          file: image,
          statusCode: e.response!.statusCode,
          data: null,
          etag: null,
          error: null,
        );
      }
      return (
        file: image,
        statusCode: e.response?.statusCode,
        data: null,
        etag: null,
        error: e,
      );
    }
  }

  Future<bool> downloadImages({
    Iterable<MediaWithEtag>? images,
    bool stopOnError = true,
  }) async {
    if (images?.isEmpty ?? false) {
      return true;
    }
    switch (_status) {
      case SyncStatus.idle:
      case SyncStatus.updateAvailable:
      case SyncStatus.mediaNotComplete:
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
    SyncStatus finalStatus = _status;
    _setStatus(SyncStatus.imageDownload);
    try {
      if (images == null) {
        final etagMap = {
          for (final i
              in await _db.managers.images
                  .map((i) => (name: i.name, etag: i.etag))
                  .get())
            i.name: i.etag,
        };
        final imageNames = <String>{
          ...await _db.managers.prayerGroups.map((g) => g.image).get(),
          ...await _db.managers.prayers.map((p) => p.image).get(),
        };
        images = imageNames.map((n) => (name: n, etag: etagMap[n])).toList();
      }
      final imageList = images.toList();
      _log.fine('Downloading ${imageList.length} image(s)...');

      // Phase 1: Network — download all files in parallel batches
      final results = await _runBatched(imageList, _fetchImageFile);

      // Phase 2: DB — process results (no transaction needed, each op is atomic)
      bool updateVersion = false;
      for (final r in results) {
        if (r.error != null) {
          _log.severe('Failed to download ${r.file.name}', r.error);
          success = false;
          if (stopOnError) {
            break;
          }
          continue;
        }
        final status = r.statusCode;
        if (status == HttpStatus.ok) {
          await _db.managers.images.create(
            (create) => create(
              name: r.file.name,
              data: r.data!,
              etag: Value.absentIfNull(r.etag),
            ),
            mode: InsertMode.insertOrReplace,
          );
          updateVersion = true;
        } else if (status == HttpStatus.notModified) {
          // no change
        } else if (status == HttpStatus.notFound) {
          _log.fine('Image ${r.file.name} no longer exists on server');
          await _db.managers.images
              .filter((i) => i.name.equals(r.file.name))
              .delete();
        } else if (status != null) {
          success = false;
          if (stopOnError) {
            break;
          }
        }
      }
      if (updateVersion) {
        await _prefs.setVersions(
          _prefs.versions?.copyWith(images: v.images) ??
              Versions.downloaded(v, images: true),
        );
        finalStatus = _isStatusIdleOrUpdate;
      }
    } catch (e, s) {
      _log.severe('Failed to download images', e, s);
      rethrow;
    } finally {
      _setStatus(finalStatus);
    }
    return success;
  }

  Future<bool> updateImages({bool stopOnError = true}) async {
    switch (_status) {
      case SyncStatus.idle:
      case SyncStatus.updateAvailable:
      case SyncStatus.mediaNotComplete:
        break;
      default:
        _log.warning('Cannot update images in $_status');
        return false;
    }
    final etagMap = {
      for (final i
          in await _db.managers.images
              .map((i) => (name: i.name, etag: i.etag))
              .get())
        i.name: i.etag,
    };
    final imageNames = <String>{
      ...await _db.managers.prayerGroups.map((g) => g.image).get(),
      ...await _db.managers.prayers.map((p) => p.image).get(),
    };
    return downloadImages(
      images: imageNames.map((n) => (name: n, etag: etagMap[n])).toList(),
      stopOnError: stopOnError,
    );
  }

  Future<_DownloadResult> _fetchVoiceFile(MediaWithEtag voice) async {
    try {
      final response = await _get<List<int>>(
        Env.serverVoicePath(voice.name),
        etag: voice.etag,
        responseType: ResponseType.bytes,
      );
      final data = response?.data;
      final statusCode = response?.statusCode;
      return (
        file: voice,
        statusCode: statusCode,
        data: data is List<int> && statusCode == HttpStatus.ok
            ? Uint8List.fromList(data)
            : null,
        etag: response?.headers.value(HttpHeaders.etagHeader),
        error: null,
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == HttpStatus.notFound) {
        return (
          file: voice,
          statusCode: e.response!.statusCode,
          data: null,
          etag: null,
          error: null,
        );
      }
      return (
        file: voice,
        statusCode: e.response?.statusCode,
        data: null,
        etag: null,
        error: e,
      );
    }
  }

  Future<bool> downloadVoices({
    Iterable<MediaWithEtag>? voices,
    bool stopOnError = true,
  }) async {
    if (voices?.isEmpty ?? false) {
      return true;
    }
    switch (_status) {
      case SyncStatus.idle:
      case SyncStatus.updateAvailable:
      case SyncStatus.mediaNotComplete:
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
    SyncStatus finalStatus = _status;
    _setStatus(SyncStatus.voiceDownload);
    try {
      if (voices == null) {
        final etagMap = {
          for (final v
              in await _db.managers.voices
                  .map((v) => (name: v.name, etag: v.etag))
                  .get())
            v.name: v.etag,
        };
        final voiceNames = <String>{
          for (final step in await _db.managers.prayerSteps.get())
            ...step.voices,
          'csengo.mp3',
        };
        voices = voiceNames.map((n) => (name: n, etag: etagMap[n])).toList();
      }
      final voiceList = voices.toList();
      _log.fine('Downloading ${voiceList.length} voice(s)...');

      // Phase 1: Network — download all files in parallel batches
      final results = await _runBatched(voiceList, _fetchVoiceFile);

      // Phase 2: DB — process results (no transaction needed, each op is atomic)
      bool updateVersion = false;
      for (final r in results) {
        if (r.error != null) {
          _log.severe('Failed to download ${r.file.name}', r.error);
          success = false;
          if (stopOnError) {
            break;
          }
          continue;
        }
        final status = r.statusCode;
        if (status == HttpStatus.ok) {
          await _db.managers.voices.create(
            (create) => create(
              name: r.file.name,
              data: r.data!,
              etag: Value.absentIfNull(r.etag),
            ),
            mode: InsertMode.insertOrReplace,
          );
          updateVersion = true;
        } else if (status == HttpStatus.notModified) {
          // no change
        } else if (status == HttpStatus.notFound) {
          _log.fine('Voice ${r.file.name} no longer exists on server');
          await _db.managers.voices
              .filter((v) => v.name.equals(r.file.name))
              .delete();
        } else if (status != null) {
          success = false;
          if (stopOnError) {
            break;
          }
        }
      }
      if (updateVersion) {
        await _prefs.setVersions(
          _prefs.versions?.copyWith(voices: v.voices) ??
              Versions.downloaded(v, voices: true),
        );
        finalStatus = _isStatusIdleOrUpdate;
      }
    } catch (e, s) {
      _log.severe('Failed to download images', e, s);
      rethrow;
    } finally {
      _setStatus(finalStatus);
    }
    return success;
  }

  Future<bool> updateVoices({bool stopOnError = true}) async {
    switch (_status) {
      case SyncStatus.idle:
      case SyncStatus.updateAvailable:
      case SyncStatus.mediaNotComplete:
        break;
      default:
        _log.warning('Cannot update voices in $_status');
        return false;
    }
    final etagMap = {
      for (final v
          in await _db.managers.voices
              .map((v) => (name: v.name, etag: v.etag))
              .get())
        v.name: v.etag,
    };
    final voiceNames = <String>{
      for (final step in await _db.managers.prayerSteps.get()) ...step.voices,
      'csengo.mp3',
    };
    return downloadVoices(
      voices: voiceNames.map((n) => (name: n, etag: etagMap[n])).toList(),
      stopOnError: stopOnError,
    );
  }
}

class SyncServiceProvider
    extends ChangeNotifierProxyProvider2<Preferences, Database, SyncService> {
  SyncServiceProvider({super.key})
    : super(
        create: (context) => SyncService(),
        update: (context, prefs, db, srv) => (srv ?? SyncService())
          .._prefs = prefs
          .._db = db,
      );
}
