import 'package:flutter/material.dart';

/// RTN's colours: deep teal with a rust accent.
abstract final class RtnColors {
  static const Color teal = Color(0xFF0F766E);
  static const Color tealBright = Color(0xFF2DD4BF);
  static const Color rust = Color(0xFFC2410C);
  static const Color rustBright = Color(0xFFFB923C);
  static const Color paper = Color(0xFFF7F5F2);
  static const Color night = Color(0xFF0E1414);
}

ThemeData rtnTheme(Brightness brightness) {
  final bool dark = brightness == Brightness.dark;
  final ColorScheme scheme = ColorScheme.fromSeed(
    seedColor: RtnColors.teal,
    brightness: brightness,
  ).copyWith(
    primary: dark ? RtnColors.tealBright : RtnColors.teal,
    onPrimary: dark ? RtnColors.night : Colors.white,
    secondary: dark ? RtnColors.rustBright : RtnColors.rust,
    onSecondary: dark ? RtnColors.night : Colors.white,
    surface: dark ? RtnColors.night : RtnColors.paper,
  );
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: scheme.surface,
    cardTheme: CardThemeData(
      elevation: 0,
      color: dark ? const Color(0xFF162020) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      margin: EdgeInsets.zero,
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
    ),
  );
}
