import 'package:flutter/material.dart';

/// RTN's colours: deep teal with a rust accent, on an off-white or a
/// near-black page. Nothing yellow, and no other operator's colours.
abstract final class RtnColors {
  static const Color teal = Color(0xFF0F766E);
  static const Color tealDeep = Color(0xFF0B4F4A);
  static const Color tealLight = Color(0xFF5EEAD4);
  static const Color rust = Color(0xFFC2410C);
  static const Color rustLight = Color(0xFFFB923C);
  static const Color paper = Color(0xFFF7F5F2);
  static const Color night = Color(0xFF0E1414);
  static const Color good = Color(0xFF15803D);
  static const Color goodLight = Color(0xFF4ADE80);
  static const Color warn = Color(0xFFB45309);
  static const Color bad = Color(0xFFB91C1C);
  static const Color badLight = Color(0xFFF87171);
}

ThemeData rtnTheme(Brightness brightness) {
  final bool dark = brightness == Brightness.dark;
  final ColorScheme scheme = ColorScheme.fromSeed(
    seedColor: RtnColors.teal,
    brightness: brightness,
    primary: dark ? RtnColors.tealLight : RtnColors.teal,
    onPrimary: dark ? RtnColors.night : Colors.white,
    secondary: dark ? RtnColors.rustLight : RtnColors.rust,
    onSecondary: dark ? RtnColors.night : Colors.white,
    surface: dark ? RtnColors.night : RtnColors.paper,
    error: dark ? RtnColors.badLight : RtnColors.bad,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    fontFamily: 'Manrope',
    package: 'dartvel_flutter',
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 400),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFFE7F5F3) : RtnColors.tealDeep,
        borderRadius: BorderRadius.circular(6),
      ),
      textStyle: TextStyle(color: dark ? RtnColors.night : Colors.white, fontSize: 13),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      filled: true,
      fillColor: dark ? const Color(0xFF162020) : Colors.white,
    ),
  );
}

/// The reader's choice of light or dark, kept for the app in `DV.global`.
/// Replaced, never changed, so `context.global` redraws whoever reads it.
class const ThemeChoice({final ThemeMode mode = ThemeMode.system}) {
  ThemeChoice next(Brightness showing) =>
      ThemeChoice(mode: showing == Brightness.dark ? ThemeMode.light : ThemeMode.dark);
}
