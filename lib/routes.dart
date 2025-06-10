import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

import 'data/prayer.dart';
import 'data/prayer_group.dart';
import 'data_handlers/data_manager.dart';
import 'menu/prayer_groups_page.dart';
import 'menu/prayers_page.dart';
import 'prayer/prayer_description_page.dart';
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
          final slug = uri.pathSegments.last;
          return FutureBuilder<PrayerGroup?>(
            future: DataManager.instance.prayerGroups.data.then(
              (g) => g.items.singleWhereOrNull((i) => i.slug == slug),
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
              group: args[0] as PrayerGroup,
              prayer: args[1] as Prayer,
            );
          }
          final [groupSlug, prayerSlug] = uri.pathSegments;
          return FutureBuilder<PrayerGroup?>(
            future: DataManager.instance.prayerGroups.data.then(
              (g) => g.items.singleWhereOrNull((i) => i.slug == groupSlug),
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
              final prayer = data.prayers.singleWhereOrNull(
                (p) => p.slug == prayerSlug,
              );
              if (prayer == null) {
                return const _NotFoundPage();
              }
              return PrayerDescriptionPage(group: data, prayer: prayer);
            },
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
