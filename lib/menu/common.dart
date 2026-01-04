import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart' show BuildContext;

import '../data/database.dart';
import '../services.dart';

Future<void> downloadMissingImages(
  BuildContext context,
  Iterable<String> images,
) async {
  if (kIsWeb || images.isEmpty) {
    return;
  }
  final srv = context.read<SyncService>();
  final db = context.read<Database>();
  final downloadedImages = await db.managers.images.map((i) => i.name).get();
  await srv.downloadImages(
    images: images
        .where((image) => !downloadedImages.contains(image))
        .map((image) => (name: image, etag: null)),
  );
}
