import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const Color bg = Color(0xFF090915);
  static const Color surface1 = Color(0xFF1A1A38);
  static const Color surface2 = Color(0xFF101024);
  static const Color line = Color(0x12FFFFFF); // rgba(255,255,255,.07) approx
  static const Color primary = Color(0xFF8B3AE8);
  static const Color primaryLight = Color(0xFFA855F7);
  static const Color pink = Color(0xFFFF2D9B);
  static const Color green = Color(0xFF10B981);
  static const Color amber = Color(0xFFF59E0B);
  static const Color red = Color(0xFFEF4444);
  static const Color text = Color(0xFFFFFFFF);
  static const Color muted = Color(0xFF9A9BB2);
  static const Color blueLight = Color(0xFFA9D4FF);
}

class AppTheme {
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: Colors.transparent,
      colorScheme: const ColorScheme.dark(
        surface: AppColors.surface1,
        primary: AppColors.primary,
        secondary: AppColors.primaryLight,
        error: AppColors.red,
        onSurface: AppColors.text,
      ),
      textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme)
          .copyWith(
            displayLarge: GoogleFonts.inter(
              color: AppColors.text,
              fontWeight: FontWeight.w900,
            ),
            displayMedium: GoogleFonts.inter(
              color: AppColors.text,
              fontWeight: FontWeight.w900,
            ),
            displaySmall: GoogleFonts.inter(
              color: AppColors.text,
              fontWeight: FontWeight.w700,
            ),
            headlineLarge: GoogleFonts.inter(
              color: AppColors.text,
              fontWeight: FontWeight.w700,
            ),
            titleLarge: GoogleFonts.inter(
              color: AppColors.text,
              fontWeight: FontWeight.w700,
            ),
            bodyLarge: GoogleFonts.inter(
              color: AppColors.text,
              fontWeight: FontWeight.w400,
            ),
            bodyMedium: GoogleFonts.inter(
              color: AppColors.muted,
              fontWeight: FontWeight.w400,
            ),
          ),
    );
  }
}
