import 'package:flutter/material.dart';

class AppTheme {
  static ThemeData light() {
    return ThemeData(
      colorScheme: const ColorScheme(
        brightness: Brightness.light,
        primary: Color(0xFF006A6A),
        onPrimary: Color(0xFFFFFFFF),
        primaryContainer: Color(0xFF6FF5F5),
        onPrimaryContainer: Color(0xFF002020),
        secondary: Color(0xFF4A6363),
        onSecondary: Color(0xFFFFFFFF),
        secondaryContainer: Color(0xFFCCE8E7),
        onSecondaryContainer: Color(0xFF051F1F),
        tertiary: Color(0xFF4B6078),
        onTertiary: Color(0xFFFFFFFF),
        tertiaryContainer: Color(0xFFD3E4FF),
        onTertiaryContainer: Color(0xFF041C31),
        error: Color(0xFFBA1A1A),
        onError: Color(0xFFFFFFFF),
        errorContainer: Color(0xFFFFDAD6),
        onErrorContainer: Color(0xFF410002),
        surface: Color(0xFFF4FBFA),
        onSurface: Color(0xFF161D1D),
        surfaceContainerHighest: Color(0xFFDAE5E4),
        onSurfaceVariant: Color(0xFF3F4948),
        outline: Color(0xFF6F7979),
        outlineVariant: Color(0xFFBEC9C8),
        shadow: Color(0xFF000000),
        scrim: Color(0xFF000000),
        inverseSurface: Color(0xFF2B3231),
        onInverseSurface: Color(0xFFECF2F1),
        inversePrimary: Color(0xFF4DDADA),
      ),
      useMaterial3: true,
    );
  }

  static ThemeData dark() {
    return ThemeData(
      colorScheme: const ColorScheme(
        brightness: Brightness.dark,
        primary: Color(0xFF4DDADA),
        onPrimary: Color(0xFF003737),
        primaryContainer: Color(0xFF004F4F),
        onPrimaryContainer: Color(0xFF6FF5F5),
        secondary: Color(0xFFB0CCCB),
        onSecondary: Color(0xFF1B3434),
        secondaryContainer: Color(0xFF324B4B),
        onSecondaryContainer: Color(0xFFCCE8E7),
        tertiary: Color(0xFFB2C8E5),
        onTertiary: Color(0xFF1B3147),
        tertiaryContainer: Color(0xFF33485F),
        onTertiaryContainer: Color(0xFFD3E4FF),
        error: Color(0xFFFFB4AB),
        onError: Color(0xFF690005),
        errorContainer: Color(0xFF93000A),
        onErrorContainer: Color(0xFFFFDAD6),
        surface: Color(0xFF0E1414),
        onSurface: Color(0xFFDEE3E2),
        surfaceContainerHighest: Color(0xFF3A4342),
        onSurfaceVariant: Color(0xFFBEC9C8),
        outline: Color(0xFF889392),
        outlineVariant: Color(0xFF3F4948),
        shadow: Color(0xFF000000),
        scrim: Color(0xFF000000),
        inverseSurface: Color(0xFFDEE3E2),
        onInverseSurface: Color(0xFF2B3231),
        inversePrimary: Color(0xFF006A6A),
      ),
      useMaterial3: true,
    );
  }
}
