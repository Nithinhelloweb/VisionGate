/// Centralized responsive layout system for VisionGate Admin Panel.
/// Ensures consistent layout scaling across all device classes.
class AdminBreakpoints {
  // Device Breakpoints (dp)
  static const double xs = 360.0;   // Extra-small phones (e.g. Galaxy A03, iPhone SE)
  static const double sm = 390.0;   // Standard mobile (e.g. iPhone 14, Pixel 7)
  static const double md = 430.0;   // Large mobile (e.g. iPhone 14 Pro Max, S23 Ultra)
  static const double lg = 600.0;   // Small tablets / Foldables open (e.g. iPad Mini)
  static const double xl = 840.0;   // Medium tablets (e.g. iPad Air, Tab S8)
  static const double xxl = 1280.0; // Desktop / Large tablet landscape

  // Device Class Checkers
  static bool isXSmall(double w) => w < xs;
  static bool isSmallPhone(double w) => w < sm;
  static bool isPhone(double w) => w < lg;
  static bool isTablet(double w) => w >= lg && w < xxl;
  static bool isDesktop(double w) => w >= xxl;

  // Layout Spacing Helpers
  static double pagePadding(double width) {
    if (width < xs) return 10.0;
    if (width < sm) return 12.0;
    if (width < md) return 16.0;
    if (width < lg) return 20.0;
    return 24.0;
  }

  static double cardPadding(double width) {
    if (width < xs) return 10.0;
    if (width < sm) return 12.0;
    return 16.0;
  }

  static double titleFontSize(double width) {
    if (width < xs) return 16.0;
    if (width < sm) return 18.0;
    if (width < md) return 20.0;
    return 22.0;
  }

  static double statValueFontSize(double width) {
    if (width < xs) return 20.0;
    if (width < sm) return 24.0;
    return 28.0;
  }

  static int statGridColumns(double width) {
    if (width < 320.0) return 1;  // Only ultra-narrow screens < 320px use 1 col
    if (width < lg) return 2;     // 2-column grid on all mobile screens (320px - 600px)
    if (width < xl) return 3;     // 3-column grid on small tablets
    return 4;                     // 4-column grid on large screen/desktop
  }

  static double navRailWidth(double width) {
    if (width >= xxl) return 220.0; // Extended sidebar showing labels
    return 72.0;                   // Compact icon-only rail
  }

  static double maxContentWidth(double width) {
    return 1400.0;
  }
}
