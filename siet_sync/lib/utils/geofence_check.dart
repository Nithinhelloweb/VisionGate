import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import '../config/college_ip_config.dart';
import 'wifi_check.dart';
import 'platform_utils.dart';

/// Geo-fence check result for attendance.
class GeoFenceDecision {
  final bool enforced;
  final bool? insideOuter;
  final bool? insideInner;
  final String? error;

  const GeoFenceDecision({
    required this.enforced,
    required this.insideOuter,
    required this.insideInner,
    required this.error,
  });

  bool get shouldSkipWifi =>
      enforced && insideOuter == true && insideInner == true;
}

/// Geo-fence checker for attendance marking.
/// Returns a user-facing error message if location is not allowed.
class GeoFenceChecker {
  static Position? lastFetchedPosition;

  static Future<GeoFenceDecision> checkAttendanceFence() async {
    if (!CollegeIPConfig.isGeoFenceEnabled) {
      return const GeoFenceDecision(
        enforced: false,
        insideOuter: null,
        insideInner: null,
        error: null,
      );
    }
    // Load latest geofence coordinates from server
    CollegeIPConfig.clearGeoFenceCache();
    await CollegeIPConfig.loadGeoFenceCoordinates();
    await AppSettings.loadSettings();
    if (kIsWeb) {
      if (!AppSettings.enforceGeoFence) {
        return const GeoFenceDecision(
          enforced: false,
          insideOuter: null,
          insideInner: null,
          error: null,
        );
      }
    } else {
      if (!AppSettings.enforceAppGeoFence) {
        return const GeoFenceDecision(
          enforced: false,
          insideOuter: null,
          insideInner: null,
          error: null,
        );
      }
    }

    if (!CollegeIPConfig.isGeoFenceConfigured) {
      return const GeoFenceDecision(
        enforced: true,
        insideOuter: false,
        insideInner: false,
        error: 'Attendance location is not configured. Please contact admin.',
      );
    }

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return const GeoFenceDecision(
          enforced: true,
          insideOuter: false,
          insideInner: false,
          error:
              'Location services are disabled. Please enable location to mark attendance.',
        );
      }

      LocationPermission permission = await Geolocator.checkPermission();
      
      // Web-specific: sometimes checkPermission returns denied even when enabled
      if (kIsWeb && permission == LocationPermission.denied) {
        try {
          permission = await Geolocator.requestPermission();
        } catch (e) {
          // On web, requestPermission may throw if user ignores prompt
          return const GeoFenceDecision(
            enforced: true,
            insideOuter: false,
            insideInner: false,
            error: 'Please allow location access in your browser settings.',
          );
        }
      } else if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        String permError;
        if (kIsWeb) {
          permError = 'Location permission denied. Click the location icon in your browser address bar to allow access.';
        } else if (AppPlatform.isWindows) {
          permError = 'Location permission is required. Please enable Location in Windows Settings > Privacy & security > Location.';
        } else if (AppPlatform.isMacOS) {
          permError = 'Location permission is required. Please enable Location in macOS System Settings > Privacy & Security > Location Services.';
        } else if (AppPlatform.isLinux) {
          permError = 'Location permission is required. Please enable Location services in your system settings.';
        } else {
          permError = 'Location permission is required to mark attendance.';
        }

        return GeoFenceDecision(
          enforced: true,
          insideOuter: false,
          insideInner: false,
          error: permError,
        );
      }

      late final Position position;
      int retries = kIsWeb ? 4 : 1;
      
      for (int i = 0; i < retries; i++) {
        try {
          // Attempt high accuracy first (requests Wi-Fi / GPS triangulation from browser)
          position = await Geolocator.getCurrentPosition(
            desiredAccuracy: (i == 0)
                ? LocationAccuracy.high
                : ((i == 1) ? LocationAccuracy.medium : LocationAccuracy.low),
            timeLimit: Duration(seconds: kIsWeb ? 12 : 8),
          );
          lastFetchedPosition = position; // Cache successful position
          break;
        } catch (e) {
          if (kIsWeb) {
            // Try last known position as fallback (works on most modern browsers)
            try {
              final lastPos = await Geolocator.getLastKnownPosition();
              if (lastPos != null) {
                position = lastPos;
                lastFetchedPosition = position;
                break;
              }
            } catch (_) {}
          }
          
          if (i == retries - 1) {
            if (kIsWeb) {
              return const GeoFenceDecision(
                enforced: true,
                insideOuter: false,
                insideInner: false,
                error: 'Unable to get your location. Please:\n1. Refresh the page\n2. Click location icon in browser address bar\n3. Select "Allow" for this site\n4. Ensure you are on HTTPS',
              );
            }
            rethrow;
          }
          
          await Future.delayed(Duration(milliseconds: kIsWeb ? (400 * (i + 1)) : 400));
        }
      }

      // ── Outer Boundary is MANDATORY for Attendance Marking ─────────────────
      final insideOuter = _isPointInAnyPolygon(
        position.latitude,
        position.longitude,
        CollegeIPConfig.geoFencePolygons,
      );

      if (!insideOuter) {
        return const GeoFenceDecision(
          enforced: true,
          insideOuter: false,
          insideInner: false,
          error: 'You are outside the allowed location.',
        );
      }

      final hasInner = CollegeIPConfig.geoFenceInnerPolygons.any((poly) => poly.length >= 3);
      final insideInner = hasInner
          ? _isPointInAnyPolygon(
              position.latitude,
              position.longitude,
              CollegeIPConfig.geoFenceInnerPolygons,
            )
          : false;

      return GeoFenceDecision(
        enforced: true,
        insideOuter: true,
        insideInner: insideInner,
        error: null,
      );
    } catch (e) {
      return GeoFenceDecision(
        enforced: true,
        insideOuter: false,
        insideInner: false,
        error: kIsWeb
            ? 'Unable to verify location. Please ensure:\n1. Location is enabled in browser settings\n2. You are using HTTPS\n3. Allow location when prompted'
            : 'Unable to verify location. Please enable location and try again.',
      );
    }
  }

  static Future<String?> validateAttendanceLocation() async {
    final decision = await checkAttendanceFence();
    return decision.error;
  }

  static bool _isPointInPolygon(
    double lat,
    double lng,
    List<List<double>> polygon,
  ) {
    bool inside = false;
    final int len = polygon.length;
    
    for (int i = 0, j = len - 1; i < len; j = i++) {
      final double yi = polygon[i][0];
      final double xi = polygon[i][1];
      final double yj = polygon[j][0];
      final double xj = polygon[j][1];
      
      // Check if point's y (lat) is within the edge's y range
      if (((yi > lat) != (yj > lat))) {
        // Calculate x intersection at this y
        final double dy = yj - yi;
        if (dy.abs() < 0.0000001) continue; // Skip horizontal edges
        
        final double t = (lat - yi) / dy;
        final double xIntersect = xi + t * (xj - xi);
        
        // Check if point's x (lng) is to the left of intersection
        if (lng < xIntersect) {
          inside = !inside;
        }
      }
    }
    return inside;
  }

  static bool _isPointInAnyPolygon(
    double lat,
    double lng,
    List<List<List<double>>> polygons,
  ) {
    for (final polygon in polygons) {
      if (polygon.length >= 3 && _isPointInPolygon(lat, lng, polygon)) {
        return true;
      }
    }
    return false;
  }
}