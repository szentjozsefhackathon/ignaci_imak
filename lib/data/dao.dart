import 'package:drift/drift.dart';

import 'database.dart';

part 'dao.g.dart';

@DriftAccessor(tables: [PrayerSteps, Prayers, PrayerGroups])
class PrayersDao extends DatabaseAccessor<Database> with _$PrayersDaoMixin {
  PrayersDao(super.db);

  Future<List<PrayerWithGroup>> getPrayersWithGroups() async {
    final prayers = <PrayerWithGroup>[];
    for (final (group, refs)
        in await db.managers.prayerGroups
            .withReferences((prefetch) => prefetch(prayersRefs: true))
            .orderBy((o) => o.title.asc())
            .get()) {
      for (final prayer in await refs.prayersRefs.get()) {
        prayers.add((prayer: prayer, group: group));
      }
    }
    return prayers;
  }

  Future<List<PrayerGroup>> getPrayerGroups() =>
      db.managers.prayerGroups.orderBy((o) => o.title.asc()).get();

  Stream<List<PrayerGroup>> watchPrayerGroups() =>
      db.managers.prayerGroups.orderBy((o) => o.title.asc()).watch();

  Future<List<Prayer>> getPrayersOf(PrayerGroup group) => db.managers.prayers
      .filter((p) => p.group.slug(group.slug))
      .orderBy((o) => o.title.asc())
      .get();

  Stream<List<Prayer>> watchPrayersOf(PrayerGroup group) => db.managers.prayers
      .filter((p) => p.group.slug(group.slug))
      .orderBy((o) => o.title.asc())
      .watch();

  Future<PrayerGroup?> findPrayerGroupBySlug(String slug) =>
      db.managers.prayerGroups.filter((g) => g.slug(slug)).getSingleOrNull();

  Future<PrayerWithGroup?> findPrayerBySlugs(
    String groupSlug,
    String prayerSlug,
  ) async {
    final prayer = await db.managers.prayers
        .filter((p) => p.group.slug(groupSlug) & p.slug(prayerSlug))
        .getSingleOrNull();
    if (prayer == null) {
      return null;
    }
    final group = await findPrayerGroupBySlug(groupSlug);
    if (group == null) {
      return null;
    }
    return (prayer: prayer, group: group);
  }

  Future<List<PrayerStep>> prayerStepsOf(Prayer prayer) => db
      .managers
      .prayerSteps
      .filter((s) => s.prayer.slug(prayer.slug))
      .orderBy((o) => o.index.asc())
      .get();
}

@DriftAccessor(tables: [PrayerSteps, Prayers, PrayerGroups])
class MediaDao extends DatabaseAccessor<Database> with _$MediaDaoMixin {
  MediaDao(super.db);

  Future<Voice> voiceByName(String name) =>
      db.managers.voices.filter((v) => v.name(name)).getSingle();

  Stream<Image?> watchImageByName(String name) =>
      db.managers.images.filter((g) => g.name(name)).watchSingleOrNull();

  Future<List<String>> availableVoiceOptionsOf(Prayer prayer) async {
    final steps = await db.prayersDao.prayerStepsOf(prayer);
    final names = <String, String>{};
    for (final option in prayer.voiceOptions) {
      final voiceIndex = prayer.voiceOptions.indexOf(option);
      names[option] = steps.first.voices[voiceIndex];
    }
    final voiceNames = await db.managers.voices
        .filter((v) => v.name.isIn(names.values))
        .map((v) => v.name)
        .get();
    return names.keys
        .where((option) => voiceNames.contains(names[option]))
        .toList(growable: false);
  }
}
