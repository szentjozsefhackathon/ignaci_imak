import 'dart:async' show StreamSubscription;

import 'package:flutter/material.dart';

import '../data/database.dart';
import '../data/preferences.dart';
import '../services.dart';
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
  late final AudioHandler _audioHandler;

  int _currentPage = 0;
  bool _isClosing = false;
  StreamSubscription? _playbackSubscription;

  @override
  void initState() {
    super.initState();
    _pageViewController = PageController();
    _tabController = TabController(
      length: widget.prayer.steps.length,
      vsync: this,
    );
    _fabAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _currentPage = 0;

    _audioHandler = context.read<AudioHandler>();
    _playbackSubscription = _audioHandler.playbackState.listen((_) {
      if (!mounted || _isClosing) return;
      if (_audioHandler.isFinished) {
        _isClosing = true;
        WidgetsBinding.instance.addPostFrameCallback((_) => _close());
        return;
      }
      if (_audioHandler.prayerIsRunning) {
        if (_fabAnimationController.isDismissed) {
          _fabAnimationController.forward();
        }
      } else {
        if (_fabAnimationController.isCompleted) {
          _fabAnimationController.reverse();
        }
      }
      setState(() {
        _currentPage = _audioHandler.currentIndex ?? _currentPage;
      });
    });
    final prefs = context.read<Preferences>();
    _audioHandler.preparePrayer(prefs.prayerLength);
    _audioHandler.startPrayerTimer();
    _fabAnimationController.value = 1.0;

    _tabController.addListener(() {
      if (!mounted || _tabController.indexIsChanging) return;
      final to = _tabController.index;
      if (to >= widget.prayer.steps.length || to == _currentPage) return;

      setState(() => _currentPage = to);
      _audioHandler.skipToQueueItem(to);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _audioHandler.loadPrayerVoices(
        context,
        widget.group,
        widget.prayer,
        prefs.prayerLength,
        widget.prayer.prayer.voiceOptions.indexOf(prefs.voiceChoice),
      );
      await _audioHandler.initSession(
        const AudioSessionConfiguration.speech().copyWith(
          androidWillPauseWhenDucked: false,
        ),
      );
      await _audioHandler.setMuted(!prefs.prayerSoundEnabled);
    });
  }

  @override
  void dispose() {
    _playbackSubscription?.cancel();
    _audioHandler.stop();
    _pageViewController.dispose();
    _fabAnimationController.dispose();
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
    await _audioHandler.stop();
    if (mounted) {
      int count = 0;
      Navigator.popUntil(context, (_) => count++ >= 2);
    }
  }

  @override
  Widget build(BuildContext context) {
    final remainingTime = _audioHandler.remainingTime;
    final isRunning = _audioHandler.prayerIsRunning;
    final isPaused = _audioHandler.isPausedByUser;

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
            opacity: isPaused ? 1.0 : .4,
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
            if (remainingTime.inSeconds > 0)
              AnimatedOpacity(
                opacity: isPaused ? 1.0 : .5,
                duration: kThemeAnimationDuration,
                child: Text(
                  'Hátralévő idő: ${remainingTime.inMinutes}:${(remainingTime.inSeconds % 60).toString().padLeft(2, '0')}',
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
                  hasFab: remainingTime.inSeconds > 0,
                ),
              ),
            ),
          ],
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.miniEndFloat,
        floatingActionButton: remainingTime.inSeconds <= 0
            ? null
            : AnimatedOpacity(
                opacity: isPaused ? 1.0 : .5,
                duration: kThemeAnimationDuration,
                child: FloatingActionButton(
                  mini: true,
                  onPressed: _togglePlayPause,
                  tooltip: isRunning ? 'Szünet' : 'Folytatás',
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
    if (_audioHandler.prayerIsRunning) {
      _audioHandler.pause();
    } else {
      _audioHandler.play();
    }
  }

  Future<void> _updateCurrentPageIndex(int index) async {
    if (_tabController.indexIsChanging) return;
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
