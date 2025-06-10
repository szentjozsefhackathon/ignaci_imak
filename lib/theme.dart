import 'package:flutter/material.dart';

// https://konyvjelzo.jezsuita.hu/arculat/
const kColorSchemeSeed = Color(0xffba0527);

class AppTheme {
  AppTheme._();

  static const kSeedColor = Color(0xFFBA0527);

  static ThemeData createTheme(Brightness brightness) => ThemeData(
    brightness: brightness,
    colorScheme: ColorScheme.fromSeed(
      seedColor: kSeedColor,
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.vibrant,
      contrastLevel: 1,
    ),
    appBarTheme: const AppBarTheme(titleSpacing: 0),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    // ignore: deprecated_member_use
    progressIndicatorTheme: const ProgressIndicatorThemeData(year2023: false),
    // ignore: deprecated_member_use
    sliderTheme: const SliderThemeData(year2023: false),
  );
}
