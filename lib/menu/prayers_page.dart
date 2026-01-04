import 'package:flutter/material.dart';

import '../data/database.dart';
import '../prayer/prayer_app_bar.dart';
import '../prayer/prayer_card.dart';
import '../prayer/search.dart';
import '../routes.dart';
import 'common.dart';

class PrayersPage extends StatelessWidget {
  const PrayersPage({super.key, required this.group});

  final PrayerGroup group;

  @override
  Widget build(BuildContext context) {
    final appBarOptions = PrayerAppBarOptions(context, false);

    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          PrayerAppBar.group(
            group: group,
            actions: [PrayerSearchIconButton(group: group)],
            options: appBarOptions,
          ),
        ],
        body: StreamBuilder(
          stream: context.read<Database>().prayersDao.watchPrayersOf(group),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(child: Text(snapshot.error.toString()));
            }
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final prayers = snapshot.data!;
            downloadMissingImages(
              context,
              prayers.map((p) => p.image),
            ).ignore();

            return GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                mainAxisExtent: 200,
                mainAxisSpacing: 8,
                maxCrossAxisExtent: 200,
                crossAxisSpacing: 8,
              ),
              itemCount: prayers.length,
              itemBuilder: (context, index) {
                final prayer = prayers[index];
                return PrayerCard(
                  title: prayer.title,
                  image: prayer.image,
                  onTap: () => Navigator.pushNamed(
                    context,
                    Routes.prayer(group, prayer),
                    arguments: [group, prayer],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
