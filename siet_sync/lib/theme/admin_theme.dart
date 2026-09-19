import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens for VisionGate Admin Panel.
/// Light-mode default with full dark-mode support.
class AdminColors {
  // --- Light Theme Colors (Default) ---
  static const surface = Color(0xFFF8FAFC); // Page background (Slate 50)
  static const card = Color(0xFFFFFFFF); // Card background
  static const cardElevated = Color(0xFFFFFFFF); // Raised card
  static const cardTinted = Color(0xFFF1F5F9); // Subtle container (Slate 100)

  // Primary Brand Colors
  static const primary = Color(0xFF4F46E5); // Indigo 600
  static const primaryDark = Color(0xFF3730A3); // Indigo 800
  static const primaryLight = Color(0xFF818CF8); // Indigo 400
  static const primarySoft = Color(0xFFEEF2FF); // Indigo 50 (soft tint)

  // Secondary & Accents
  static const success = Color(0xFF059669); // Emerald 600
  static const successSoft = Color(0xFFECFDF5); // Emerald 50
  static const danger = Color(0xFFDC2626); // Red 600
  static const dangerSoft = Color(0xFFFEF2F2); // Red 50
  static const warning = Color(0xFFD97706); // Amber 600
  static const warningSoft = Color(0xFFFFFBEB); // Amber 50
  static const rose = Color(0xFFE11D48); // Rose 600
  static const roseSoft = Color(0xFFFFF1F2); // Rose 50
  static const info = Color(0xFF0284C7); // Sky 600
  static const infoSoft = Color(0xFFF0F9FF); // Sky 50

  // Neutral Text
  static const textPrimary = Color(0xFF0F172A); // Slate 900
  static const textSecondary = Color(0xFF475569); // Slate 600
  static const textMuted = Color(0xFF94A3B8); // Slate 400

  // Borders & Dividers
  static const border = Color(0xFFE2E8F0); // Slate 200
  static const borderFocus = Color(0xFF4F46E5); // Indigo 600

  // --- Dark Theme Equivalents ---
  static const dSurface = Color(0xFF0F172A); // Slate 900
  static const dCard = Color(0xFF1E293B); // Slate 800
  static const dCardElevated = Color(0xFF334155); // Slate 700
  static const dCardTinted = Color(0xFF1E293B);
  static const dTextPrimary = Color(0xFFF8FAFC); // Slate 50
  static const dTextSecondary = Color(0xFF94A3B8); // Slate 400
  static const dTextMuted = Color(0xFF64748B); // Slate 500
  static const dBorder = Color(0xFF334155); // Slate 700

  // Context-aware color getters based on brightness
  static Color getSurface(bool isDark) => isDark ? dSurface : surface;
  static Color getCard(bool isDark) => isDark ? dCard : card;
  static Color getCardElevated(bool isDark) => isDark ? dCardElevated : cardElevated;
  static Color getCardTinted(bool isDark) => isDark ? dCardTinted : cardTinted;
  static Color getTextPrimary(bool isDark) => isDark ? dTextPrimary : textPrimary;
  static Color getTextSecondary(bool isDark) => isDark ? dTextSecondary : textSecondary;
  static Color getTextMuted(bool isDark) => isDark ? dTextMuted : textMuted;
  static Color getBorder(bool isDark) => isDark ? dBorder : border;
}

class AdminRadii {
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 20.0;
  static const double xxl = 24.0;
  static const double circular = 999.0;
}

class AdminDurations {
  static const fast = Duration(milliseconds: 150);
  static const normal = Duration(milliseconds: 250);
  static const slow = Duration(milliseconds: 400);
}

class AdminShadows {
  static const sm = [
    BoxShadow(color: Color(0x0A000000), blurRadius: 4, offset: Offset(0, 1)),
  ];

  static const md = [
    BoxShadow(color: Color(0x12000000), blurRadius: 10, offset: Offset(0, 4)),
  ];

  static const lg = [
    BoxShadow(color: Color(0x1F000000), blurRadius: 20, offset: Offset(0, 8)),
  ];

  static List<BoxShadow> glow(Color color, {double opacity = 0.25}) {
    return [
      BoxShadow(color: color.withValues(alpha: opacity), blurRadius: 16, offset: const Offset(0, 4)),
    ];
  }
}

/// Central typography system built on Google Fonts Inter.
class AdminTextStyles {
  static TextStyle displayLg(bool isDark, {Color? color}) => GoogleFonts.inter(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: color ?? AdminColors.getTextPrimary(isDark),
        letterSpacing: -0.5,
      );

  static TextStyle titleLg(bool isDark, {Color? color}) => GoogleFonts.inter(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: color ?? AdminColors.getTextPrimary(isDark),
        letterSpacing: -0.3,
      );

  static TextStyle titleMd(bool isDark, {Color? color}) => GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: color ?? AdminColors.getTextPrimary(isDark),
      );

  static TextStyle bodyMd(bool isDark, {Color? color}) => GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: color ?? AdminColors.getTextPrimary(isDark),
      );

  static TextStyle bodySm(bool isDark, {Color? color}) => GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        color: color ?? AdminColors.getTextSecondary(isDark),
      );

  static TextStyle labelSm(bool isDark, {Color? color}) => GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: color ?? AdminColors.getTextSecondary(isDark),
      );

  static TextStyle micro(bool isDark, {Color? color}) => GoogleFonts.inter(
        fontSize: 11,
        fontWeight: FontWeight.w400,
        color: color ?? AdminColors.getTextMuted(isDark),
      );

  static TextStyle caption(bool isDark, {Color? color}) => labelSm(isDark, color: color);

  static TextStyle h2(bool isDark, {Color? color}) => titleLg(isDark, color: color);
}

/// Helper theme builds for MaterialApp
class AdminThemeData {
  static ThemeData lightTheme() {
    final base = ThemeData.light(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: AdminColors.surface,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AdminColors.primary,
        brightness: Brightness.light,
        surface: AdminColors.surface,
      ),
      textTheme: GoogleFonts.interTextTheme(base.textTheme),
      cardTheme: CardThemeData(
        color: AdminColors.card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AdminRadii.lg),
          side: const BorderSide(color: AdminColors.border),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AdminColors.card,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: const IconThemeData(color: AdminColors.textPrimary),
        titleTextStyle: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: AdminColors.textPrimary,
        ),
      ),
    );
  }

  static ThemeData darkTheme() {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: AdminColors.dSurface,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AdminColors.primary,
        brightness: Brightness.dark,
        surface: AdminColors.dSurface,
      ),
      textTheme: GoogleFonts.interTextTheme(base.textTheme),
      cardTheme: CardThemeData(
        color: AdminColors.dCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AdminRadii.lg),
          side: const BorderSide(color: AdminColors.dBorder),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AdminColors.dCard,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: const IconThemeData(color: AdminColors.dTextPrimary),
        titleTextStyle: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: AdminColors.dTextPrimary,
        ),
      ),
    );
  }
}
