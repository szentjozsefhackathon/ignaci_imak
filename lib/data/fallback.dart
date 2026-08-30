import 'dart:convert' show json;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show rootBundle;

import 'versions.dart';

class Fallback {
  static const kVersions = 'assets/versions.json';
  static const kPrayers = 'assets/prayers.json';

  static Future<Versions?> loadVersions() async {
    if (kIsWeb) {
      return null;
    }
    try {
      final value = json.decode(await rootBundle.loadString(kVersions));
      final v = Versions.fromJson(
        value as Json,
        timestamp: DateTime.now().toUtc(),
      );
      if (v.data.isEmpty) {
        return null;
      }
      return v;
    } catch (_) {
      return null;
    }
  }

  static Future<List?> loadPrayers() async {
    if (kIsWeb) {
      return null;
    }
    try {
      final p = json.decode(await rootBundle.loadString(kPrayers)) as List;
      if (p.isEmpty) {
        return null;
      }
      return p;
    } catch (_) {
      return null;
    }
  }
}
