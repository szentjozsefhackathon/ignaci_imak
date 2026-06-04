import 'dart:async' show Timer;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:vibration/vibration.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../data/database.dart';
import '../data/preferences.dart';
import '../services.dart';
import '../settings/dnd.dart' show Dnd;
import 'prayer_text.dart';

class PrayerPage extends StatefulWidget {
  const PrayerPage({super.key, required this.group, required this.prayer});

  final PrayerGroup group;
  final PrayerWithSteps prayer;

  @override
  State<PrayerPage> createState() => _PrayerPageState();
}

class _PrayerPageState extends State<PrayerPage> with TickerProviderStateMixin {
  late final AnimationController _fabAnimationController;
  late final PageController _pageViewController;
  late final TabController _tabController;
  late final Preferences _prefs;
  late final AudioHandler _audioHandler;

  late List<Duration> _pageStartTimes = [];
  late Duration _remainingTime = Duration.zero;
  late int _currentPage = 0;
  bool _isRunning = false;
  bool _isPaused = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _pageViewController = PageController();
    _tabController = TabController(
      length: widget.prayer.steps.length,
      vsync: this,
    );
    _prefs = context.read<Preferences>();
    _fabAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _audioHandler = context.read<AudioHandler>()
      ..loadPrayerVoices(
        context,
        widget.group,
        widget.prayer,
        _prefs.prayerLength,
        widget.prayer.prayer.voiceOptions.indexOf(_prefs.voiceChoice),
      )
      ..initSession(
        const AudioSessionConfiguration.speech().copyWith(
          androidWillPauseWhenDucked: false,
        ),
      )
      ..setMuted(!_prefs.prayerSoundEnabled)
      ..addListener(_onAudioHandlerUpdate);

    _startPrayer();

    _tabController.addListener(() {
      if (!mounted || _tabController.indexIsChanging) return;
      final to = _tabController.index;
      if (to == _currentPage) return;

      setState(() {
        _currentPage = to;
        _remainingTime = _pageStartTimes[to];
      });

      if (_prefs.prayerSoundEnabled) {
        _audioHandler.skipToQueueItem(to);
      }
    });
  }

  void _startPrayer() {
    _pageStartTimes = _computePageStartTimes();
    _remainingTime = _prefs.prayerLength;
    _currentPage = 0;
    _audioHandler.updatePrayerProgress(Duration.zero, _prefs.prayerLength);
    _startTimer();
    if (_prefs.dnd) {
      context.read<Dnd>().allowAlarmsOnly();
    }
    WakelockPlus.enable();
    _fabAnimationController.forward();
  }

  void _startTimer() {
    const timerPeriod = Duration(seconds: 1);
    _timer = Timer.periodic(timerPeriod, (timer) {
      if (_isPaused) {
        timer.cancel();
        return;
      }
      _remainingTime -= timerPeriod;

      if (_prefs.autoPageTurn &&
          _currentPage < widget.prayer.steps.length - 1 &&
          _remainingTime <= _pageStartTimes[_currentPage + 1]) {
        _updateCurrentPageIndex(_currentPage + 1);
        _vibrateIfNoSound();
      }

      _isRunning = true;
      setState(() {});
      _audioHandler.updatePrayerProgress(
        _prefs.prayerLength - _remainingTime,
        _prefs.prayerLength,
      );

      if (_remainingTime.inSeconds <= 0) {
        timer.cancel();
        _onTimerFinish();
      }
    });
  }

  Future<void> _onTimerFinish() async {
    setState(() => _isRunning = false);
    await _audioHandler.finish();
    _vibrateIfNoSound();
    await WakelockPlus.disable();
    if (mounted) {
      await context.read<Dnd>().restoreOriginal();
      await _close();
    }
  }

  void _onAudioHandlerUpdate() {
    if (!mounted) return;
    if (_audioHandler.isFinished) return;

    if (!_audioHandler.isPausedByUser && _isPaused) {
      _isPaused = false;
      _startTimer();
      _fabAnimationController.forward();
      WakelockPlus.toggle(enable: true);
      setState(() {});
    } else if (_audioHandler.isPausedByUser && _isRunning && !_isPaused) {
      _isPaused = true;
      _isRunning = false;
      _timer?.cancel();
      _fabAnimationController.reverse();
      WakelockPlus.toggle(enable: false);
      setState(() {});
    }

    final handlerIndex = _audioHandler.currentIndex;
    if (handlerIndex != null &&
        handlerIndex != _currentPage &&
        !_tabController.indexIsChanging) {
      _updateCurrentPageIndex(handlerIndex);
    }
  }

  @override
  void deactivate() {
    context.read<Dnd>().restoreOriginal();
    super.deactivate();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _audioHandler.removeListener(_onAudioHandlerUpdate);
    _audioHandler.stop();
    WakelockPlus.disable();
    _pageViewController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<bool> _showExitConfirmation() async {
    if (!mounted) return true;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ima leállítása'),
        content: const Text('Biztosan le akarod állítani az imát?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Mégse'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Leállítás'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _requestClose() async {
    if (!mounted) return;
    final confirmed = await _showExitConfirmation();
    if (!confirmed || !mounted) return;
    await _close();
  }

  Future<void> _close() async {
    _timer?.cancel();
    await _audioHandler.stop();
    await WakelockPlus.disable();
    if (mounted) {
      await context.read<Dnd>().restoreOriginal();
      if (!mounted) return;
      int count = 0;
      Navigator.popUntil(context, (_) => count++ >= 2);
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<AudioHandler>();
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _requestClose();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: CloseButton(onPressed: _requestClose),
          title: AnimatedOpacity(
            opacity: _isPaused ? 1.0 : .4,
            duration: kThemeAnimationDuration,
            child: Text(widget.prayer.prayer.title),
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
            if (_remainingTime.inSeconds > 0)
              AnimatedOpacity(
                opacity: _isPaused ? 1.0 : .5,
                duration: kThemeAnimationDuration,
                child: Text(
                  'Hátralévő idő: ${_remainingTime.inMinutes}:${(_remainingTime.inSeconds % 60).toString().padLeft(2, '0')}',
                ),
              ),
            Opacity(
              opacity: .25,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: _PageIndicator(
                  tabController: _tabController,
                  currentPageIndex: _currentPage,
                  onUpdateCurrentPageIndex: _updateCurrentPageIndex,
                  hasFab: _remainingTime.inSeconds > 0,
                ),
              ),
            ),
          ],
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.miniEndFloat,
        floatingActionButton: _remainingTime.inSeconds <= 0
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
      ),
    );
  }

  void _togglePlayPause() {
    if (_isRunning) {
      _isPaused = true;
      _isRunning = false;
      _timer?.cancel();
      _fabAnimationController.reverse();
      _audioHandler.pause();
    } else {
      _isPaused = false;
      _startTimer();
      _fabAnimationController.forward();
      _audioHandler.play();
    }
    WakelockPlus.toggle(enable: !_isPaused);
    setState(() {});
  }

  Future<void> _updateCurrentPageIndex(int index) async {
    if (_tabController.indexIsChanging) {
      return;
    }
    _tabController.animateTo(
      index,
      duration: kThemeAnimationDuration,
      curve: Curves.easeInOut,
    );
    await _pageViewController.animateToPage(
      index,
      duration: kThemeAnimationDuration,
      curve: Curves.easeInOut,
    );
  }

  List<Duration> _computePageStartTimes() {
    final steps = widget.prayer.steps;
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

    final total = _prefs.prayerLength;
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

  void _vibrateIfNoSound() {
    if (kIsWeb) {
      return;
    }
    if (widget.prayer.prayer.voiceOptions.isEmpty ||
        !_prefs.prayerSoundEnabled) {
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

  // each dot is about 24px wide (10-16 + padding/border)
  static const double _kDotWidth = 24;

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
    final offset = (widget.currentPageIndex * _kDotWidth) - (_kDotWidth * 2);
    _scrollController.jumpTo(offset < 0 ? 0 : offset);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

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
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: AnimatedContainer(
                          duration: kThemeAnimationDuration,
                          width: isSelected ? 16 : 10,
                          height: isSelected ? 16 : 10,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? colorScheme.primary
                                : colorScheme.surface.withValues(alpha: 0.5),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: colorScheme.primary.withValues(alpha: 0.5),
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
