import 'package:flutter/material.dart';

import '../data/prayer.dart';
import '../data/prayer_group.dart';
import 'prayer_app_bar.dart';
import 'prayer_settings_page.dart';
import 'prayer_text.dart';

class PrayerDescriptionPage extends StatelessWidget {
  const PrayerDescriptionPage({
    super.key,
    required this.group,
    required this.prayer,
  });

  final PrayerGroup group;
  final Prayer prayer;

  @override
  Widget build(BuildContext context) {
    final appBarOptions = PrayerAppBarOptions(context, true);

    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          PrayerAppBar.prayer(
            group: group,
            prayer: prayer,
            options: appBarOptions,
          ),
        ],
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            16,
            32,
            16,
            kMinInteractiveDimension * 2,
          ),
          child: PrayerText(
            prayer.description,
            minFontSize: PrayerText.kDefaultFontSize,
            padding: EdgeInsets.zero,
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PrayerSettingsPage(prayer: prayer),
          ),
        ),
        tooltip: 'Ima beállítása',
        child: const Icon(Icons.check_rounded),
      ),
    );
  }
}
