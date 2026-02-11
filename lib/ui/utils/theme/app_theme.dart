import 'package:flutter/material.dart';

class AppTheme {
  static const Color background = Color(0xFF1E1E2E);
  static const Color sidebar = Color(0xFF252536);
  static const Color primary = Color(0xFF89B4FA);
  static const Color accent = Color(0xFFCBA6F7);
  static const Color text = Color(0xFFCDD6F4);
  static const Color surface = Color(0xFF313244);
  static const Color destructive = Color(0xFFF38BA8); // Catppuccin Red
  static const Color border = Color(0xFFE0E0E0);

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      primaryColor: primary,
      colorScheme: const ColorScheme.dark(
        primary: primary,
        secondary: accent,
        surface: surface,
        surfaceContainerHighest: background,
      ),
      textTheme: ThemeData.dark().textTheme.apply(
        bodyColor: text,
        displayColor: text,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: sidebar,
        elevation: 0,
        centerTitle: false,
      ),
      // cardTheme: CardTheme(
      //   color: surface,
      //   elevation: 0,
      //   shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      // ),
    );
  }
}
