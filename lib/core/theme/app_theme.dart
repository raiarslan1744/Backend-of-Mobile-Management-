import 'package:flutter/material.dart';

class AppTheme {
  static const Color lavenderTop = Color(0xFFDCCBEA);
  static const Color blueGrayMid = Color(0xFFD5E0EE);
  static const Color aquaBottom = Color(0xFFBFEFF3);
  static const Color primaryBlue = Color(0xFF112F5B);
  static const Color textWhite = Color(0xFFF7F7FF);
  static const Color fieldTint = Color(0xFFEDF4FF);

  static ThemeData get lightTheme {
    final base = ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: Colors.transparent,
      primaryColor: primaryBlue,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryBlue,
        primary: primaryBlue,
        secondary: primaryBlue,
        surface: Colors.white,
      ),
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          fontWeight: FontWeight.w300,
          letterSpacing: 0.4,
          color: textWhite,
        ),
        labelLarge: TextStyle(
          color: Colors.white70,
          fontWeight: FontWeight.w400,
        ),
      ),
    );

    return base.copyWith(
      inputDecorationTheme: InputDecorationTheme(
        filled: false,
        contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        hintStyle: const TextStyle(
          color: Color(0xFFF3F8FF),
          fontWeight: FontWeight.w300,
          letterSpacing: 0.2,
        ),
        prefixIconColor: const Color(0xFFF4F6FF),
        border: const UnderlineInputBorder(
          borderSide: BorderSide(color: Colors.white70, width: 1),
        ),
        enabledBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Colors.white70, width: 1),
        ),
        focusedBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Colors.white, width: 1.5),
        ),
      ),
    );
  }
}
