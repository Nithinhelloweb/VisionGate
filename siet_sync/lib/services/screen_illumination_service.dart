import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:screen_brightness/screen_brightness.dart';
import '../utils/platform_utils.dart';

/// Service responsible for managing screen illumination (Screen Flash) during
/// front-camera face attendance capture in low-light environments.
class ScreenIlluminationService with WidgetsBindingObserver {
  static final ScreenIlluminationService instance = ScreenIlluminationService._internal();

  ScreenIlluminationService._internal() {
    WidgetsBinding.instance.addObserver(this);
  }

  bool _isIlluminating = false;
  bool _isLowLightDetected = false;
  double? _originalBrightness;
  bool _isInitialized = false;

  final ValueNotifier<bool> isIlluminatingNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isLowLightDetectedNotifier = ValueNotifier<bool>(false);

  bool get isIlluminating => _isIlluminating;
  bool get isLowLightDetected => _isLowLightDetected;

  /// Default luminance threshold (0 - 255) below which frame is flagged as low light
  static const double defaultLowLightThreshold = 70.0;

  /// Initializes the service and caches the baseline system brightness
  Future<void> init() async {
    if (_isInitialized) return;
    try {
      if (AppPlatform.isMobile) {
        _originalBrightness = await ScreenBrightness().system;
      }
    } catch (e) {
      debugPrint('[ScreenIllumination] Could not query initial brightness: $e');
    } finally {
      _isInitialized = true;
    }
  }

  /// Evaluates whether an image's average luminance indicates low light
  static bool evaluateImageLuminanceIsLow(Uint8List imageBytes, {double threshold = defaultLowLightThreshold}) {
    try {
      final decoded = img.decodeImage(imageBytes);
      if (decoded == null) return false;

      final grayscale = decoded.numChannels == 3 ? img.grayscale(decoded) : decoded;
      int totalLuminance = 0;
      int pixelCount = 0;

      // Subsample pixels for speed (step = 8)
      final step = (grayscale.width * grayscale.height > 10000) ? 8 : 2;

      for (int y = 0; y < grayscale.height; y += step) {
        for (int x = 0; x < grayscale.width; x += step) {
          final pixel = grayscale.getPixel(x, y);
          totalLuminance += pixel.r.toInt();
          pixelCount++;
        }
      }

      if (pixelCount == 0) return false;
      final avgLuminance = totalLuminance / pixelCount;
      return avgLuminance < threshold;
    } catch (e) {
      debugPrint('[ScreenIllumination] Error calculating luminance: $e');
      return false;
    }
  }

  /// Activates high screen brightness (default: 1.0) and updates state
  Future<void> activate({double targetBrightness = 1.0, bool isAutoTriggered = false}) async {
    if (_isIlluminating) return;

    if (isAutoTriggered) {
      _isLowLightDetected = true;
      isLowLightDetectedNotifier.value = true;
    }

    try {
      if (AppPlatform.isMobile) {
        // Cache original brightness before elevating
        _originalBrightness ??= await ScreenBrightness().system;
        await ScreenBrightness().setApplicationScreenBrightness(targetBrightness);
      }
    } catch (e) {
      debugPrint('[ScreenIllumination] Error setting screen brightness: $e');
    } finally {
      _isIlluminating = true;
      isIlluminatingNotifier.value = true;
    }
  }

  /// Restores initial screen brightness and resets illumination state
  Future<void> restore() async {
    if (!_isIlluminating) {
      _isLowLightDetected = false;
      isLowLightDetectedNotifier.value = false;
      return;
    }

    try {
      if (AppPlatform.isMobile) {
        if (_originalBrightness != null) {
          await ScreenBrightness().setApplicationScreenBrightness(_originalBrightness!);
        } else {
          await ScreenBrightness().resetApplicationScreenBrightness();
        }
      }
    } catch (e) {
      debugPrint('[ScreenIllumination] Error resetting screen brightness: $e');
    } finally {
      _isIlluminating = false;
      _isLowLightDetected = false;
      isIlluminatingNotifier.value = false;
      isLowLightDetectedNotifier.value = false;
    }
  }

  /// Toggles illumination manually
  Future<void> toggle() async {
    if (_isIlluminating) {
      await restore();
    } else {
      await activate(isAutoTriggered: false);
    }
  }

  /// Mark low light status flag
  void setLowLightDetected(bool detected) {
    _isLowLightDetected = detected;
    isLowLightDetectedNotifier.value = detected;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Failsafe: if the app is paused, hidden, or detached, restore user's original brightness immediately
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      if (_isIlluminating) {
        restore();
      }
    }
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    restore();
  }
}
