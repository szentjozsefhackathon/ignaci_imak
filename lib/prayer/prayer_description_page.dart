import 'package:flutter/material.dart';

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
  final _settingsKey = GlobalKey();
  bool _settingsVisible = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_updateSettingsVisibility);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _updateSettingsVisibility() {
    final renderBox =
        _settingsKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || !mounted) return;
    final visible =
        renderBox.localToGlobal(Offset.zero).dy <
        MediaQuery.sizeOf(context).height - kMinInteractiveDimension * 2;
    if (visible != _settingsVisible) {
      setState(() => _settingsVisible = visible);
    }
  }

  Future<void> _onFabPressed() async {
    if (_settingsAreShown) {
      final steps = await context.read<Database>().prayersDao.prayerStepsOf(
        widget.prayer.prayer,
      );
      if (!mounted) return;
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

    setState(() => _settingsVisible = true);
    await Scrollable.ensureVisible(
      _settingsKey.currentContext!,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }

  bool get _settingsAreShown =>
      MediaQuery.sizeOf(context).width >= _wideLayoutBreakpoint ||
      _settingsVisible;

  Widget _description() => PrayerText(
    widget.prayer.prayer.description,
    minFontSize: PrayerText.kDefaultFontSize,
    padding: EdgeInsets.zero,
  );

  Widget _settings() => Column(
    key: _settingsKey,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Text(
          'Ima beállítása',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
      ),
      PrayerSettings(prayer: widget.prayer),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final appBarOptions = PrayerAppBarOptions(context, true);

    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          PrayerAppBar.prayer(
            group: widget.prayer.group,
            prayer: widget.prayer.prayer,
            options: appBarOptions,
          ),
        ],
        body: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= _wideLayoutBreakpoint) {
              return ListView(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(
                  24,
                  32,
                  24,
                  kMinInteractiveDimension * 2,
                ),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1200),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: _description(),
                            ),
                          ),
                          const SizedBox(width: 32),
                          Expanded(child: _settings()),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            }
            return ListView(
              controller: _scrollController,
              padding: const EdgeInsets.only(
                bottom: kMinInteractiveDimension * 2,
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 32, 16, 48),
                  child: _description(),
                ),
                _settings(),
              ],
            );
          },
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
}
