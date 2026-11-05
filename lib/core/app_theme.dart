import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppTheme {
  static const Color green950 = Color(0xFF0B2E24);
  static const Color green800 = Color(0xFF123832);
  static const Color green700 = Color(0xFF0A00FF);
  static const Color gold600 = Color(0xFFB8923D);
  static const Color gold500 = Color(0xFFC9A227);
  static const Color gold300 = Color(0xFFE4C766);
  static const Color cream = Color(0xFFFAF7F0);
  static const Color cream100 = Color(0xFFF2EDE0);
  static const Color ink = Color(0xFF1E2B26);
  static const Color inkMuted = Color(0xFF5A6A62);
  static const Color card = Color(0xFFFFFFFF);
  static const Color neoBlue = Color(0xFF4D73CD);

  static const Color teaGreen = green700;
  static const Color leaf = Color(0xFF26967A);
  static const Color purple = green700;
  static const Color gold = gold500;

  static const Color gradientDark = Color(0xFF0C3027);
  static const Color gradientLight = Color(0xFF26967A);
  static const Color refreshMint = Color(0xFF8FE3C4);

  static const LinearGradient splashGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [gradientDark, gradientLight],
  );

  static const ColorFilter knockoutBlack = ColorFilter.matrix(<double>[
    1,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
    0,
    1,
    1,
    1,
    0,
    0,
  ]);

  static const ColorFilter knockoutBlackToWhite = ColorFilter.matrix(<double>[
    0,
    0,
    0,
    0,
    255,
    0,
    0,
    0,
    0,
    255,
    0,
    0,
    0,
    0,
    255,
    1,
    1,
    1,
    0,
    0,
  ]);

  static SystemUiOverlayStyle get systemOverlay => const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: card,
    systemNavigationBarIconBrightness: Brightness.dark,
  );

  static ThemeData get theme {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: green700,
        primary: green700,
        secondary: gold500,
        surface: cream,
        brightness: Brightness.light,
      ),
    );

    return base.copyWith(
      scaffoldBackgroundColor: cream,
      appBarTheme: const AppBarTheme(
        backgroundColor: green950,
        foregroundColor: cream,
        elevation: 0,
        centerTitle: true,
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: gold500,
          foregroundColor: green950,
          elevation: 0,
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }
}
