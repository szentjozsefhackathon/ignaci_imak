import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../data/database.dart';
import '../prayer/prayer_app_bar.dart';
import '../prayer/prayer_image.dart';
import '../prayer/search.dart';
import '../routes.dart';
import '../services.dart';

class PrayersPage extends StatelessWidget {
  const PrayersPage({super.key, required this.group});

  final PrayerGroup group;

  Future<void> _downloadMissingImages(
    BuildContext context,
    List<Prayer> prayers,
  ) async {
    if (kIsWeb || prayers.isEmpty) {
      return;
    }
    final srv = context.read<SyncService>();
    final db = context.read<Database>();
    final downloadedImages = await db.managers.images.map((i) => i.name).get();
    await srv.downloadImages(
      images: prayers
          .where((p) => !downloadedImages.contains(p.image))
          .map((p) => (name: p.image, etag: null)),
      stopOnError: true,
    );
  }

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
            _downloadMissingImages(context, prayers).ignore();

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
                return Card(
                  clipBehavior: Clip.antiAliasWithSaveLayer,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 4,
                  child: InkWell(
                    onTap: () => Navigator.pushNamed(
                      context,
                      Routes.prayer(group, prayer),
                      arguments: [group, prayer],
                    ),
                    child: Stack(
                      children: [
                        Positioned.fill(child: PrayerImage(name: prayer.image)),
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: Container(
                            color: Colors.black54,
                            padding: const EdgeInsets.all(8),
                            child: Text(
                              prayer.title,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
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
