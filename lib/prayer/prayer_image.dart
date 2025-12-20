import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../data/database.dart' hide Image;
import '../env.dart';

class PrayerImage extends StatelessWidget {
  const PrayerImage({
    super.key,
    required this.name,
    this.opacity,
    this.frameBuilder = _defaultFrameBuilder,
    this.loadingBuilder = _defaultLoadingBuilder,
    this.errorBuilder = _defaultErrorBuilder,
  });

  final String name;
  final Animation<double>? opacity;
  final ImageFrameBuilder? frameBuilder;
  final ImageLoadingBuilder? loadingBuilder;
  final ImageErrorWidgetBuilder? errorBuilder;

  static Widget _defaultFrameBuilder(
    BuildContext context,
    Widget child,
    int? frame,
    bool wasSynchronouslyLoaded,
  ) {
    if (wasSynchronouslyLoaded) {
      return child;
    }
    return AnimatedOpacity(
      opacity: frame == null ? 0 : 1,
      duration: const Duration(seconds: 1),
      curve: Curves.easeOut,
      child: child,
    );
  }

  static Widget _defaultErrorBuilder(
    BuildContext context,
    Object error,
    StackTrace? stack,
  ) => const Center(
    child: Icon(Icons.broken_image, size: 50, color: Colors.grey),
  );

  static Widget _defaultLoadingBuilder(
    BuildContext context,
    Widget child,
    ImageChunkEvent? event,
  ) {
    if (event == null) {
      return child;
    }
    return Center(
      child: CircularProgressIndicator(
        value: event.expectedTotalBytes != null
            ? event.cumulativeBytesLoaded / event.expectedTotalBytes!
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return Image.network(
        Env.serverUri.replace(path: Env.serverImagePath(name)).toString(),
        fit: BoxFit.cover,
        opacity: opacity,
        frameBuilder: frameBuilder,
        loadingBuilder: loadingBuilder,
        errorBuilder: errorBuilder,
      );
    }

    return StreamBuilder(
      stream: context.read<Database>().mediaDao.watchImageByName(name),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return loadingBuilder?.call(
                context,
                frameBuilder?.call(context, const SizedBox(), 0, false) ??
                    const SizedBox(),
                null,
              ) ??
              const SizedBox();
        }
        if (snapshot.hasError) {
          return errorBuilder?.call(
                context,
                snapshot.error!,
                snapshot.stackTrace,
              ) ??
              const SizedBox();
        }
        if (!snapshot.hasData) {
          return const SizedBox();
        }
        return Image.memory(
          snapshot.data!.data,
          fit: BoxFit.cover,
          opacity: opacity,
          frameBuilder: frameBuilder,
          errorBuilder: errorBuilder,
        );
      },
    );
  }
}
