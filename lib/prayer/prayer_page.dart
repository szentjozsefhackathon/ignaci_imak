import 'dart:async' show Timer;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:logging/logging.dart';
import 'package:provider/provider.dart';
import 'package:vibration/vibration.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../data/prayer.dart';
import '../data/prayer_step.dart';
import '../data/settings_data.dart';
import '../data_handlers/data_manager.dart';
import '../settings/dnd.dart' show DndProvider;
import 'prayer_text.dart';

class PrayerPage extends StatefulWidget {
  const PrayerPage({super.key, required this.prayer});

  final Prayer prayer;

  @override
  State<PrayerPage> createState() => _PrayerPageState();
}

class _PrayerPageState extends State<PrayerPage> with TickerProviderStateMixin {
  static final log = Logger('PrayerPage');

  late final AudioPlayer _audioPlayer;
  late List<int> _nextPageTimes = [];
  late int _remainingSeconds = 0;
  late int _currentPage = 0;
  bool _isRunning = false;
  bool _isPaused = false;
  late final AnimationController _fabAnimationController;
  Timer? _timer;

  late final PageController _pageViewController;
  late final TabController _tabController;
  late final SettingsData _settings;

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    _pageViewController = PageController();
    _tabController = TabController(
      length: widget.prayer.steps.length,
      vsync: this,
    );
    _settings = context.read<SettingsData>();
    _fabAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _startPrayer();
    _tabController.addListener(() {
      if (!mounted || _tabController.indexIsChanging) {
        return;
      }
      setState(() => _currentPage = _tabController.index);
      if (_settings.prayerSoundEnabled) {
        _pageAudioPlayer();
      }
    });
  }

  @override
  void deactivate() {
    context.read<DndProvider>().restoreOriginal();
    super.deactivate();
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _audioPlayer.dispose();
    _timer?.cancel();
    _pageViewController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _startPrayer() {
    _nextPageTimes = _getOptimalPageTimes();
    _remainingSeconds = _settings.prayerLength * 60;
    _startTimer();
    if (_settings.dnd) {
      context.read<DndProvider>().allowAlarmsOnly();
    }
    WakelockPlus.enable();
    if (_settings.prayerSoundEnabled) {
      _pageAudioPlayer();
    }
    _fabAnimationController.forward();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_isPaused) {
        timer.cancel();
      } else {
        _remainingSeconds--;
        if (_settings.autoPageTurn) {
          for (final time in _nextPageTimes) {
            if (time == _remainingSeconds) {
              final pageIndex = _nextPageTimes.indexOf(time);
              // we're not going back
              if (pageIndex > _currentPage) {
                _updateCurrentPageIndex(pageIndex);
                _vibrateIfNoSound();
              }
              break;
            }
          }
        }
        _isRunning = true;
        setState(() {});
      }
      if (_remainingSeconds <= 0) {
        timer.cancel();
        _onTimerFinish();
      }
    });
  }

  Future<void> _onTimerFinish() async {
    setState(() => _isRunning = false);
    if (_settings.prayerSoundEnabled) {
      await _audioPlayer.pause();
      await _loadAudio('csengo.mp3');
      await _audioPlayer.setVolume(1);
      await _audioPlayer.play();
    }
    _vibrateIfNoSound();
    await WakelockPlus.disable();
    if (mounted) {
      await context.read<DndProvider>().restoreOriginal();
      _close();
    }
  }

  void _close() {
    if (mounted) {
      int count = 0;
      Navigator.popUntil(context, (_) => count++ >= 2);
    }
  }

  Future<void> _loadAudio(String filename) async {
    try {
      if (kIsWeb) {
        await _audioPlayer.setAudioSource(
          AudioSource.uri(DataManager.instance.voices.getDownloadUri(filename)),
          initialPosition: Duration.zero,
        );
      } else {
        await DataManager.instance.voices
            .getLocalFile(filename)
            .then((audio) => _audioPlayer.setFilePath(audio.path));
      }
    } catch (e, s) {
      log.severe('Error loading $filename', e, s);
    }
  }

  Future<void> _pageAudioPlayer() async {
    if (widget.prayer.voiceOptions.isEmpty) {
      return;
    }
    await _audioPlayer.pause();
    final voiceIndex = widget.prayer.voiceOptions.indexOf(
      _settings.voiceChoice,
    );
    // match voices
    final filename = widget.prayer.steps[_currentPage].voices[voiceIndex];
    await _loadAudio(filename);
    await _audioPlayer.setVolume(1);
    if (_isPaused) {
      await _audioPlayer.pause();
    } else {
      await _audioPlayer.play();
    }
  }

  List<int> _getOptimalPageTimes() {
    final pageTimes = <int>[];
    var totalFixTime = 0;
    var totalFlexTime = 0;
    for (final step in widget.prayer.steps) {
      if (step.type == PrayerStepType.fix) {
        totalFixTime += step.timeInSeconds;
      } else if (step.type == PrayerStepType.flex) {
        totalFlexTime += step.timeInSeconds;
      }
    }
    final totalTimeForFlex = _settings.prayerLength * 60 - totalFixTime;
    var remainingTime = _settings.prayerLength * 60;
    for (final step in widget.prayer.steps) {
      if (step.type == PrayerStepType.fix) {
        remainingTime -= step.timeInSeconds;
      } else if (step.type == PrayerStepType.flex) {
        remainingTime -= totalTimeForFlex * step.timeInSeconds ~/ totalFlexTime;
      }
      pageTimes.add(remainingTime);
    }
    pageTimes.removeLast();
    return pageTimes;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: CloseButton(onPressed: _close),
      title: AnimatedOpacity(
        opacity: _isPaused ? 1.0 : .4,
        duration: kThemeAnimationDuration,
        child: Text(widget.prayer.title),
      ),
    ),
    body: Column(
      children: [
        Expanded(
          child: PageView.builder(
            controller: _pageViewController,
            itemCount: widget.prayer.steps.length,
            onPageChanged: (index) => _tabController.index = index,
            itemBuilder: (context, index) =>
                PrayerText(widget.prayer.steps[index].description),
          ),
        ),
        if (_remainingSeconds > 0)
          AnimatedOpacity(
            opacity: _isPaused ? 1.0 : .5,
            duration: kThemeAnimationDuration,
            child: Text(
              "Hátralévő idő: ${_remainingSeconds ~/ 60}:${(_remainingSeconds % 60).toString().padLeft(2, '0')}",
            ),
          ),
        Opacity(
          opacity: .25,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 56.0), // Add bottom padding
            child: _PageIndicator(
              tabController: _tabController,
              currentPageIndex: _currentPage,
              onUpdateCurrentPageIndex: _updateCurrentPageIndex,
              hasFab: _remainingSeconds > 0,
            ),
          ),
        ),
      ],
    ),
    floatingActionButtonLocation: FloatingActionButtonLocation.miniEndFloat,
    floatingActionButton: _remainingSeconds <= 0
        ? null
        : AnimatedOpacity(
            opacity: _isPaused ? 1.0 : .5,
            duration: kThemeAnimationDuration,
            child: FloatingActionButton(
              mini: true,
              onPressed: _togglePlayPause,
              tooltip: _isRunning ? 'Szünet' : 'Folytatás',
              child: AnimatedIcon(
                icon: AnimatedIcons.play_pause,
                progress: _fabAnimationController,
              ),
            ),
          ),
  );

  void _togglePlayPause() {
    if (_isRunning) {
      _audioPlayer.pause();
      _isPaused = true;
      _isRunning = false;
      _fabAnimationController.reverse();
    } else {
      _isPaused = false;
      _startTimer();
      _audioPlayer.play();
      _fabAnimationController.forward();
    }
    WakelockPlus.toggle(enable: !_isPaused);
    setState(() {});
  }

  Future<void> _updateCurrentPageIndex(int index) async {
    _tabController.index = index;
    await _pageViewController.animateToPage(
      index,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }

  void _vibrateIfNoSound() {
    if (kIsWeb) {
      return;
    }
    if (widget.prayer.voiceOptions.isEmpty || !_settings.prayerSoundEnabled) {
      Vibration.vibrate();
    }
  }
}

class _PageIndicator extends StatefulWidget {
  const _PageIndicator({
    required this.tabController,
    required this.currentPageIndex,
    required this.onUpdateCurrentPageIndex,
    required this.hasFab,
  });

  final int currentPageIndex;
  final TabController tabController;
  final void Function(int) onUpdateCurrentPageIndex;
  final bool hasFab;

  @override
  State<_PageIndicator> createState() => _PageIndicatorState();
}

class _PageIndicatorState extends State<_PageIndicator> {
  final ScrollController _scrollController = ScrollController();
  int? _lastScrolledIndex;

  @override
  void didUpdateWidget(covariant _PageIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_lastScrolledIndex != widget.currentPageIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToCurrentDot();
        _lastScrolledIndex = widget.currentPageIndex;
      });
    }
  }

  void _scrollToCurrentDot() {
    // Each dot is about 24px wide (10-16 + padding/border)
    const double dotWidth = 24.0;
    final double offset = (widget.currentPageIndex * dotWidth) - (dotWidth * 2);
    _scrollController.animateTo(
      offset < 0 ? 0 : offset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // ...existing LayoutBuilder and padding code...
    return LayoutBuilder(
      builder: (context, constraints) {
        double left = 8;
        double right = 8;
        if (widget.hasFab) {
          if (constraints.maxWidth > ((widget.tabController.length + 1) * 32)) {
            left += kMinInteractiveDimension;
          }
          right += kMinInteractiveDimension;
        }

        return Padding(
          padding: EdgeInsets.fromLTRB(left, 8, right, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                splashRadius: 16,
                padding: EdgeInsets.zero,
                onPressed: widget.currentPageIndex <= 0
                    ? null
                    : () => widget.onUpdateCurrentPageIndex(
                        widget.currentPageIndex - 1,
                      ),
                icon: const Icon(Icons.chevron_left_rounded),
                tooltip: 'Előző oldal',
              ),
              Flexible(
                child: SingleChildScrollView(
                  controller: _scrollController,
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(widget.tabController.length, (i) {
                      final isSelected = i == widget.currentPageIndex;
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4.0),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: isSelected ? 16 : 10,
                          height: isSelected ? 16 : 10,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? colorScheme.primary
                                : colorScheme.surface.withOpacity(0.5),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: colorScheme.primary.withOpacity(0.5),
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ),
              IconButton(
                splashRadius: 16,
                padding: EdgeInsets.zero,
                onPressed:
                    widget.currentPageIndex >= widget.tabController.length - 1
                    ? null
                    : () => widget.onUpdateCurrentPageIndex(
                        widget.currentPageIndex + 1,
                      ),
                icon: const Icon(Icons.chevron_right_rounded),
                tooltip: 'Következő oldal',
              ),
            ],
          ),
        );
      },
    );
  }
}
