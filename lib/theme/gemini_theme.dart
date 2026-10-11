import 'package:flutter/material.dart';

/// Design tokens and styling for the DropSync Gemini Aesthetic.
class GeminiTheme {
  // Core Color Palette
  static const Color deepVoid = Color(0xFF0E0E10);
  static const Color surfaceContainer = Color(0xFF1E1F22);
  static const Color surfaceVariant = Color(0xFF28292A);
  static const Color surfaceElevated = Color(0xFF333538);

  // Gemini Glow Gradients & Accents
  static const Color electricBlue = Color(0xFF4E75FF);
  static const Color cyan = Color(0xFF56C5FE);
  static const Color lavender = Color(0xFF9B72CF);
  static const Color emeraldGreen = Color(0xFF34D399);
  static const Color amberWarning = Color(0xFFFBBF24);
  static const Color coralError = Color(0xFFF87171);

  // Typography Colors
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF9AA0A6);
  static const Color textMuted = Color(0xFF6B7280);

  // Signature Gemini Glow Gradients
  static const LinearGradient geminiGlowGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      electricBlue,
      cyan,
      lavender,
    ],
  );

  static const LinearGradient geminiHorizontalGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [
      electricBlue,
      cyan,
      lavender,
    ],
  );

  static const SweepGradient radarSweepGradient = SweepGradient(
    colors: [
      Colors.transparent,
      Color(0x3356C5FE),
      Color(0x884E75FF),
      cyan,
    ],
    stops: [0.0, 0.4, 0.8, 1.0],
  );

  // Thin Luminous Borders
  static Border thinBorder = Border.all(
    color: Colors.white.withOpacity(0.08),
    width: 1.0,
  );

  static Border activeGlowBorder = Border.all(
    color: cyan.withOpacity(0.6),
    width: 1.5,
  );

  static Border lavenderGlowBorder = Border.all(
    color: lavender.withOpacity(0.6),
    width: 1.5,
  );

  // Glow Box Shadows
  static List<BoxShadow> glowShadow({Color color = electricBlue, double opacity = 0.25, double blur = 24}) => [
    BoxShadow(
      color: color.withOpacity(opacity),
      blurRadius: blur,
      spreadRadius: 2,
    ),
  ];

  static List<BoxShadow> subtleCardShadow = [
    BoxShadow(
      color: Colors.black.withOpacity(0.4),
      blurRadius: 16,
      offset: const Offset(0, 6),
    ),
  ];

  // ThemeData Definition
  static ThemeData get darkTheme {
    return ThemeData.dark(useMaterial3: true).copyWith(
      scaffoldBackgroundColor: deepVoid,
      canvasColor: deepVoid,
      cardColor: surfaceContainer,
      dialogBackgroundColor: surfaceContainer,
      colorScheme: const ColorScheme.dark(
        primary: electricBlue,
        secondary: cyan,
        tertiary: lavender,
        surface: surfaceContainer,
        surfaceContainerHighest: surfaceVariant,
        onSurface: textPrimary,
        error: coralError,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.bold,
          letterSpacing: -0.3,
        ),
        iconTheme: IconThemeData(color: textPrimary),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          foregroundColor: textPrimary,
          backgroundColor: electricBlue,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(100), // Pill button
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          side: BorderSide(color: Colors.white.withOpacity(0.12)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(100),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
      ),
      iconTheme: const IconThemeData(color: textSecondary),
      dividerTheme: DividerThemeData(
        color: Colors.white.withOpacity(0.06),
        thickness: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceVariant,
        contentTextStyle: const TextStyle(color: textPrimary),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
      ),
    );
  }
}
