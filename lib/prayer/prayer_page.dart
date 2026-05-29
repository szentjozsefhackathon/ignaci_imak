import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:vibration/vibration.dart';

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
      ..addListener(_onAudioHandlerUpdate)
      ..play();

    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        _audioHandler.skipToQueueItem(_tabController.index);
      }
    });
  }

  Future<void> _onAudioHandlerUpdate() async {
    final dnd = context.read<Dnd>();
    if (_audioHandler.isFinished) {
      _vibrateIfNoSound();
      await dnd.restoreOriginal();
      _close();
      return;
    }
    if (_audioHandler.isPlaying) {
      if (_prefs.dnd) {
        await dnd.allowAlarmsOnly();
      }
      await _fabAnimationController.forward();
    } else {
      await _fabAnimationController.reverse();
      await dnd.restoreOriginal();
    }
    if (!_tabController.indexIsChanging) {
      _tabController.index = _audioHandler.currentIndex!;
    }
  }

  @override
  void deactivate() {
    context.read<Dnd>().restoreOriginal();
    super.deactivate();
  }

  @override
  void dispose() {
    _audioHandler.stop();
    _pageViewController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _close() {
    if (mounted) {
      int count = 0;
      Navigator.popUntil(context, (_) => count++ >= 2);
    }
  }

  @override
  Widget build(BuildContext context) {
    final audioHandler = context.watch<AudioHandler>();
    final remainingTime = audioHandler.remainingTime;
    return Scaffold(
      appBar: AppBar(
        leading: CloseButton(onPressed: _close),
        title: AnimatedOpacity(
          opacity: audioHandler.isPlaying ? .4 : 1,
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
          if (!audioHandler.isFinished && remainingTime != null)
            AnimatedOpacity(
              opacity: audioHandler.isPlaying ? .5 : 1,
              duration: kThemeAnimationDuration,
              child: Text('Hátralévő idő: ${_formatDuration(remainingTime)}'),
            ),
          Opacity(
            opacity: .25,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: _PageIndicator(
                tabController: _tabController,
                currentPageIndex: audioHandler.currentIndex!,
                onUpdateCurrentPageIndex: _updateCurrentPageIndex,
                hasFab: !audioHandler.isFinished,
              ),
            ),
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.miniEndFloat,
      floatingActionButton: audioHandler.isFinished
          ? null
          : AnimatedOpacity(
              opacity: audioHandler.isPlaying ? .5 : 1,
              duration: kThemeAnimationDuration,
              child: FloatingActionButton(
                mini: true,
                onPressed: () {
                  if (audioHandler.isPlaying) {
                    audioHandler.pause();
                  } else {
                    audioHandler.play();
                  }
                },
                tooltip: audioHandler.isPlaying ? 'Szünet' : 'Folytatás',
                child: AnimatedIcon(
                  icon: AnimatedIcons.play_pause,
                  progress: _fabAnimationController,
                ),
              ),
            ),
    );
  }

  String _formatDuration(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

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
