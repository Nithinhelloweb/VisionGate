import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

/// Centralized platform detection and capabilities utility
class AppPlatform {
  /// True if running on Web browser
  static bool get isWeb => kIsWeb;

  /// True if running on Windows desktop
  static bool get isWindows => !kIsWeb && Platform.isWindows;

  /// True if running on Linux desktop
  static bool get isLinux => !kIsWeb && Platform.isLinux;

  /// True if running on macOS desktop
  static bool get isMacOS => !kIsWeb && Platform.isMacOS;

  /// True if running on Android mobile/tablet
  static bool get isAndroid => !kIsWeb && Platform.isAndroid;

  /// True if running on iOS mobile/tablet
  static bool get isIOS => !kIsWeb && Platform.isIOS;

  /// True if running on any desktop platform (Windows, Linux, macOS)
  static bool get isDesktop => !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  /// True if running on any mobile platform (Android, iOS)
  static bool get isMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// Human readable platform name
  static String get platformName {
    if (kIsWeb) return 'web';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return 'unknown';
  }

  /// Client platform string for backend API ('web' or 'app')
  static String get clientPlatformTag => kIsWeb ? 'web' : 'app';

  /// Whether the platform supports mobile background location permissions (Allow all time)
  static bool get supportsAlwaysOnLocation => isAndroid || isIOS;

  /// Whether the platform uses mobile runtime notifications permission request
  static bool get requiresMobileNotificationPermission => isAndroid || isIOS;
}
