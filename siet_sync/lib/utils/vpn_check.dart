import 'dart:io';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/college_ip_config.dart';
import 'wifi_check.dart';

/// VPN Detection Utility
/// Detects active VPN connections across all platforms
class VpnChecker {
  /// Check if VPN is currently active
  static Future<bool> isVpnActive() async {
    try {
      await AppSettings.loadSettings();
      
      if (!AppSettings.enforceVpnBlocking) {
        return false;
      }

      if (kIsWeb) {
        return await _detectVpnWeb();
      } else if (Platform.isAndroid) {
        return await _detectVpnAndroid();
      } else if (Platform.isIOS) {
        return await _detectVpnIos();
      } else if (Platform.isWindows) {
        return await _detectVpnWindows();
      } else if (Platform.isLinux) {
        return await _detectVpnLinux();
      } else if (Platform.isMacOS) {
        return await _detectVpnMacos();
      }
      
      // Other platforms: default to false (allow access unless detected)
      return false;
    } catch (e) {
      debugPrint('[VPN] Detection error: $e');
      final isLocalDev = CollegeIPConfig.defaultURL.contains('localhost') ||
          CollegeIPConfig.defaultURL.contains('127.0.0.1') ||
          CollegeIPConfig.defaultURL.contains('192.168.');
      if (isLocalDev) return false;
      return false;
    }
  }

  /// Android VPN detection using official API
  static Future<bool> _detectVpnAndroid() async {
    final connectivity = Connectivity();
    final result = await connectivity.checkConnectivity();
    
    // Check if VPN is active connection
    if (result.contains(ConnectivityResult.vpn)) {
      return true;
    }
    
    // Additional check via network interfaces for VPNs that bypass connectivity API
    try {
      for (final interface in await NetworkInterface.list()) {
        final name = interface.name.toLowerCase();
        if (name.contains('tun') || 
            name.contains('tap') || 
            name.contains('ppp') ||
            name.contains('vpn') ||
            name.startsWith('utun') ||
            name.startsWith('wg')) { // WireGuard
          return true;
        }
      }
    } catch (e) {
      // Ignore interface check errors
    }
    
    return false;
  }

  /// iOS VPN detection by checking network interfaces
  static Future<bool> _detectVpnIos() async {
    try {
      for (final interface in await NetworkInterface.list()) {
        final name = interface.name.toLowerCase();
        // All iOS VPNs use utun* interfaces
        if (name.startsWith('utun') || name.contains('ppp') || name.contains('ipsec')) {
          return true;
        }
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Windows VPN detection
  static Future<bool> _detectVpnWindows() async {
    try {
      for (final interface in await NetworkInterface.list()) {
        final name = interface.name.toLowerCase();
        // Common VPN interface names on Windows
        if (name.contains('vpn') || 
            name.contains('wireguard') || 
            name.contains('openvpn') ||
            name.contains('tun') ||
            name.contains('tap') ||
            name.contains('tailscale') ||
            name.contains('wintun')) {
          return true;
        }
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Linux VPN detection
  static Future<bool> _detectVpnLinux() async {
    try {
      for (final interface in await NetworkInterface.list()) {
        final name = interface.name.toLowerCase();
        // Common VPN interface names on Linux
        if (name.startsWith('tun') ||
            name.startsWith('tap') ||
            name.startsWith('wg') ||
            name.startsWith('ppp') ||
            name.contains('vpn') ||
            name.contains('tailscale') ||
            name.contains('wireguard')) {
          return true;
        }
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// macOS VPN detection
  static Future<bool> _detectVpnMacos() async {
    try {
      for (final interface in await NetworkInterface.list()) {
        final name = interface.name.toLowerCase();
        // Common VPN interface names on macOS
        if (name.startsWith('utun') ||
            name.startsWith('tun') ||
            name.startsWith('tap') ||
            name.startsWith('ppp') ||
            name.contains('ipsec') ||
            name.contains('vpn') ||
            name.contains('tailscale') ||
            name.contains('wireguard')) {
          return true;
        }
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Web VPN detection using server-side validation
  static Future<bool> _detectVpnWeb() async {
    try {
      // Local development or offline bypass check
      final isLocalDev = CollegeIPConfig.defaultURL.contains('localhost') ||
          CollegeIPConfig.defaultURL.contains('127.0.0.1') ||
          CollegeIPConfig.defaultURL.contains('192.168.');

      // Defense-in-depth: Multiple VPN detection layers for web
      
      // 1. Check for timezone mismatch (common VPN indicator)
      final timezoneOffset = DateTime.now().timeZoneOffset.inHours;
      // College timezone is UTC+5:30 (India Standard Time)
      if (timezoneOffset != 5 && timezoneOffset != 5.5) {
        // User is in different timezone - high probability of VPN
        print('[VPN] Timezone mismatch detected: $timezoneOffset');
        if (!isLocalDev) {
          return true;
        }
      }
      
      // 2. Check common VPN browser headers via performance API
      try {
        // Check if any suspicious headers are present
        // These are commonly added by VPN extensions
        final response = await http.head(
          Uri.parse('${CollegeIPConfig.defaultURL}/api/health'),
          headers: {'Content-Type': 'application/json'},
        ).timeout(const Duration(seconds: 2));
        
        if (response.headers.containsKey('x-forwarded-for') && 
            response.headers['x-forwarded-for'] != null &&
            response.headers['x-forwarded-for']!.contains(',')) {
          // Multiple IPs in X-Forwarded-For indicates proxy/VPN
          print('[VPN] Multiple X-Forwarded-For IPs detected');
          return true;
        }
      } catch (e) {
        // Ignore this check if it fails
      }
      
      // 3. Primary server VPN check (most reliable)
      try {
        final response = await http.get(
          Uri.parse('${CollegeIPConfig.defaultURL}/check_vpn'),
          headers: {'Content-Type': 'application/json'},
        ).timeout(const Duration(seconds: 4));
        
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final vpnDetected = data['vpn_detected'] ?? false;
          
          if (vpnDetected) {
            print('[VPN] Server confirmed VPN detection');
            return true;
          }
          
          // Server explicitly says no VPN - trust it
          return false;
        }
      } catch (e) {
        print('[VPN] Server VPN check failed: $e');
        // If server check fails in local development or if offline, DO NOT block
        if (isLocalDev) {
          return false;
        }
        // Fail-open to avoid locking out genuine users during network blips
        return false;
      }
      
      // All checks passed
      return false;
    } catch (e) {
      print('[VPN] Web detection error: $e');
      return false;
    }
  }

  /// Validate VPN status and return error message if VPN is active
  static Future<String?> validateVpnStatus() async {
    await AppSettings.loadSettings();
    
    if (!AppSettings.enforceVpnBlocking) {
      return null;
    }

    final vpnActive = await isVpnActive();
    
    if (vpnActive) {
      return 'VPN detected. Please turn off your VPN connection to continue.';
    }
    
    return null;
  }

  /// Get VPN status message for display
  static Future<String> getVpnStatusMessage() async {
    await AppSettings.loadSettings();
    
    if (!AppSettings.enforceVpnBlocking) {
      return 'VPN blocking is disabled.';
    }

    final vpnActive = await isVpnActive();
    
    if (vpnActive) {
      return '⚠️ VPN is active - Access blocked';
    } else {
      return '✓ No VPN detected';
    }
  }
}
