import 'dart:convert';
import '../services/api_client.dart';

class CollegeIPConfig {
  /// ============================================
  /// SERVER CONFIGURATION - For Any Network
  /// ============================================
  ///
  /// IMPORTANT: The server runs on 0.0.0.0:8001 (all interfaces)
  /// Update this URL to match your computer's current IP address:
  /// - Run "ipconfig" in CMD to find your IPv4 Address
  /// - Example: "http://192.168.1.100:8001"
  ///
  /// For different networks, use the appropriate IP:
  /// - Mobile Hotspot: Use the hotspot IP (typically 192.168.x.x)
  /// - College WiFi: Use the college network IP
  /// - USB Tethering: Use the USB tethering IP (typically 192.168.137.x)
  ///
  /// ============================================

  /// 🔴 CLOUDFLARE TUNNEL URL - SET ONCE, NEVER CHANGES
  ///
  /// To get your Cloudflare Tunnel URL:
  /// 1. Install: npm install -g cloudflared
  /// 2. Run: cloudflared tunnel --url http://localhost:8001
  /// 3. Copy the URL shown (e.g., https://abc-xyz.trycloudflare.com)
  /// 4. Paste it above in customServerURL
  ///
  /// NOTE: For access from OUTSIDE your network (mobile data, other WiFi):
  /// - Your router needs port forwarding to this computer OR
  /// - Use a tunnel service like Cloudflare: cloudflared tunnel --url http://localhost:8001
  ///
  static const String customServerURL = "https://attenda.srishakthicgpa.in";

  /// Runtime API URL - can be set programmatically for web/deployment
  /// Set this to override customServerURL at runtime
  static String? _runtimeServerURL;

  /// Set runtime API URL (useful for web deployment)
  static void setRuntimeURL(String url) {
    _runtimeServerURL = url;
  }

  /// Clear runtime URL and use default
  static void clearRuntimeURL() {
    _runtimeServerURL = null;
  }

  /// ============================================
  /// ATTENDANCE WIFI REQUIREMENT
  /// ============================================
  ///
  /// 🔴 ATTENDANCE REQUIREMENT:
  /// Users MUST be connected to college WiFi to mark attendance
  /// This ensures attendance is marked only when physically present
  ///
  static const bool enforceWifiCheckForAttendance = true;

  /// College WiFi SSID required for marking attendance
  static const List<String> allowedWifiSSIDs = [];

  /// ============================================
  /// ATTENDANCE GEOFENCE REQUIREMENT
  /// ============================================
  ///
  /// If enabled, users must be within the polygon to mark attendance.
  /// Coordinates are now fetched dynamically from the server.
  ///
  static const bool enforceGeoFenceForAttendance = true;

  /// Default fallback coordinates (used if API fails)
  static const List<List<double>> _defaultGeoFencePolygon = [
    [11.040730, 77.073717],
    [11.040865, 77.075121],
    [11.039733, 77.075201],
    [11.039529, 77.075786],
    [11.038500, 77.075892],
    [11.038551, 77.073616],
  ];

  /// Default fallback inner coordinates
  static const List<List<double>> _defaultGeoFenceInnerPolygon = [
    [11.039537, 77.075328],
    [11.039554, 77.075895],
    [11.038858, 77.075912],
    [11.038501, 77.074908],
  ];

  /// Cached coordinates (loaded from API)
  static List<List<double>>? _cachedGeoFencePolygon;
  static List<List<double>>? _cachedGeoFenceInnerPolygon;
  static List<List<double>>? _cachedGeoFenceLimitRangePolygon;
  static List<List<List<double>>>? _cachedGeoFencePolygons;
  static List<List<List<double>>>? _cachedGeoFenceInnerPolygons;
  static List<List<List<double>>>? _cachedGeoFenceLimitRangePolygons;

  /// Get outer geo fence polygon (fetched from API or fallback to defaults)
  static List<List<double>> get geoFencePolygon {
    return _cachedGeoFencePolygon ?? _defaultGeoFencePolygon;
  }

  /// Get all outer geo fence polygons
  static List<List<List<double>>> get geoFencePolygons {
    return _cachedGeoFencePolygons ?? [geoFencePolygon];
  }

  /// Get inner geo fence polygon (fetched from API or fallback to defaults)
  static List<List<double>> get geoFenceInnerPolygon {
    return _cachedGeoFenceInnerPolygon ?? _defaultGeoFenceInnerPolygon;
  }

  /// Get all inner geo fence polygons
  static List<List<List<double>>> get geoFenceInnerPolygons {
    return _cachedGeoFenceInnerPolygons ?? [geoFenceInnerPolygon];
  }

  /// Get limit range polygon (for movement tracking)
  static List<List<double>> get geoFenceLimitRangePolygon {
    return _cachedGeoFenceLimitRangePolygon ?? [];
  }

  /// Get all limit range polygons (for user movement range tracking)
  static List<List<List<double>>> get geoFenceLimitRangePolygons {
    return _cachedGeoFenceLimitRangePolygons ?? (_cachedGeoFenceLimitRangePolygon != null && _cachedGeoFenceLimitRangePolygon!.isNotEmpty ? [_cachedGeoFenceLimitRangePolygon!] : []);
  }

  static List<List<List<double>>> _parsePolygonList(dynamic rawList) {
    if (rawList == null || rawList is! List) return [];
    final result = <List<List<double>>>[];
    for (final poly in rawList) {
      if (poly is List) {
        final polygon = <List<double>>[];
        for (final pt in poly) {
          if (pt is List && pt.length >= 2) {
            try {
              final lat = (pt[0] as num).toDouble();
              final lng = (pt[1] as num).toDouble();
              polygon.add([lat, lng]);
            } catch (_) {}
          }
        }
        if (polygon.length >= 3) {
          result.add(polygon);
        }
      }
    }
    return result;
  }

  static List<List<double>> _parseSinglePolygon(dynamic rawPoly) {
    if (rawPoly == null || rawPoly is! List) return [];
    final polygon = <List<double>>[];
    for (final pt in rawPoly) {
      if (pt is List && pt.length >= 2) {
        try {
          final lat = (pt[0] as num).toDouble();
          final lng = (pt[1] as num).toDouble();
          polygon.add([lat, lng]);
        } catch (_) {}
      }
    }
    return polygon;
  }

  /// Load geo fence coordinates from API
  static Future<bool> loadGeoFenceCoordinates() async {
    try {
      final apiClient = ApiClient();
      final response = await apiClient.get(
        '$defaultURL/geo-fence/public',
        timeout: const Duration(seconds: 8),
      );
      final data = json.decode(response.body);

      if (data['success'] == true) {
        clearGeoFenceCache();

        final parsedOuter = _parsePolygonList(data['outer_polygons']);
        final parsedInner = _parsePolygonList(data['inner_polygons']);
        final parsedLimit = _parsePolygonList(data['limit_range_polygons']);

        if (parsedOuter.isNotEmpty) {
          _cachedGeoFencePolygons = parsedOuter;
          _cachedGeoFencePolygon = parsedOuter.first;
        } else if (data['outer_polygon'] != null) {
          final single = _parseSinglePolygon(data['outer_polygon']);
          if (single.isNotEmpty) {
            _cachedGeoFencePolygon = single;
            _cachedGeoFencePolygons = [single];
          }
        }

        if (parsedInner.isNotEmpty) {
          _cachedGeoFenceInnerPolygons = parsedInner;
          _cachedGeoFenceInnerPolygon = parsedInner.first;
        } else if (data['inner_polygon'] != null) {
          final single = _parseSinglePolygon(data['inner_polygon']);
          if (single.isNotEmpty) {
            _cachedGeoFenceInnerPolygon = single;
            _cachedGeoFenceInnerPolygons = [single];
          }
        }

        if (parsedLimit.isNotEmpty) {
          _cachedGeoFenceLimitRangePolygons = parsedLimit;
          _cachedGeoFenceLimitRangePolygon = parsedLimit.first;
        } else if (data['limit_range_polygon'] != null) {
          final single = _parseSinglePolygon(data['limit_range_polygon']);
          if (single.isNotEmpty) {
            _cachedGeoFenceLimitRangePolygon = single;
            _cachedGeoFenceLimitRangePolygons = [single];
          }
        }
        return true;
      }
    } catch (e) {
      // Keep existing cached coordinates if available
    }
    return false;
  }

  /// Clear cached coordinates (force reload on next access)
  static void clearGeoFenceCache() {
    _cachedGeoFencePolygon = null;
    _cachedGeoFenceInnerPolygon = null;
    _cachedGeoFenceLimitRangePolygon = null;
    _cachedGeoFencePolygons = null;
    _cachedGeoFenceInnerPolygons = null;
    _cachedGeoFenceLimitRangePolygons = null;
  }

  /// ============================================
  /// PREDEFINED SERVER LIST
  /// ============================================
  ///
  /// Add your common network IPs here for quick switching
  /// Update these based on your typical network setups
  ///
  static const List<Map<String, dynamic>> collegeIPs = [
    {
      'ip': '192.168.137.1',
      'port': 8001,
      'location': 'USB Tethering',
      'name': 'Mobile Hotspot',
      'isDefault': true,
    },
    {
      'ip': '192.168.1.100',
      'port': 8001,
      'location': 'WiFi Network',
      'name': 'Local WiFi',
      'isDefault': false,
    },
    {
      'ip': '192.168.68.1',
      'port': 8001,
      'location': 'Mobile Hotspot (Common)',
      'name': 'Hotspot IP Range 1',
      'isDefault': false,
    },
    {
      'ip': '192.168.43.1',
      'port': 8001,
      'location': 'Mobile Hotspot (Common)',
      'name': 'Hotspot IP Range 2',
      'isDefault': false,
    },
  ];

  /// Get the default server URL
  static String get defaultURL {
    if (_runtimeServerURL != null && _runtimeServerURL!.isNotEmpty) {
      return _runtimeServerURL!;
    }

    if (customServerURL.isNotEmpty) {
      return customServerURL;
    }

    final defaultIP = collegeIPs.firstWhere(
      (ip) => ip['isDefault'] == true,
      orElse: () => collegeIPs.first,
    );
    return 'http://${defaultIP['ip']}:${defaultIP['port']}';
  }

  /// Get server URL by IP address
  static String getURLByIP(String ip) {
    final server = collegeIPs.firstWhere(
      (server) => server['ip'] == ip,
      orElse: () => {'ip': ip, 'port': 8000} as Map<String, dynamic>,
    );
    return 'http://${server['ip']}:${server['port']}';
  }

  /// Get server info by IP
  static Map<String, dynamic>? getServerInfo(String ip) {
    try {
      return collegeIPs.firstWhere((server) => server['ip'] == ip);
    } catch (e) {
      return null;
    }
  }

  /// Get all available server names
  static List<String> get serverNames {
    return collegeIPs
        .map((server) => '${server['name']} (${server['location']})')
        .toList();
  }

  /// Get all available IPs
  static List<String> get allIPs {
    return collegeIPs.map((server) => server['ip'] as String).toList();
  }

  /// Get total number of configured servers
  static int get serverCount => collegeIPs.length;

  /// Check if an IP is configured
  static bool isIPConfigured(String ip) {
    return collegeIPs.any((server) => server['ip'] == ip);
  }

  /// Get list of servers formatted for dropdown
  static List<Map<String, String>> getServersForDropdown() {
    return collegeIPs.map((server) {
      return {
        'ip': server['ip'] as String,
        'name': '${server['name']} - ${server['location']}',
        'url': 'http://${server['ip']}:${server['port']}',
      };
    }).toList();
  }

  /// Get allowed WiFi SSIDs for attendance marking
  static List<String> get allowedNetworks => allowedWifiSSIDs;

  /// Check if given SSID is allowed for attendance
  static bool isSSIDAllowedForAttendance(String ssid) {
    if (!enforceWifiCheckForAttendance) return true;
    return allowedWifiSSIDs.contains(ssid);
  }

  /// Check if WiFi check is enabled for attendance
  static bool get isWifiCheckEnabled => enforceWifiCheckForAttendance;

  /// Check if geofence check is enabled for attendance
  static bool get isGeoFenceEnabled => enforceGeoFenceForAttendance;

  /// Check if geofence coordinates are configured
  static bool get isGeoFenceConfigured => geoFencePolygons.any((poly) => poly.length >= 3);
}
