import 'dart:convert' show json;
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:ignaci_imak/env.dart';

Future<void> main() async {
  final serverUri = Env.serverUri;
  const versionsPath = Env.serverCheckVersionsPath;
  const dataPath = Env.serverDownloadDataPath;
  if ([versionsPath, dataPath].any((value) => value.isEmpty)) {
    stderr.writeln(
      'All of SERVER_CHECK_VERSIONS_PATH and SERVER_DOWNLOAD_DATA_PATH must be set in .env',
    );
    exit(1);
  }

  final versions = await _download(
    serverUri.resolve(versionsPath),
    expectList: false,
  );
  final prayers = await _download(
    serverUri.resolve(dataPath),
    expectList: true,
  );

  final directory = Directory('assets')..createSync(recursive: true);
  File('${directory.path}/versions.json').writeAsStringSync(versions);
  File('${directory.path}/prayers.json').writeAsStringSync(prayers);
  stdout.writeln('Downloaded native fallback assets.');
}

Future<String> _download(Uri uri, {required bool expectList}) async {
  stdout.writeln('Downloading $uri');
  final response = await http.get(uri);
  if (response.statusCode != 200) {
    throw StateError('$uri returned HTTP ${response.statusCode}');
  }
  final decoded = json.decode(response.body);
  if (expectList ? decoded is! List : decoded is! Map<String, dynamic>) {
    throw FormatException('Unexpected JSON returned by $uri');
  }
  return response.body;
}
