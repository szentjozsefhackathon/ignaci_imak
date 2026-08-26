import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

import 'data/database.dart';
import 'menu/prayer_groups_page.dart';
import 'menu/prayers_page.dart';
import 'prayer/prayer_description_page.dart';
import 'prayer/prayer_page.dart';
import 'settings/data_sync_page.dart';
import 'settings/impressum_page.dart';
import 'settings/settings_page.dart';

class Routes {
  Routes._();

  static final _log = Logger('Routes');

  static const home = '/';

  static String prayers(PrayerGroup group) => '/${group.slug}';
  static String prayer(PrayerGroup group, Prayer prayer) =>
      '${prayers(group)}/${prayer.slug}';

  static String prayerState(
    PrayerGroup group,
    Prayer prayer, {
    required int page,
    required Duration elapsed,
  }) => Uri(
    path: Routes.prayer(group, prayer),
    queryParameters: {'p': '$page', 't': '${elapsed.inSeconds}'},
  ).toString();

  static PrayerOffset? prayerOffset(Uri uri, int pageCount) {
    final elapsed = int.tryParse(uri.queryParameters['t'] ?? '');
    final page = int.tryParse(uri.queryParameters['p'] ?? '') ?? 0;
    if (elapsed == null || elapsed < 0 || page < 0 || pageCount == 0) {
      return null;
    }
    return (
      page: page.clamp(0, pageCount - 1),
      elapsed: Duration(seconds: elapsed),
    );
  }

  static const settings = '/beallitasok';
  static const dataSync = '$settings/adatok';
  static const impressum = '$settings/impresszum';

  static Route? onGenerateRoute(RouteSettings s) {
    if (s.name == null) {
      return null;
    }
    _log.info('onGenerateRoute: ${s.name}');
    final matchedRoute = switch (s.name) {
      home => MaterialPageRoute(
        settings: s,
        builder: (context) => const PrayerGroupsPage(),
      ),
      settings => MaterialPageRoute(
        settings: s,
        builder: (context) => const SettingsPage(),
      ),
      dataSync =>
        kIsWeb
            ? onUnknownRoute(s)
            : MaterialPageRoute(
                settings: s,
                builder: (context) => const DataSyncPage(),
              ),
      impressum => MaterialPageRoute(
        settings: s,
        builder: (context) => const ImpressumPage(),
      ),
      _ => null,
    };
    if (matchedRoute != null) {
      return matchedRoute;
    }
    final uri = Uri.parse(s.name!);
    if (uri.pathSegments.length == 1) {
      return MaterialPageRoute(
        settings: s,
        builder: (context) {
          final group = context.getRouteArgument<PrayerGroup>();
          if (group != null) {
            return PrayersPage(group: group);
          }
          return Consumer<Database>(
            builder: (context, db, _) => FutureBuilder(
              future: db.prayersDao.findPrayerGroupBySlug(
                uri.pathSegments.last,
              ),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Scaffold(
                    body: Center(child: Text(snapshot.error.toString())),
                  );
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Scaffold(
                    body: Center(child: CircularProgressIndicator()),
                  );
                }
                final data = snapshot.data;
                if (data == null) {
                  return const _NotFoundPage();
                }
                return PrayersPage(group: data);
              },
            ),
          );
        },
      );
    }
    if (uri.pathSegments.length == 2) {
      return MaterialPageRoute(
        settings: s,
        builder: (context) {
          final args = context.getRouteArgument<List<Object>>();
          if (args != null) {
            return PrayerDescriptionPage(
              prayer: (
                group: args[0] as PrayerGroup,
                prayer: args[1] as Prayer,
              ),
            );
          }
          return Consumer<Database>(
            builder: (context, db, _) => FutureBuilder(
              future: _loadPrayer(db, uri),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Scaffold(
                    body: Center(child: Text(snapshot.error.toString())),
                  );
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Scaffold(
                    body: Center(child: CircularProgressIndicator()),
                  );
                }
                final data = snapshot.data;
                if (data == null) {
                  return const _NotFoundPage();
                }
                final offset = Routes.prayerOffset(
                  uri,
                  data.withSteps?.steps.length ?? 0,
                );
                if (offset != null && data.withSteps != null) {
                  return PrayerPage(
                    group: data.prayer.group,
                    prayer: data.withSteps!,
                    offset: offset,
                  );
                }
                return PrayerDescriptionPage(prayer: data.prayer);
              },
            ),
          );
        },
      );
    }
    return kIsWeb ? onUnknownRoute(s) : null;
  }

  static Route onUnknownRoute(RouteSettings s) => MaterialPageRoute(
    settings: s,
    builder: (context) => const _NotFoundPage(),
  );

  static Future<({PrayerWithGroup prayer, PrayerWithSteps? withSteps})?>
  _loadPrayer(Database db, Uri uri) async {
    final [groupSlug, prayerSlug] = uri.pathSegments;
    final prayer = await db.prayersDao.findPrayerBySlugs(groupSlug, prayerSlug);
    if (prayer == null || !uri.queryParameters.containsKey('t')) {
      return prayer == null ? null : (prayer: prayer, withSteps: null);
    }
    final steps = await db.prayersDao.prayerStepsOf(prayer.prayer);
    return (
      prayer: prayer,
      withSteps: steps.isEmpty ? null : (prayer: prayer.prayer, steps: steps),
    );
  }
}

extension _RoutesExtension on BuildContext {
  T? getRouteArgument<T>() => ModalRoute.of(this)!.settings.arguments as T?;
}

class _NotFoundPage extends StatelessWidget {
  const _NotFoundPage();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 16,
        children: [
          const Text('Nincs ilyen oldal'),
          TextButton(
            onPressed: () =>
                Navigator.pushReplacementNamed(context, Routes.home),
            child: const Text('Kezdőoldal'),
          ),
        ],
      ),
    ),
  );
}
