import 'dart:io' show File, exit, stdout, stderr;

import 'package:http/http.dart' as http;
import 'package:pubspec_lock_parse/pubspec_lock_parse.dart';

Future<void> main(List<String> args) async {
  final pubspec = PubspecLock.parse(File('pubspec.lock').readAsStringSync());
  final sqlite3 = pubspec.packages['sqlite3'];
  if (sqlite3 == null) {
    stderr.writeln('failed to find sqlite3 package in pubspec.lock');
    exit(1);
  }
  stdout.writeln('sqlite3 package found with version ${sqlite3.version}');
  final response = await http.get(
    Uri.parse(
      'https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-${sqlite3.version}/sqlite3.wasm',
    ),
  );
  if (response.statusCode != 200) {
    stderr.writeln(
      'failed to download sqlite3.wasm, status code: ${response.statusCode}',
    );
    exit(1);
  }
  File('web/sqlite3.wasm').writeAsBytesSync(response.bodyBytes);
  stdout.writeln('downloaded sqlite3.wasm to web/');
}
