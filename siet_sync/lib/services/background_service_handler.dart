import 'package:flutter/services.dart';

/// Manage background location updates via native Android foreground service.
/// The service runs in a separate `:attendance_service` process, meaning it
/// survives app swipe, Doze mode, and device reboot (via BootReceiver).
class BackgroundLocationService {
  static const MethodChannel _channel = MethodChannel('attendance');

  static Future<void> initialize() async {
    // Native service handles its own initialisation — no-op on Dart side.
  }

  /// Start the background service.
  static Future<void> start({
    required String baseUrl,
    required double geofenceLat,
    required double geofenceLng,
    required double geofenceRadius,
    required String token,
    required String regNo,
    required String deviceSessionId,
  }) async {
    try {
      await _channel.invokeMethod('startService', {
        'baseUrl': baseUrl,
        'geofenceLat': geofenceLat,
        'geofenceLng': geofenceLng,
        'geofenceRadius': geofenceRadius,
        'token': token,
        'regNo': regNo,
        'deviceSessionId': deviceSessionId,
      });
    } catch (_) {}
  }

  /// Stop the background service.
  static Future<void> stop() async {
    try {
      await _channel.invokeMethod('stopService');
    } catch (_) {}
  }

  /// Restart the background service using stored native session credentials.
  static Future<bool> restart() async {
    try {
      final result = await _channel.invokeMethod<bool>('restartService');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Returns `true` if Android battery optimisation is disabled for this app.
  /// Always returns `true` on non-Android platforms.
  static Future<bool> isIgnoringBatteryOptimisations() async {
    try {
      final result = await _channel.invokeMethod<bool>('isIgnoringBatteryOptimisations');
      return result ?? false;
    } catch (_) {
      return true; // non-Android: no battery restriction concept
    }
  }

  /// Opens the system battery-optimisation exemption dialog.
  /// Must be called from a user-initiated action (e.g. a settings button tap).
  static Future<void> requestBatteryOptimisationExemption() async {
    try {
      await _channel.invokeMethod('requestBatteryOptimisationExemption');
    } catch (_) {}
  }

  /// Returns the current service health status.
  /// `running` — whether the foreground service process is alive.
  /// `batteryExempt` — whether battery optimisation is disabled.
  static Future<({bool running, bool batteryExempt})> getServiceStatus() async {
    try {
      final result = await _channel.invokeMethod<Map>('getServiceStatus');
      if (result != null) {
        return (
          running: result['running'] as bool? ?? false,
          batteryExempt: result['batteryExempt'] as bool? ?? false,
        );
      }
    } catch (_) {}
    return (running: false, batteryExempt: true);
  }

  /// No-op — notification content is managed entirely by the native service.
  static void updateNotification({required bool isTracking, String? customContent}) {}
}
