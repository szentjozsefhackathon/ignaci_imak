import 'dart:async' show unawaited;
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:collection/collection.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart'
    show ChangeNotifier, kDebugMode, kIsWeb;
import 'package:flutter/widgets.dart' show BuildContext;
import 'package:flutter/widgets.dart' show imageCache;
import 'package:just_audio/just_audio.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart'
    show ChangeNotifierProxyProvider2, ChangeNotifierProvider;
import 'package:sentry_dio/sentry_dio.dart';
import 'package:sentry_flutter/sentry_flutter.dart' show SentryStatusCode;
import 'package:universal_io/io.dart' show File;
import 'package:universal_io/universal_io.dart' show HttpHeaders, HttpStatus;

import 'data/database.dart';
import 'data/preferences.dart';
import 'data/versions.dart';
import 'env.dart';
import 'notifications.dart' show kNotificationIcon, kNotificationChannelBase;
import 'theme.dart' show kThemeSeedColor;

export 'package:audio_session/audio_session.dart';

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
    final voicesLengthField = _db.managers.prayerSteps.computedField(
      (o) => o.voices.length,
    );
    _allVoices = 0;
    for (final (_, refs) in await _db.managers.prayerSteps.withFields([
      voicesLengthField,
    ]).get()) {
      _allVoices += voicesLengthField.read(refs) ?? 0;
    }

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
        // continue
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

  Future<int?> _downloadImage(MediaWithEtag image) async {
    final response = await _get<List<int>>(
      Env.serverImagePath(image.name),
      etag: image.etag,
      responseType: ResponseType.bytes,
    );
    if (response?.data case final List<int> data
        when response?.statusCode == HttpStatus.ok) {
      await _db.managers.images.create(
        (create) => create(
          name: image.name,
          data: Uint8List.fromList(data),
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
    SyncStatus finalStatus = _status;
    _setStatus(SyncStatus.imageDownload);
    try {
      if (images == null) {
        final etagMap = Map.fromEntries(
          await _db.managers.images.map((i) => MapEntry(i.name, i.etag)).get(),
        );
        images = [
          ...await _db.managers.prayerGroups.map((g) => g.image).get(),
          ...await _db.managers.prayers.map((p) => p.image).get(),
        ].map((name) => (name: name, etag: etagMap[name]));
      }
      _log.fine('Downloading ${images.length} image(s)...');
      bool updateVersion = false;
      success = await _db.transaction(() async {
        bool success = true;
        for (final image in images!) {
          final status = await _downloadImage(image);
          if (status == HttpStatus.ok) {
            updateVersion = true;
          } else if (status != HttpStatus.notModified) {
            success = false;
            if (stopOnError) {
              break;
            }
          }
        }
        if (updateVersion) {
          await _prefs.setVersions(
            _prefs.versions?.copyWith(images: v.data) ??
                Versions.downloaded(v, images: true),
          );
          finalStatus = _isStatusIdleOrUpdate;
        }
        return success;
      });
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
        // continue
        break;
      default:
        _log.warning('Cannot update images in $_status');
        return false;
    }
    final downloaded = await _db.managers.images
        .map((i) => (name: i.name, etag: i.etag))
        .get();
    return downloadImages(images: downloaded, stopOnError: stopOnError);
  }

  Future<int?> _downloadVoice(MediaWithEtag voice) async {
    final response = await _get<List<int>>(
      Env.serverVoicePath(voice.name),
      etag: voice.etag,
      responseType: ResponseType.bytes,
    );
    if (response?.data case final List<int> data
        when response?.statusCode == HttpStatus.ok) {
      await _db.managers.voices.create(
        (create) => create(
          name: voice.name,
          data: Uint8List.fromList(data),
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
    SyncStatus finalStatus = _status;
    _setStatus(SyncStatus.voiceDownload);
    try {
      if (voices == null) {
        final etagMap = Map.fromEntries(
          await _db.managers.voices.map((v) => MapEntry(v.name, v.etag)).get(),
        );
        voices = [
          for (final step in await _db.managers.prayerSteps.get())
            ...step.voices,
        ].map((name) => (name: name, etag: etagMap[name]));
      }
      _log.fine('Downloading ${voices.length} image(s)...');
      bool updateVersion = false;
      success = await _db.transaction(() async {
        bool success = true;
        for (final voice in voices!) {
          final status = await _downloadVoice(voice);
          if (status == HttpStatus.ok) {
            updateVersion = true;
          } else if (status != HttpStatus.notModified) {
            success = false;
            if (stopOnError) {
              break;
            }
          }
        }
        if (updateVersion) {
          await _prefs.setVersions(
            _prefs.versions?.copyWith(voices: v.data) ??
                Versions.downloaded(v, voices: true),
          );
          finalStatus = _isStatusIdleOrUpdate;
        }
        return success;
      });
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
        // continue
        break;
      default:
        _log.warning('Cannot update voices in $_status');
        return false;
    }
    final downloaded = await _db.managers.voices
        .map((v) => (name: v.name, etag: v.etag))
        .get();
    return downloadVoices(voices: downloaded, stopOnError: stopOnError);
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

// https://pub.dev/packages/audio_service

// https://github.com/yringler/inside-app/blob/master/just_audio_handlers/lib/src/handler_just_audio.dart
// https://suragch.medium.com/background-audio-in-flutter-with-audio-service-and-just-audio-3cce17b4a7d
// https://pub.dev/packages/just_audio_background

class AudioHandler extends BaseAudioHandler with ChangeNotifier {
  AudioHandler() : _player = AudioPlayer() {
    _setupPlayerListener();
    playbackState.listen((_) => notifyListeners());
    mediaItem.listen((item) => notifyListeners());
  }

  late AudioPlayer _player;
  static const _kTempFilePrefix = '.ignaciima_';
  int? _currentIndex;
  List<Uri>? _voiceUris;
  bool _paused = false;
  bool _prayerActive = false;
  Duration _prayerElapsed = Duration.zero;
  Duration _prayerTotal = Duration.zero;

  void updatePrayerProgress(Duration elapsed, Duration total) {
    _prayerElapsed = elapsed;
    _prayerTotal = total;
    try {
      playbackState.add(
        playbackState.value.copyWith(
          updatePosition: elapsed,
          speed: _paused ? 0 : 1,
        ),
      );
    } catch (_) {}
    notifyListeners();
  }

  Future<void> initSession(AudioSessionConfiguration cfg) async {
    final session = await AudioSession.instance;
    await session.configure(cfg);
  }

  void _setupPlayerListener() {
    _player.playbackEventStream
        .map(_transformEvent)
        .listen((state) => playbackState.add(state));
  }

  @override
  Future<void> play() async {
    _paused = false;
    try {
      playbackState.add(
        playbackState.value.copyWith(
          controls: const [
            MediaControl.skipToPrevious,
            MediaControl.pause,
            MediaControl.skipToNext,
          ],
          updatePosition: _prayerElapsed,
          speed: 1,
        ),
      );
    } catch (_) {}
    notifyListeners();
    if (_player.processingState != ProcessingState.idle) {
      try {
        await _player.play();
      } catch (_) {}
    }
  }

  @override
  Future<void> pause() async {
    _paused = true;
    try {
      playbackState.add(
        playbackState.value.copyWith(
          controls: const [
            MediaControl.skipToPrevious,
            MediaControl.play,
            MediaControl.skipToNext,
          ],
          updatePosition: _prayerElapsed,
          speed: 0,
        ),
      );
    } catch (_) {}
    notifyListeners();
    if (_player.playing) {
      try {
        await _player.pause();
      } catch (_) {}
    }
  }

  bool get isPlaying => playbackState.valueOrNull?.playing ?? false;
  bool get isPausedByUser => _paused;

  bool _isFinished = false;
  bool get isFinished => _isFinished;

  MediaItem? get currentItem => mediaItem.valueOrNull;

  int? get currentIndex => _currentIndex;

  @override
  Future<void> stop() async {
    _paused = false;
    _prayerActive = false;
    _prayerTotal = Duration.zero;
    _prayerElapsed = Duration.zero;
    try {
      await _player.stop();
    } catch (_) {}
    _isFinished = true;
    notifyListeners();
    await super.stop();
    await _cleanupTempFiles();
  }

  Future<void> _cleanupTempFiles() async {
    final tempDir = await getTemporaryDirectory();
    final tempFiles = tempDir
        .list(followLinks: false)
        .where(
          (e) =>
              e is File &&
              path
                  .basenameWithoutExtension(e.path)
                  .startsWith(_kTempFilePrefix),
        );
    await for (final f in tempFiles) {
      await f.delete();
    }
  }

  Future<void> setMuted(bool muted) => _player.setVolume(muted ? 0 : 1);

  Future<void> loadPrayerVoices(
    BuildContext context,
    PrayerGroup group,
    PrayerWithSteps p,
    Duration totalDuration,
    int voiceIndex,
  ) async {
    _paused = false;
    unawaited(_player.dispose().catchError((_) {}));
    _player = AudioPlayer();
    _setupPlayerListener();
    await _cleanupTempFiles();
    if (!context.mounted) {
      return;
    }

    final db = context.read<Database>();
    final imageUri = kIsWeb
        ? Env.serverUri.replace(path: Env.serverImagePath(p.prayer.image))
        : await db.mediaDao.imageByName(p.prayer.image).then((image) async {
            final tempDir = await getTemporaryDirectory();
            final file = File(
              '${tempDir.path}/$_kTempFilePrefix${p.prayer.image}',
            );
            if (!file.existsSync()) {
              await file.writeAsBytes(image.data);
            }
            return file.uri;
          });
    final mediaItems = p.steps
        .mapIndexed((index, step) {
          final voiceIdx = voiceIndex.clamp(0, step.voices.length - 1);
          final name = step.voices[voiceIdx];
          return MediaItem(
            id: name,
            album: '${p.prayer.title} · ${group.title}',
            title: step.description,
            artUri: imageUri,
            duration: totalDuration,
          );
        })
        .toList(growable: false);

    _voiceUris = [];
    for (final m in mediaItems) {
      final Uri voiceUri;
      if (kIsWeb) {
        voiceUri = Env.serverUri.replace(path: Env.serverVoicePath(m.id));
      } else {
        try {
          voiceUri = await db.mediaDao.voiceByName(m.id).then((voice) async {
            final tempDir = await getTemporaryDirectory();
            final file = File('${tempDir.path}/$_kTempFilePrefix${m.id}');
            if (!file.existsSync()) {
              await file.writeAsBytes(voice.data);
            }
            return file.uri;
          });
        } catch (_) {
          continue;
        }
      }
      _voiceUris!.add(voiceUri);
    }

    if (_voiceUris!.isEmpty) {
      return;
    }

    _isFinished = false;
    _prayerActive = true;
    _currentIndex = 0;
    queue.add(mediaItems);
    try {
      await _loadAndPlayStep(0);
    } catch (_) {
      _prayerActive = false;
    }
  }

  Future<void> _loadAndPlayStep(int index) async {
    if (_voiceUris == null || index >= _voiceUris!.length) {
      return;
    }
    final uri = _voiceUris![index];
    if (uri.scheme == 'file' && !File(uri.toFilePath()).existsSync()) {
      mediaItem.add(queue.value[index]);
      return;
    }
    try {
      await _player.stop();
      await _player.setAudioSource(AudioSource.uri(uri));
      mediaItem.add(queue.value[index]);
      if (!_paused) {
        await _player.play();
      }
    } catch (_) {}
  }

  @override
  Future<void> skipToPrevious() async {
    final prevIndex = (_currentIndex ?? 0) - 1;
    if (prevIndex >= 0) {
      await skipToQueueItem(prevIndex);
    }
  }

  @override
  Future<void> skipToNext() async {
    final nextIndex = (_currentIndex ?? 0) + 1;
    final queueLen = queue.valueOrNull?.length ?? 0;
    if (nextIndex < queueLen) {
      await skipToQueueItem(nextIndex);
    }
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (queue.valueOrNull == null || index >= queue.value.length) {
      return;
    }
    _currentIndex = index;
    playbackState.add(playbackState.value.copyWith(queueIndex: index));
    mediaItem.add(queue.value[index]);
    try {
      await _loadAndPlayStep(index);
    } catch (_) {}
  }

  Future<void> finish() async {
    _prayerActive = false;
    _prayerTotal = Duration.zero;
    _prayerElapsed = Duration.zero;
    _isFinished = true;
    await _player.stop();
    notifyListeners();
    final finishPlayer = AudioPlayer();
    await finishPlayer.setAudioSource(AudioSource.asset('csengo.mp3'));
    await finishPlayer.play();
    await finishPlayer.dispose();
  }

  PlaybackState _transformEvent(PlaybackEvent event) => PlaybackState(
    controls: [
      MediaControl.skipToPrevious,
      if (_paused) MediaControl.play else MediaControl.pause,
      MediaControl.skipToNext,
    ],
    androidCompactActionIndices: const [0, 1, 2],
    processingState: switch (_player.processingState) {
      ProcessingState.idle => AudioProcessingState.idle,
      ProcessingState.loading => AudioProcessingState.loading,
      ProcessingState.buffering => AudioProcessingState.buffering,
      ProcessingState.ready => AudioProcessingState.ready,
      ProcessingState.completed => AudioProcessingState.idle,
    },
    playing: _prayerActive,
    updatePosition: _prayerTotal > Duration.zero
        ? _prayerElapsed
        : _player.position,
    bufferedPosition: _player.bufferedPosition,
    speed: _prayerTotal > Duration.zero ? (_paused ? 0 : 1) : _player.speed,
    queueIndex: _currentIndex,
  );
}

class AudioHandlerProvider extends ChangeNotifierProvider<AudioHandler> {
  AudioHandlerProvider({super.key, required super.value}) : super.value();

  static Future<AudioHandler>
  createHandler() => AudioService.init<AudioHandler>(
    builder: () => AudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationIcon: kNotificationIcon,
      notificationColor: kThemeSeedColor,
      androidNotificationOngoing: true,
      androidNotificationChannelId: '$kNotificationChannelBase.ima',
      androidNotificationChannelName: 'Ima értesítés',
      androidNotificationChannelDescription:
          'Az ima elindítása alatt megjelenő értesítés, amivel az alkalmazás háttérbe kerülése esetén és a lezárt képernyőről is vezérelhető marad.',
    ),
  );
}
