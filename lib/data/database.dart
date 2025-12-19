import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart' show Provider;

import 'converters.dart';
import 'dao.dart';
import 'types.dart';

export 'package:provider/provider.dart'
    show ReadContext, WatchContext, Consumer;

export 'types.dart';

part 'database.g.dart';

@UseRowClass(PrayerStep)
@TableIndex(name: 'step_prayer', columns: {#prayer})
class PrayerSteps extends Table {
  late final id = integer().autoIncrement()();
  late final index = integer()();
  late final description = text()();
  late final type = textEnum<PrayerStepType>()();
  late final Column<int> time = integer()
      .check(time.isBiggerThanValue(0))
      .map(const DurationConverter())();
  late final voices = text().map(const StringListConverter())();
  late final prayer = text().references(Prayers, #slug)();

  @override
  List<Set<Column>> get uniqueKeys => [
    {prayer, index},
  ];
}

abstract class PrayerTable extends Table {
  late final slug = text()();
  late final title = text()();
  late final image = text().references(Images, #name)();

  @override
  Set<Column<Object>> get primaryKey => {slug};
}

@UseRowClass(Prayer)
@TableIndex(name: 'prayer_slug', columns: {#slug})
class Prayers extends PrayerTable {
  late final description = text()();
  late final Column<int> minTime = integer()
      .check(minTime.isBiggerThanValue(0))
      .map(const DurationConverter())();
  late final voiceOptions = text().map(const StringListConverter())();
  late final group = text().references(PrayerGroups, #slug)();
}

@UseRowClass(PrayerGroup)
@TableIndex(name: 'prayer_group_slug', columns: {#slug})
class PrayerGroups extends PrayerTable {}

abstract class MediaTable extends Table {
  late final name = text()();
  late final data = blob()();
  late final etag = text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {name};
}

@TableIndex(name: 'image_name', columns: {#name})
class Images extends MediaTable {}

@TableIndex(name: 'voice_name', columns: {#name})
class Voices extends MediaTable {}

@DriftDatabase(
  tables: [PrayerSteps, Prayers, PrayerGroups, Images, Voices],
  daos: [PrayersDao, MediaDao],
)
class Database extends _$Database {
  Database([QueryExecutor? executor]) : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 1;

  static QueryExecutor _openConnection() => driftDatabase(
    name: 'ignaciimak',
    native: const DriftNativeOptions(
      // By default, `driftDatabase` from `package:drift_flutter` stores the database files in `getApplicationDocumentsDirectory()`.
      databaseDirectory: getApplicationSupportDirectory,
    ),
  );
}

class DatabaseProvider extends Provider<Database> {
  DatabaseProvider({super.key})
    : super(create: (_) => Database(), dispose: (_, db) => db.close());
}
