import 'dart:convert' show json;

import 'package:drift/drift.dart' show TypeConverter;

class DurationConverter extends TypeConverter<Duration, int> {
  const DurationConverter();

  @override
  Duration fromSql(int fromDb) => Duration(seconds: fromDb);

  @override
  int toSql(Duration value) => value.inSeconds;
}

class StringListConverter extends TypeConverter<List<String>, String> {
  const StringListConverter();

  @override
  List<String> fromSql(String fromDb) => List<String>.from(json.decode(fromDb));

  @override
  String toSql(List<String> value) => json.encode(value);
}
