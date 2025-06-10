import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/widgets.dart';

class PrayerText extends StatelessWidget {
  const PrayerText(
    this.text, {
    super.key,
    this.minFontSize = 12,
    this.maxFontSize = kDefaultFontSize,
    this.stepGranularity = 1,
    this.textAlign = TextAlign.center,
    this.style = kDefaultStyle,
    this.padding = kDefaultPadding,
  });

  static const kDefaultFontSize = 24.0;
  static const kDefaultStyle = TextStyle(
    fontSize: kDefaultFontSize,
    height: 1.5,
  );
  static const kDefaultPadding = EdgeInsets.all(38);

  final String text;
  final double minFontSize;
  final double maxFontSize;
  final double stepGranularity;
  final TextAlign textAlign;
  final TextStyle? style;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: Center(
      child: ConstrainedBox(
        constraints: BoxConstraints.loose(const Size.fromWidth(600)),
        child: AutoSizeText(
          text,
          minFontSize: minFontSize,
          maxFontSize: maxFontSize,
          stepGranularity: stepGranularity,
          textAlign: textAlign,
          style: style,
        ),
      ),
    ),
  );
}
