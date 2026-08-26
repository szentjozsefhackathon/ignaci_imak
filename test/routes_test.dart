import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ignaci_imak/data/types.dart';
import 'package:ignaci_imak/routes.dart';

void main() {
  final prayerGroup = PrayerGroup(title: 'Group Title', image: 'group.jpg');
  final prayer = Prayer(
    group: prayerGroup.slug,
    title: 'Prayer Title',
    description: 'Description',
    image: 'prayer.jpg',
    voiceOptions: const [],
    minTime: const Duration(minutes: 5),
  );

  group('Routes paths', () {
    test('builds group, prayer and resumable prayer paths', () {
      expect(Routes.prayers(prayerGroup), '/group-title');
      expect(Routes.prayer(prayerGroup, prayer), '/group-title/prayer-title');
      expect(
        Routes.prayerState(
          prayerGroup,
          prayer,
          page: 2,
          elapsed: const Duration(seconds: 65),
        ),
        '/group-title/prayer-title?p=2&t=65',
      );
    });
  });

  group('Routes.prayerOffset', () {
    test('restores elapsed time on the first page', () {
      expect(Routes.prayerOffset(Uri.parse('/group/prayer?p=0&t=42'), 3), (
        page: 0,
        elapsed: const Duration(seconds: 42),
      ));
    });

    test('clamps the page and rejects invalid elapsed time', () {
      expect(Routes.prayerOffset(Uri.parse('/group/prayer?p=99&t=42'), 3), (
        page: 2,
        elapsed: const Duration(seconds: 42),
      ));
      expect(
        Routes.prayerOffset(Uri.parse('/group/prayer?p=0&t=-1'), 3),
        isNull,
      );
    });

    test('defaults a missing page to the first page', () {
      expect(Routes.prayerOffset(Uri.parse('/group/prayer?t=12'), 3), (
        page: 0,
        elapsed: const Duration(seconds: 12),
      ));
    });

    test('rejects malformed, negative and unusable parameters', () {
      expect(
        Routes.prayerOffset(Uri.parse('/group/prayer?p=x&t=12'), 3),
        (page: 0, elapsed: const Duration(seconds: 12)),
      );
      expect(
        Routes.prayerOffset(Uri.parse('/group/prayer?p=-1&t=12'), 3),
        isNull,
      );
      expect(
        Routes.prayerOffset(Uri.parse('/group/prayer?p=0&t=x'), 3),
        isNull,
      );
      expect(
        Routes.prayerOffset(Uri.parse('/group/prayer?p=0'), 3),
        isNull,
      );
      expect(
        Routes.prayerOffset(Uri.parse('/group/prayer?p=0&t=12'), 0),
        isNull,
      );
    });
  });

  group('Routes.onGenerateRoute', () {
    test('returns null without a route name', () {
      expect(Routes.onGenerateRoute(const RouteSettings()), isNull);
    });

    test('recognizes static and dynamic paths', () {
      for (final name in [
        Routes.home,
        Routes.settings,
        Routes.impressum,
        '/group-title',
        '/group-title/prayer-title',
      ]) {
        final route = Routes.onGenerateRoute(RouteSettings(name: name));
        expect(route, isA<MaterialPageRoute>(), reason: name);
        expect(route!.settings.name, name);
      }
    });

    test('handles unsupported paths for the current platform', () {
      final route = Routes.onGenerateRoute(
        const RouteSettings(name: '/too/many/segments'),
      );
      expect(route, kIsWeb ? isA<MaterialPageRoute>() : isNull);
    });

    test('creates an unknown route retaining its settings', () {
      const settings = RouteSettings(name: '/missing');
      final route = Routes.onUnknownRoute(settings);
      expect(route, isA<MaterialPageRoute>());
      expect(route.settings, same(settings));
    });
  });
}
