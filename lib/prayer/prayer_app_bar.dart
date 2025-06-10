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
          final percentage =
              (currentHeight - opts.collapsedHeight) /
              (opts.expandedHeight - opts.collapsedHeight);
          final t = (percentage * 10).roundToDouble() / 10;
          return FlexibleSpaceBar(
            title: buildTitle(opts, percentage < 0.3),
            titlePadding: EdgeInsets.fromLTRB(
              Tween<double>(begin: 56, end: 24).transform(t),
              14,
              actions == null
                  ? 12
                  : Tween<double>(
                      begin: actions!.length * kMinInteractiveDimension,
                      end: 12,
                    ).transform(t),
              14,
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

    return PrayerAppBarOptions._(
      collapsedHeight:
          mq.padding.top + (kToolbarHeight * (hasSubtitle ? 1.5 : 1)),
      expandedHeight: screenSize.height * 0.3,
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
