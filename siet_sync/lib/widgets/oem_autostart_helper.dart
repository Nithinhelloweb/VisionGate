import 'package:flutter/services.dart';

/// Launches the OEM-specific battery or auto-start settings screen.
///
/// Most Chinese OEMs (Xiaomi, Samsung, OnePlus, Oppo, Vivo, Huawei) ship
/// proprietary battery killers that kill services even when the standard
/// Android battery-optimisation exemption is granted. This helper attempts
/// to open the correct screen for the detected OEM.
///
/// Returns `true` if an OEM-specific screen was successfully launched.
class OemAutostartHelper {
  static const _channel = MethodChannel('attendance');

  /// Attempt to open the OEM battery / auto-start settings screen.
  ///
  /// Falls back to the standard battery-optimisation page if no OEM screen
  /// is found.  Returns `false` if nothing could be opened at all.
  static Future<bool> launchOemBatterySettings() async {
    try {
      final result = await _channel.invokeMethod<bool>('launchOemBatterySettings');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }
}
