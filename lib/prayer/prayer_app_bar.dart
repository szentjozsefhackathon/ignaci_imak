import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/prayer.dart';
import '../data/prayer_group.dart';
import 'prayer_image.dart';

class PrayerAppBar extends StatelessWidget {
  const PrayerAppBar.group({
    super.key,
    required this.group,
    this.options,
    this.actions,
  }) : prayer = null;

  const PrayerAppBar.prayer({
    super.key,
    required this.group,
    required this.prayer,
    this.options,
    this.actions,
  });

  final PrayerGroup group;
  final Prayer? prayer;
  final PrayerAppBarOptions? options;
  final List<Widget>? actions;

  Widget buildTitle(PrayerAppBarOptions opts, bool singleLine) =>
      opts.subtitleVisible
      ? Text.rich(
          TextSpan(
            children: [
              TextSpan(text: prayer!.title),
              const TextSpan(text: '\n'),
              TextSpan(text: group.title, style: const TextStyle(fontSize: 14)),
            ],
          ),
          maxLines: singleLine ? 2 : null,
          overflow: singleLine ? TextOverflow.ellipsis : TextOverflow.visible,
        )
      : Text(
          prayer?.title ?? group.title,
          maxLines: singleLine ? 1 : null,
          overflow: singleLine ? TextOverflow.ellipsis : TextOverflow.visible,
        );

  @override
  Widget build(BuildContext context) {
    final opts = options ?? PrayerAppBarOptions(context, prayer != null);

    final background = PrayerImage(
      name: prayer?.image ?? group.image,
      opacity: const AlwaysStoppedAnimation(.3),
      errorBuilder: null,
    );

    return SliverAppBar.large(
      expandedHeight: opts.expandedHeight,
      collapsedHeight: opts.collapsedHeight,
      toolbarHeight: opts.collapsedHeight,
      stretch: true,
      //title: buildTitle(opts, true),
      actions: actions,
      flexibleSpace: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final currentHeight = constraints.biggest.height;
          final double difference = opts.expandedHeight - opts.collapsedHeight;
          double percentage;
          if (difference <= 0) {
            // If expandedHeight is not greater than collapsedHeight,
            // the space bar cannot expand. Treat it as fully collapsed.
            percentage = 0.0;
          } else {
            percentage = (currentHeight - opts.collapsedHeight) / difference;
          }
          percentage = percentage.clamp(0.0, 1.0); // Clamp the final percentage
          final t = (percentage * 10).roundToDouble() / 10;
          return FlexibleSpaceBar(
            title: buildTitle(opts, percentage < 0.2),
            titlePadding: EdgeInsets.fromLTRB(
              Tween<double>(begin: 56, end: 24).transform(t),
              14,
              actions == null
                  ? 12
                  : Tween<double>(
                      begin: (actions!.length * kMinInteractiveDimension) + 12,
                      end: 12,
                    ).transform(t),
              // add more bottom padding when subtitle is visible
              opts.subtitleVisible
                  ? Tween<double>(begin: 24, end: 14).transform(t)
                  : 14,
            ),
            background: background,
          );
        },
      ),
    );
  }
}

class PrayerAppBarOptions {
  factory PrayerAppBarOptions(BuildContext context, bool groupAndPrayer) {
    final mq = MediaQuery.of(context);
    final screenSize = mq.size;
    final hasSubtitle = groupAndPrayer && screenSize.width > 600;
    final collapsedHeight = mq.padding.top + kToolbarHeight;

    return PrayerAppBarOptions._(
      collapsedHeight: collapsedHeight,
      expandedHeight: math.max(
        screenSize.height * 0.3,
        collapsedHeight + kToolbarHeight,
      ),
      subtitleVisible: hasSubtitle,
    );
  }

  PrayerAppBarOptions._({
    required this.collapsedHeight,
    required this.expandedHeight,
    required this.subtitleVisible,
  });

  final double collapsedHeight;
  final double expandedHeight;
  final bool subtitleVisible;
}
