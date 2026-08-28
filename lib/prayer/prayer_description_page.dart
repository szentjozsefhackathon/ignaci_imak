import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;

import '../data/database.dart';
import 'prayer_app_bar.dart';
import 'prayer_page.dart';
import 'prayer_settings.dart';
import 'prayer_text.dart';

class PrayerDescriptionPage extends StatefulWidget {
  const PrayerDescriptionPage({super.key, required this.prayer});

  final PrayerWithGroup prayer;

  @override
  State<PrayerDescriptionPage> createState() => _PrayerDescriptionPageState();
}

class _PrayerDescriptionPageState extends State<PrayerDescriptionPage> {
  static const _wideLayoutBreakpoint = 900.0;

  final _scrollController = ScrollController();
  bool _showingSettings = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _onFabPressed() async {
    if (_settingsAreShown) {
      final steps = await context.read<Database>().prayersDao.prayerStepsOf(
        widget.prayer.prayer,
      );
      if (!mounted) {
        return;
      }
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PrayerPage(
            group: widget.prayer.group,
            prayer: (prayer: widget.prayer.prayer, steps: steps),
          ),
        ),
      );
      return;
    }

    setState(() => _showingSettings = true);
    await _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }

  bool get _settingsAreShown =>
      MediaQuery.sizeOf(context).width >= _wideLayoutBreakpoint ||
      _showingSettings;

  bool _onScroll(ScrollNotification notification) {
    final scrollingUp =
        notification is UserScrollNotification &&
        notification.direction == ScrollDirection.forward;
    final reachedBottom =
        notification is ScrollUpdateNotification &&
        notification.metrics.extentAfter == 0;
    final showingSettings = reachedBottom || (_showingSettings && !scrollingUp);

    if (showingSettings != _showingSettings) {
      setState(() => _showingSettings = showingSettings);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final appBarOptions = PrayerAppBarOptions(context, true);

    return Scaffold(
      body: NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            PrayerAppBar.prayer(
              group: widget.prayer.group,
              prayer: widget.prayer.prayer,
              options: appBarOptions,
            ),
            SliverToBoxAdapter(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth >= _wideLayoutBreakpoint) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(
                        24,
                        32,
                        24,
                        kMinInteractiveDimension * 2,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1200),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: _buildDescription(),
                                ),
                              ),
                              const Expanded(child: SizedBox(width: 32)),
                              Expanded(child: _buildSettings(rounded: true)),
                            ],
                          ),
                        ),
                      ),
                    );
                  }
                  return Padding(
                    padding: const EdgeInsets.only(
                      bottom: kMinInteractiveDimension * 2,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 32, 16, 48),
                          child: _buildDescription(),
                        ),
                        _buildSettings(),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: FloatingActionButton(
        onPressed: _onFabPressed,
        tooltip: _settingsAreShown ? 'Ima indítása' : 'Ima beállítása',
        child: Icon(
          _settingsAreShown
              ? Icons.play_arrow_rounded
              : Icons.keyboard_arrow_down_rounded,
        ),
      ),
    );
  }

  Widget _buildDescription() => PrayerText(
    widget.prayer.prayer.description,
    minFontSize: PrayerText.kDefaultFontSize,
    padding: EdgeInsets.zero,
  );

  Widget _buildSettings({bool rounded = false}) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Text(
          'Ima beállítása',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
      ),
      ListTileTheme.merge(
        shape: rounded
            ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
            : null,
        child: PrayerSettings(prayer: widget.prayer),
      ),
    ],
  );
}
