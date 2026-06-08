import 'dart:async' show Timer, unawaited;
import 'dart:typed_data' show Uint8List, ByteData, Endian;
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart' show BuildContext;
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart' show Provider;
import 'package:universal_io/io.dart' show File;
import 'package:vibration/vibration.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../data/database.dart';
import '../data/preferences.dart';
import '../env.dart';
import '../notifications.dart' show kNotificationIcon, kNotificationChannelBase;
import '../settings/dnd.dart' show Dnd;
import '../theme.dart' show kThemeSeedColor;

export 'package:audio_session/audio_session.dart';

// https://pub.dev/packages/audio_service
// https://github.com/yringler/inside-app/blob/master/just_audio_handlers/lib/src/handler_just_audio.dart
// https://suragch.medium.com/background-audio-in-flutter-with-audio-service-and-just-audio-3cce17b4a7d
// https://pub.dev/packages/just_audio_background

class AudioHandler extends BaseAudioHandler {
  AudioHandler() : _player = AudioPlayer(), _bgPlayer = AudioPlayer() {
    _setupPlayerListener();
  }

  late AudioPlayer _player;
  final AudioPlayer _bgPlayer;
  static const _kTempFilePrefix = '.ignaciima_';
  int? _currentIndex;
  List<Uri>? _voiceUris;
  bool _paused = false;
  bool _prayerActive = false;
  Duration _prayerElapsed = Duration.zero;
  Duration _prayerTotal = Duration.zero;
  Uri? _csengoUri;
  Dnd? _dnd;
  bool _dndWasEnabled = false;

  Timer? _prayerTimer;
  DateTime? _prayerStartTime;
  DateTime? _pausedAt;
  Duration _remainingTime = Duration.zero;
  int _prayerCurrentPage = 0;
  List<Duration> _pageStartTimes = [];
  bool _prayerIsRunning = false;
  int _totalSteps = 0;
  bool _autoPageTurn = false;
  bool _prayerHasVoices = false;
  bool _soundMuted = false;
  Uri? _silenceUri;

  static Future<Uri> _ensureSilenceFile() async {
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/${_kTempFilePrefix}silence.wav');
    if (!file.existsSync()) {
      const sampleRate = 44100;
      const numSamples = sampleRate;
      const dataSize = numSamples * 2;
      const fileSize = 44 + dataSize;
      final bytes = Uint8List(fileSize);
      final b = ByteData.view(bytes.buffer);
      int offset = 0;
      void ws(String s) {
        for (int i = 0; i < s.length; i++) {
          b.setUint8(offset++, s.codeUnitAt(i));
        }
      }

      ws('RIFF');
      b.setUint32(offset, fileSize - 8, Endian.little);
      offset += 4;
      ws('WAVE');
      ws('fmt ');
      b.setUint32(offset, 16, Endian.little);
      offset += 4;
      b.setUint16(offset, 1, Endian.little);
      offset += 2;
      b.setUint16(offset, 1, Endian.little);
      offset += 2;
      b.setUint32(offset, sampleRate, Endian.little);
      offset += 4;
      b.setUint32(offset, sampleRate * 2, Endian.little);
      offset += 4;
      b.setUint16(offset, 2, Endian.little);
      offset += 2;
      b.setUint16(offset, 16, Endian.little);
      offset += 2;
      ws('data');
      b.setUint32(offset, dataSize, Endian.little);
      offset += 4;
      await file.writeAsBytes(bytes);
    }
    return file.uri;
  }

  Future<void> _startBgLoop() async {
    final silenceUri = await _ensureSilenceFile();
    await _bgPlayer.setAudioSource(AudioSource.uri(silenceUri));
    await _bgPlayer.setLoopMode(LoopMode.all);
    await _bgPlayer.play();
  }

  Future<void> _stopBgLoop() async {
    if (_bgPlayer.playing) {
      await _bgPlayer.stop();
    }
  }

  void preparePrayer(Duration total) {
    _prayerTotal = total;
    _remainingTime = total;
  }

  void startPrayerTimer() {
    _prayerStartTime = DateTime.now();
    _prayerElapsed = Duration.zero;
    _remainingTime = _prayerTotal;
    if (!kIsWeb) {
      unawaited(WakelockPlus.enable());
    }
    _startPrayerTimer();
  }

  void _restoreDnd() {
    if (_dndWasEnabled) {
      _dndWasEnabled = false;
      _dnd?.restoreOriginal();
      _dnd = null;
    }
  }

  Future<void> initSession(AudioSessionConfiguration cfg) async {
    final session = await AudioSession.instance;
    await session.configure(cfg);
  }

  void _setupPlayerListener() {
    _player.playbackEventStream.listen((event) {
      playbackState.add(_transformEvent(event));
      if (event.processingState == ProcessingState.completed &&
          _prayerActive &&
          !_paused &&
          !kIsWeb &&
          _silenceUri != null) {
        unawaited(
          _player
              .setAudioSource(AudioSource.uri(_silenceUri!))
              .then((_) => _player.setLoopMode(LoopMode.all))
              .then((_) => _player.play()),
        );
      }
    });
  }

  @override
  Future<void> play() async {
    _paused = false;
    if (_pausedAt != null) {
      final now = DateTime.now();
      if (_prayerStartTime == null) {
        _prayerStartTime = now;
      } else {
        _prayerStartTime = _prayerStartTime!.add(now.difference(_pausedAt!));
      }
      _pausedAt = null;
    }
    if (!kIsWeb) {
      unawaited(WakelockPlus.enable());
    }
    if (_prayerTimer == null) {
      _startPrayerTimer();
    }
    try {
      playbackState.add(
        playbackState.value.copyWith(
          controls: const [
            MediaControl.skipToPrevious,
            MediaControl.pause,
            MediaControl.skipToNext,
          ],
          playing: true,
          updatePosition: _prayerElapsed,
          speed: 1,
        ),
      );
    } catch (_) {}
    if (_player.processingState == ProcessingState.completed ||
        _player.processingState == ProcessingState.idle) {
      return;
    }
    try {
      await _player.play();
    } catch (_) {}
  }

  @override
  Future<void> pause() async {
    _paused = true;
    _pausedAt = DateTime.now();
    if (!kIsWeb) {
      unawaited(WakelockPlus.disable());
    }
    _prayerTimer?.cancel();
    _prayerTimer = null;
    _prayerIsRunning = false;
    try {
      playbackState.add(
        playbackState.value.copyWith(
          controls: const [
            MediaControl.skipToPrevious,
            MediaControl.play,
            MediaControl.skipToNext,
          ],
          playing: false,
          updatePosition: _prayerElapsed,
          speed: 0,
        ),
      );
    } catch (_) {}
    if (_player.playing) {
      try {
        await _player.pause();
      } catch (_) {}
    }
  }

  bool get isPlaying => playbackState.valueOrNull?.playing ?? false;
  bool get isPausedByUser => _paused;
  bool get isRunning => !_paused;

  bool _isFinished = false;
  bool get isFinished => _isFinished;

  Duration get remainingTime => _remainingTime;
  int get prayerCurrentPage => _prayerCurrentPage;
  bool get prayerIsRunning => _prayerIsRunning;

  MediaItem? get currentItem => mediaItem.valueOrNull;

  int? get currentIndex => _currentIndex;

  @override
  Future<void> stop() async {
    _prayerTimer?.cancel();
    _prayerTimer = null;
    _prayerIsRunning = false;
    _pausedAt = null;
    _paused = true;
    _prayerActive = false;
    if (!kIsWeb) {
      unawaited(WakelockPlus.disable());
    }
    try {
      await _player.stop();
    } catch (_) {}
    try {
      await _bgPlayer.stop();
    } catch (_) {}
    _restoreDnd();
    await super.stop();
  }

  Future<void> stopPrayer() async {
    _prayerTimer?.cancel();
    _prayerTimer = null;
    _prayerIsRunning = false;
    _pausedAt = null;
    _paused = false;
    _prayerActive = false;
    _prayerTotal = Duration.zero;
    _prayerElapsed = Duration.zero;
    if (!kIsWeb) {
      unawaited(WakelockPlus.disable());
    }
    try {
      await _player.stop();
    } catch (_) {}
    try {
      await _bgPlayer.stop();
    } catch (_) {}
    _restoreDnd();
    _isFinished = true;
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

  Future<void> setMuted(bool muted) {
    _soundMuted = muted;
    return _player.setVolume(muted ? 0 : 1);
  }

  Future<void> loadPrayerVoices(
    BuildContext context,
    PrayerGroup group,
    PrayerWithSteps p,
    Duration totalDuration,
    int voiceIndex,
  ) async {
    _paused = false;
    _prayerElapsed = Duration.zero;
    _csengoUri = null;
    await _stopBgLoop();
    unawaited(_player.dispose().catchError((_) {}));
    _player = AudioPlayer();
    _setupPlayerListener();
    await _cleanupTempFiles();
    if (!context.mounted) {
      return;
    }

    final db = context.read<Database>();
    final prefs = context.read<Preferences>();
    if (prefs.dnd) {
      _dndWasEnabled = true;
      _dnd = context.read<Dnd>();
      await _dnd!.allowAlarmsOnly();
    }
    if (!kIsWeb) {
      try {
        final csengo = await db.mediaDao.voiceByName('csengo.mp3');
        if (true) {
          final tempDir = await getTemporaryDirectory();
          final file = File('${tempDir.path}/${_kTempFilePrefix}csengo.mp3');
          if (!file.existsSync()) {
            await file.writeAsBytes(csengo.data);
          }
          _csengoUri = file.uri;
        }
      } catch (_) {}
    }
    _csengoUri ??= Env.serverUri.replace(
      path: Env.serverVoicePath('csengo.mp3'),
    );
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
    if (!kIsWeb) {
      _silenceUri ??= await _ensureSilenceFile();
    }
    final mediaItems = p.steps
        .mapIndexed((index, step) {
          if (step.voices.isEmpty) {
            return MediaItem(
              id: '__silence__',
              album: '${p.prayer.title} · ${group.title}',
              title: step.description,
              artUri: imageUri,
              duration: totalDuration,
            );
          }
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
      if (m.id == '__silence__') {
        if (kIsWeb) {
          _voiceUris!.add(Uri());
          continue;
        }
        _voiceUris!.add(_silenceUri!);
        continue;
      }
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
          _voiceUris!.add(_silenceUri!);
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
    _pageStartTimes = AudioHandler.computePageStartTimes(
      p.steps,
      totalDuration,
    );
    _totalSteps = p.steps.length;
    _prayerHasVoices = p.prayer.voiceOptions.isNotEmpty;
    _autoPageTurn = prefs.autoPageTurn;
    playbackState.add(
      PlaybackState(
        controls: const [
          MediaControl.skipToPrevious,
          MediaControl.pause,
          MediaControl.skipToNext,
        ],
        androidCompactActionIndices: [0, 1, 2],
        playing: true,
        updatePosition: _prayerElapsed,
      ),
    );
    _currentIndex = 0;
    _prayerCurrentPage = 0;
    queue.add(mediaItems);
    try {
      await _loadAndPlayStep(0);
    } catch (_) {
      _prayerActive = false;
    }
    if (!kIsWeb) {
      await _startBgLoop();
    }
  }

  Future<void> _loadAndPlayStep(int index) async {
    if (_voiceUris == null || index >= _voiceUris!.length) {
      return;
    }
    final uri = _voiceUris![index];
    if (uri.toString().isEmpty) {
      mediaItem.add(queue.value[index]);
      return;
    }
    if (uri.scheme == 'file' && !File(uri.toFilePath()).existsSync()) {
      mediaItem.add(queue.value[index]);
      return;
    }
    try {
      await _player.setAudioSource(AudioSource.uri(uri));
      if (uri == _silenceUri) {
        await _player.setLoopMode(LoopMode.all);
      } else {
        await _player.setLoopMode(LoopMode.off);
      }
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
    _prayerCurrentPage = index;
    if (index < _pageStartTimes.length) {
      _remainingTime = _pageStartTimes[index];
      final now = DateTime.now();
      _prayerStartTime = now.subtract(_prayerTotal - _remainingTime);
      _prayerElapsed = _prayerTotal - _remainingTime;
    }
    playbackState.add(playbackState.value.copyWith(queueIndex: index));
    mediaItem.add(queue.value[index]);
    try {
      await _loadAndPlayStep(index);
    } catch (_) {}
  }

  Future<void> finish() async {
    _prayerTimer?.cancel();
    _prayerTimer = null;
    _prayerIsRunning = false;
    _pausedAt = null;
    _prayerActive = false;
    _prayerTotal = Duration.zero;
    _prayerElapsed = Duration.zero;
    _isFinished = true;
    if (!kIsWeb) {
      unawaited(WakelockPlus.disable());
    }

    if (_csengoUri != null) {
      final finishPlayer = AudioPlayer();
      try {
        await finishPlayer.setAudioSource(AudioSource.uri(_csengoUri!));
        final done = finishPlayer.processingStateStream.firstWhere(
          (s) => s == ProcessingState.completed,
        );
        await finishPlayer.play();
        await done.timeout(
          const Duration(seconds: 10),
          onTimeout: () => ProcessingState.completed,
        );
      } catch (_) {
      } finally {
        unawaited(finishPlayer.dispose());
      }
    }

    try {
      await _player.stop();
    } catch (_) {}
    try {
      await _bgPlayer.stop();
    } catch (_) {}
    _restoreDnd();

    try {
      playbackState.add(
        playbackState.value.copyWith(
          controls: [],
          playing: false,
          processingState: AudioProcessingState.ready,
        ),
      );
      playbackState.add(
        playbackState.value.copyWith(
          controls: [],
          playing: false,
          processingState: AudioProcessingState.idle,
        ),
      );
    } catch (_) {}
  }

  static List<Duration> computePageStartTimes(
    List<PrayerStep> steps,
    Duration total,
  ) {
    if (steps.isEmpty) return [];

    Duration totalFix = Duration.zero;
    Duration totalFlex = Duration.zero;
    for (final s in steps) {
      if (s.type == PrayerStepType.fix) {
        totalFix += s.time;
      } else if (s.type == PrayerStepType.flex) {
        totalFlex += s.time;
      }
    }

    final flexAvailable = total - totalFix;

    final durations = <Duration>[];
    if (totalFix.inSeconds == 0 && totalFlex.inSeconds == 0) {
      durations.addAll(steps.map((_) => Duration.zero));
    } else if (totalFlex.inSeconds == 0 || flexAvailable.inSeconds <= 0) {
      final totalWeight = steps.fold<int>(
        0,
        (sum, s) => sum + s.time.inSeconds,
      );
      durations.addAll(
        steps.map(
          (s) => Duration(
            seconds: total.inSeconds * s.time.inSeconds ~/ totalWeight,
          ),
        ),
      );
    } else {
      for (final s in steps) {
        if (s.type == PrayerStepType.fix) {
          durations.add(s.time);
        } else {
          durations.add(
            Duration(
              seconds:
                  flexAvailable.inSeconds *
                  s.time.inSeconds ~/
                  totalFlex.inSeconds,
            ),
          );
        }
      }
    }

    final startTimes = <Duration>[];
    Duration running = total;
    for (int i = 0; i < steps.length; i++) {
      startTimes.add(running);
      running -= durations[i];
    }
    return startTimes;
  }

  void _startPrayerTimer() {
    const timerPeriod = Duration(seconds: 1);
    _prayerIsRunning = true;
    _prayerTimer = Timer.periodic(timerPeriod, (timer) {
      if (_prayerStartTime == null) {
        timer.cancel();
        _prayerTimer = null;
        return;
      }
      _remainingTime =
          _prayerTotal - DateTime.now().difference(_prayerStartTime!);

      if (_autoPageTurn &&
          _prayerCurrentPage < _totalSteps - 1 &&
          _remainingTime <= _pageStartTimes[_prayerCurrentPage + 1]) {
        skipToQueueItem(_prayerCurrentPage + 1);
        _vibrateIfNoSound();
      }

      _prayerElapsed = _prayerTotal - _remainingTime;
      try {
        playbackState.add(
          playbackState.value.copyWith(
            updatePosition: _prayerElapsed,
            playing: _prayerActive && !_paused,
            speed: 1,
          ),
        );
      } catch (_) {}

      if (_remainingTime.inSeconds <= 0) {
        timer.cancel();
        _prayerTimer = null;
        _finishPrayer();
      }
    });
  }

  Future<void> _finishPrayer() async {
    _prayerIsRunning = false;
    if (!kIsWeb) {
      unawaited(WakelockPlus.disable());
    }
    await finish();
    _vibrateIfNoSound();
  }

  void _vibrateIfNoSound() {
    if (kIsWeb) return;
    if (!_prayerHasVoices || _soundMuted) {
      Vibration.vibrate();
    }
  }

  PlaybackState _transformEvent(PlaybackEvent event) => PlaybackState(
    controls: [
      MediaControl.skipToPrevious,
      if (_paused) MediaControl.play else MediaControl.pause,
      MediaControl.skipToNext,
    ],
    androidCompactActionIndices: const [0, 1, 2],
    processingState: switch (_player.processingState) {
      ProcessingState.idle =>
        _prayerActive && _prayerTotal > Duration.zero
            ? AudioProcessingState.ready
            : AudioProcessingState.idle,
      ProcessingState.loading => AudioProcessingState.loading,
      ProcessingState.buffering => AudioProcessingState.buffering,
      ProcessingState.ready => AudioProcessingState.ready,
      ProcessingState.completed => AudioProcessingState.idle,
    },
    playing: _prayerActive && !_paused,
    updatePosition: _prayerTotal > Duration.zero
        ? _prayerElapsed
        : _player.position,
    bufferedPosition: _player.bufferedPosition,
    speed: _prayerTotal > Duration.zero ? (_paused ? 0 : 1) : _player.speed,
    queueIndex: _currentIndex,
  );
}

class AudioHandlerProvider extends Provider<AudioHandler> {
  AudioHandlerProvider({super.key, required AudioHandler value})
    : super.value(value: value);

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
