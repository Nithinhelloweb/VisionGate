import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/college_ip_config.dart';
import 'vpn_check.dart';

/// Runtime settings loaded from server
class AppSettings {
  static bool allowAnyNetwork = false;
  static String collegeSSID = '';
  static bool enforceGeoFence = true;
  static bool enforceAppGeoFence = true;
  static bool enforceVpnBlocking = true;
  static bool multiUserKioskMode = false;
  static bool enableThirukkural = true;
  static final ValueNotifier<bool> thirukkuralNotifier = ValueNotifier<bool>(true);
  static bool _isLoaded = false;
  static DateTime? _lastLoaded;
  static const Duration _cacheExpiry = Duration(seconds: 10);
  static const String _prefThirukkuralKey = 'app_config_enable_thirukkural';

  /// Persist the Thirukkural flag locally and notify all listeners
  static Future<void> persistThirukkuralFlag(bool value) async {
    enableThirukkural = value;
    thirukkuralNotifier.value = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefThirukkuralKey, value);
    } catch (e) {
      debugPrint('[AppSettings] Failed to persist Thirukkural flag: $e');
    }
  }

  /// Hydrate the Thirukkural flag from local storage immediately
  static Future<bool> hydrateThirukkuralFlag() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.containsKey(_prefThirukkuralKey)) {
        final saved = prefs.getBool(_prefThirukkuralKey) ?? true;
        enableThirukkural = saved;
        thirukkuralNotifier.value = saved;
        return saved;
      }
    } catch (e) {
      debugPrint('[AppSettings] Failed to hydrate Thirukkural flag: $e');
    }
    return enableThirukkural;
  }

  static void updateThirukkural(bool value) {
    persistThirukkuralFlag(value);
  }

  /// Fetch settings from server
  static Future<void> loadSettings({bool forceRefresh = false}) async {
    // Hydrate cached local flag first so offline / cold boot state is respected
    if (!_isLoaded) {
      await hydrateThirukkuralFlag();
    }

    if (_isLoaded && !forceRefresh) {
      if (_lastLoaded != null &&
          DateTime.now().difference(_lastLoaded!) < _cacheExpiry) {
        return;
      }
    }

    try {
      final url = '${CollegeIPConfig.defaultURL}/settings/allow_any_network';
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        final data = Map<String, dynamic>.from(
          response.body.isNotEmpty ? jsonDecode(response.body) : {},
        );
        allowAnyNetwork = data['allow_any_network'] ?? false;
        collegeSSID = data['college_ssid'] ?? '';
        enforceGeoFence = data['enforce_geo_fence'] ?? true;
        enforceAppGeoFence = data['enforce_app_geo_fence'] ?? true;
        enforceVpnBlocking = data['enforce_vpn_blocking'] ?? true;
        multiUserKioskMode = data['multi_user_kiosk_mode'] ?? false;
        
        if (data.containsKey('enable_thirukkural')) {
          final serverVal = data['enable_thirukkural'] == true;
          await persistThirukkuralFlag(serverVal);
        }
      }
    } catch (e) {
      // Offline / network failure: keep the persisted local flag; do not clobber with hardcoded true
      if (!_isLoaded) {
        await hydrateThirukkuralFlag();
      }
    }
    _isLoaded = true;
    _lastLoaded = DateTime.now();
  }

  /// Force refresh settings from server
  static Future<void> refreshSettings() async {
    await loadSettings(forceRefresh: true);
  }

  /// Parse JSON safely - kept for backward compatibility if called elsewhere
  static Map<String, dynamic> parseJson(String body) {
    try {
      return Map<String, dynamic>.from(jsonDecode(body));
    } catch (e) {
      // Ignore parse errors - fallback to default values will be used
    }
    return {};
  }

  /// Reset for testing
  static void reset() {
    _isLoaded = false;
    _lastLoaded = null;
    allowAnyNetwork = false;
    collegeSSID = '';
    enforceGeoFence = true;
    enforceAppGeoFence = true;
    enforceVpnBlocking = true;
  }
}

/// WiFi & Local Network Checker Utility
class WifiChecker {
  static final NetworkInfo _networkInfo = NetworkInfo();

  /// Check if device is connected to WiFi or wired Ethernet (for desktop)
  static Future<bool> isWifiConnected() async {
    try {
      final result = await Connectivity().checkConnectivity();
      return result.contains(ConnectivityResult.wifi) ||
          result.contains(ConnectivityResult.ethernet) ||
          (!kIsWeb && !result.contains(ConnectivityResult.none) && result.isNotEmpty);
    } catch (e) {
      return false;
    }
  }

  /// Get current WiFi SSID
  static Future<String?> getCurrentWifiSSID() async {
    try {
      final wifiName = await _networkInfo.getWifiName();
      if (wifiName == null || wifiName.isEmpty) return null;
      // Clean up: remove quotes, whitespace, <unknown ssid>
      final cleaned = wifiName.replaceAll('"', '').replaceAll("'", '').trim();
      if (cleaned.isEmpty || cleaned.toLowerCase() == '<unknown ssid>') {
        return null;
      }
      return cleaned;
    } catch (e) {
      return null;
    }
  }

  /// Check if connected to allowed college WiFi
  static Future<bool> isOnCollegeWifi() async {
    await AppSettings.loadSettings();

    // If allow_any_network is true (toggle OFF), allow from anywhere
    if (AppSettings.allowAnyNetwork) {
      return true;
    }

    // On Web, browsers cannot inspect Wi-Fi SSID by security design;
    // Web location is validated strictly by Geofence.
    if (kIsWeb) {
      return true;
    }

    final isConnected = await isWifiConnected();
    if (!isConnected) {
      debugPrint('[WIFI] Not connected to any network');
      return false;
    }

    final requiredSSID = _getRequiredSSID();
    final ssid = await getCurrentWifiSSID();
    debugPrint('[WIFI] Current SSID: "$ssid" (Required: "$requiredSSID")');

    if (ssid != null && ssid.isNotEmpty) {
      // Case-insensitive comparison
      final matches = ssid.toLowerCase() == requiredSSID.toLowerCase();
      debugPrint('[WIFI] SSID match: $matches');
      return matches;
    }

    return false;
  }

  /// Get WiFi status message for display
  static Future<String> getWifiStatusMessage() async {
    await AppSettings.loadSettings();

    if (AppSettings.allowAnyNetwork) {
      return 'Network check disabled. You can mark attendance from any network.';
    }

    if (kIsWeb) {
      return 'Web Network: Location verified via GPS Geofence.';
    }

    final requiredSSID = _getRequiredSSID();
    final isConnected = await isWifiConnected();

    if (!isConnected) {
      return 'Not connected to network. Please connect to $requiredSSID';
    }

    final ssid = await getCurrentWifiSSID();
    if (ssid != null && ssid.isNotEmpty) {
      if (ssid.toLowerCase() == requiredSSID.toLowerCase()) {
        return 'Connected to $ssid (Allowed network)';
      } else {
        return 'Connected to $ssid (Not the required network: $requiredSSID)';
      }
    }

    return 'Please connect to $requiredSSID Wi-Fi network.';
  }

  /// Validate and return error message if not on college WiFi/network
  static Future<String?> validateCollegeWifi() async {
    await AppSettings.loadSettings();

    // Check VPN first
    final vpnError = await VpnChecker.validateVpnStatus();
    if (vpnError != null) {
      return vpnError;
    }

    if (AppSettings.allowAnyNetwork || kIsWeb) {
      return null;
    }

    final isOnCollege = await isOnCollegeWifi();

    if (!isOnCollege) {
      if (!await isWifiConnected()) {
        return 'Please connect to a Wi-Fi network to mark attendance.';
      }

      final ssid = await getCurrentWifiSSID();
      final requiredSSID = _getRequiredSSID();
      if (ssid != null && ssid.isNotEmpty && ssid.toLowerCase() != requiredSSID.toLowerCase()) {
        return 'You are connected to "$ssid". Please connect to "$requiredSSID" to mark attendance.';
      }

      return 'Please connect to "$requiredSSID" Wi-Fi network to mark attendance.';
    }

    return null;
  }

  static String _getRequiredSSID() {
    final configured = AppSettings.collegeSSID.trim();
    if (configured.isNotEmpty) return configured;
    return 'LifeatSriShakthi';
  }
}
