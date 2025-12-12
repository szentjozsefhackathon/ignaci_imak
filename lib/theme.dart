import 'package:flutter/material.dart';

// https://konyvjelzo.jezsuita.hu/arculat/
const kThemeSeedColor = Color(0xFFBA0527);

enum AppThemeMode { system, light, dark, oled }

class AppTheme {
  AppTheme._();

  static ThemeData get lightTheme => createTheme(Brightness.light);
  static ThemeData get darkTheme => createTheme(Brightness.dark);
  static ThemeData get oledTheme {
    final baseTheme = darkTheme;
    return baseTheme.copyWith(
      scaffoldBackgroundColor: Colors.black,
      colorScheme: baseTheme.colorScheme.copyWith(surface: Colors.black),
    );
  }

  static ThemeData createTheme(Brightness brightness) => ThemeData(
    brightness: brightness,
    colorScheme: ColorScheme.fromSeed(
      seedColor: kThemeSeedColor,
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.content,
      contrastLevel: 1,
    ),
    appBarTheme: const AppBarTheme(titleSpacing: 0),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    // ignore: deprecated_member_use

    // Example of manual color adjustments for dark mode
    // colorScheme: brightness == Brightness.dark
    //     ? ColorScheme.fromSeed(
    //         seedColor: kSeedColor,
    //         brightness: brightness,
    //       ).copyWith(background: Colors.grey[800]) // Adjust background color
    //     : ColorScheme.fromSeed(seedColor: kSeedColor, brightness: brightness),
    // ignore: deprecated_member_use
    progressIndicatorTheme: const ProgressIndicatorThemeData(year2023: false),
    // ignore: deprecated_member_use
    sliderTheme: const SliderThemeData(year2023: false),
  );
}
