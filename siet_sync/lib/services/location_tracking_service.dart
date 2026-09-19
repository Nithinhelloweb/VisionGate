import 'dart:async';
import 'dart:convert';

import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:permission_handler/permission_handler.dart';
import 'background_service_handler.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../config/college_ip_config.dart';
import 'api_client.dart';
import 'session_service.dart';

enum TrackingLifecycleState {
  standbyWaitingCheckIn, // Before check-in: waiting for user to mark attendance
  activeInWindow,        // Checked in & within tracking window duration
  completedForToday,     // Checked out or passed end of tracking window
  pausedError,           // Checked in & in window, but service was paused or died
}

class LocationTrackingService with WidgetsBindingObserver {
  LocationTrackingService._() {
    _initLocalNotifications();
    WidgetsBinding.instance.addObserver(this);
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_running && _activeToken != null) {
        _captureAndQueue(source: 'app_resume');
        flushAllCachesInstantly();
      }
    }
  }
  static final LocationTrackingService instance = LocationTrackingService._();

  final ValueNotifier<TrackingLifecycleState> lifecycleState =
      ValueNotifier<TrackingLifecycleState>(TrackingLifecycleState.standbyWaitingCheckIn);
  final ValueNotifier<String?> windowEndTime = ValueNotifier<String?>(null);
  final ValueNotifier<String?> statusDetailMessage = ValueNotifier<String?>(null);

  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  StreamSubscription<Position>? _positionSub;
  Timer? _heartbeatTimer;
  Timer? _appLivePingTimer;
  bool _running = false;
  String? _activeToken;
  Map<String, dynamic>? _activeUser;
  final List<Map<String, dynamic>> _pending = [];
  
  // Tracking window status variables
  bool _trackingSuspended = false;
  final _warningController = StreamController<String>.broadcast();
  
  /// Stream emitting warnings (e.g. boundary breach warnings) to be consumed by UI pages
  Stream<String> get warningStream => _warningController.stream;

  Future<void> _initLocalNotifications() async {
    try {
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosInit = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestSoundPermission: true,
        requestBadgePermission: true,
      );
      const linuxInit = LinuxInitializationSettings(
        defaultActionName: 'Open notification',
      );
      const initSettings = InitializationSettings(
        android: androidInit,
        iOS: iosInit,
        linux: linuxInit,
      );
      await _localNotifications.initialize(initSettings);
    } catch (e) {
      debugPrint('[Notifications] Initialization skipped on this platform: $e');
    }
  }

  Future<void> _showBreachNotification(String message) async {
    try {
      final androidDetails = AndroidNotificationDetails(
        'geofence_breach_channel',
        'Geofence Alerts',
        channelDescription: 'Alerts when moving out of geofence boundaries',
        importance: Importance.max,
        priority: Priority.max,
        playSound: true,
        enableVibration: true,
        vibrationPattern: Int64List.fromList([0, 500, 200, 500, 200, 500]),
        fullScreenIntent: true,
        ongoing: false,
        autoCancel: true,
        styleInformation: BigTextStyleInformation(
          message,
          htmlFormatBigText: false,
          contentTitle: '⚠ Boundary Breach Detected!',
          htmlFormatContentTitle: false,
          summaryText: 'VisionGate Geofence Alert',
        ),
        color: const Color(0xFFFF3333),
        largeIcon: const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
      );
      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
        presentBadge: true,
        interruptionLevel: InterruptionLevel.timeSensitive,
      );
      const linuxDetails = LinuxNotificationDetails(
        urgency: LinuxNotificationUrgency.critical,
      );
      final details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
        linux: linuxDetails,
      );
      
      await _localNotifications.show(
        1001,
        '⚠ Boundary Breach Detected!',
        message,
        details,
      );
    } catch (e) {
      debugPrint('[Notifications] Could not present local notification: $e');
    }
  }

  String? _deviceSessionId;

  /// Ensures that tracking is running and auto-heals/restarts the native service if stopped.
  Future<bool> ensureTrackingActive() async {
    if (kIsWeb) return false;
    if (_running && _activeToken != null) {
      try {
        final status = await BackgroundLocationService.getServiceStatus();
        if (!status.running) {
          await BackgroundLocationService.restart();
        }
      } catch (_) {}
      return true;
    }

    try {
      final session = await sessionService.getSession();
      if (session != null && session.token.isNotEmpty) {
        return await startTracking(
          token: session.token,
          user: session.user,
        );
      }
    } catch (_) {}
    return false;
  }

  Future<bool> startTracking({
    required String token,
    required Map<String, dynamic> user,
  }) async {
    if (kIsWeb) return false;
    if (_running && _activeToken == token) {
      try {
        final status = await BackgroundLocationService.getServiceStatus();
        if (!status.running) {
          await BackgroundLocationService.restart();
        }
      } catch (_) {}
      return true;
    }

    await stopTracking();
    
    try {
      final role = await sessionService.getUserRole();
      // Only 'admin' role is excluded from location tracking.
      // HOD, staff, other_staff, and student all participate.
      if (role == 'admin') {
        return false;
      }
    } catch (_) {}

    _activeToken = token;
    _activeUser = user;

    try {
      final session = await sessionService.getSession();
      _deviceSessionId = session?.deviceSessionId;
    } catch (_) {}

    final permissionGranted = await _ensureLocationPermission();
    if (!permissionGranted) {
      await stopTracking();
      return false;
    }

    _running = true;
    _trackingSuspended = false;
    await updateLocalAttendanceStatus();

    bool active = false;
    try {
      active = await checkTrackingActive();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('last_tracking_active', active);
    } catch (_) {}
    _startHeartbeat();

    // Start App Live Ping and Cache-Flush timer
    _appLivePingTimer?.cancel();
    _appLivePingTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (!_running) {
        _appLivePingTimer?.cancel();
        return;
      }
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('app_last_active_time', DateTime.now().toUtc().toIso8601String());
        
        // If there are logs cached while offline or buffered while online, flush them instantly when app is open
        final offlineLogs = prefs.getStringList('offline_locations') ?? [];
        final bufferedLogs = prefs.getStringList('online_buffered_locations') ?? [];
        if (offlineLogs.isNotEmpty || bufferedLogs.isNotEmpty) {
          await flushAllCachesInstantly();
        }
      } catch (_) {}
    });

    // Flush any pending data instantly on start tracking
    flushAllCachesInstantly();

    if (active) {
      try {
        double centerLat = 11.0396;
        double centerLng = 77.0747;
        final polygons = CollegeIPConfig.geoFencePolygons;
        if (polygons.isNotEmpty && polygons.first.isNotEmpty) {
          final poly = polygons.first;
          final latSum = poly.fold<double>(0, (s, p) => s + p[0]);
          final lngSum = poly.fold<double>(0, (s, p) => s + p[1]);
          centerLat = latSum / poly.length;
          centerLng = lngSum / poly.length;
        }

        final regNo = _activeUser!['regNo'] ?? _activeUser!['reg_no'] ?? '';
        await BackgroundLocationService.start(
          baseUrl: CollegeIPConfig.defaultURL,
          geofenceLat: centerLat,
          geofenceLng: centerLng,
          geofenceRadius: 250.0,
          token: _activeToken!,
          regNo: regNo.toString(),
          deviceSessionId: _deviceSessionId ?? '',
        );
      } catch (_) {}
    }
    return true;
  }

  Future<void> flushAllCachesInstantly() async {
    if (_activeToken == null || _activeUser == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();

      final List<String> cachedOffline = prefs.getStringList('offline_locations') ?? [];
      final List<String> cachedBuffered = prefs.getStringList('online_buffered_locations') ?? [];

      final List<Map<String, dynamic>> combinedLogs = [];
      if (cachedOffline.isNotEmpty) {
        combinedLogs.addAll(cachedOffline.map((s) => jsonDecode(s) as Map<String, dynamic>));
      }
      if (cachedBuffered.isNotEmpty) {
        combinedLogs.addAll(cachedBuffered.map((s) => jsonDecode(s) as Map<String, dynamic>));
      }

      if (combinedLogs.isEmpty) return;

      final regNo = _activeUser!.containsKey('regNo')
          ? _activeUser!['regNo'].toString()
          : (_activeUser!['reg_no']?.toString() ?? '');

      final response = await apiClient.post(
        '${CollegeIPConfig.defaultURL}/location/sync_offline',
        token: _activeToken,
        body: jsonEncode({
          'device_id': _deviceSessionId ?? 'app_$regNo',
          'logs': combinedLogs,
        }),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        await prefs.reload();
        // Clear both lists safely
        await prefs.setStringList('offline_locations', []);
        await prefs.setStringList('online_buffered_locations', []);

        // Process boundary warning alerts if returned in the batch sync response
        final data = jsonDecode(response.body);
        if (data['boundary_warning'] == true && data['warning'] != null) {
          _warningController.add(data['warning'].toString());
          _showBreachNotification(data['warning'].toString());
        } else {
          _localNotifications.cancel(1001);
        }
      }
    } catch (_) {}
  }

  Future<void> stopTracking() async {
    if (kIsWeb) return;
    _running = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('last_tracking_active', false);
    } catch (_) {}

    try {
      await _positionSub?.cancel();
    } catch (_) {}
    _positionSub = null;
    
    try {
      _heartbeatTimer?.cancel();
    } catch (_) {}
    _heartbeatTimer = null;

    try {
      _appLivePingTimer?.cancel();
    } catch (_) {}
    _appLivePingTimer = null;
    
    _activeToken = null;
    _activeUser = null;
    _deviceSessionId = null;
    _pending.clear();
    _trackingSuspended = false;
    
    try {
      await BackgroundLocationService.stop();
    } catch (_) {}
  }

  /// Called immediately after attendance is marked (check-in or check-out).
  /// Re-checks tracking status and resumes or suspends location sharing accordingly.
  /// This eliminates the delay for start/stop of tracking.
  Future<void> onAttendanceMarked() async {
    if (!_running || _activeToken == null) return;
    await updateLocalAttendanceStatus();
    
    // Instantly capture and flush current location on check-in
    await _captureAndQueue(source: 'checkin_attendance_mark');
    await flushAllCachesInstantly();

    final active = await checkTrackingActive();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('last_tracking_active', active);
    } catch (_) {}

    if (active) {
      if (_trackingSuspended) {
        _trackingSuspended = false;
      }
      lifecycleState.value = TrackingLifecycleState.activeInWindow;
      try {
        double centerLat = 11.0396;
        double centerLng = 77.0747;
        final polygons = CollegeIPConfig.geoFencePolygons;
        if (polygons.isNotEmpty && polygons.first.isNotEmpty) {
          final poly = polygons.first;
          final latSum = poly.fold<double>(0, (s, p) => s + p[0]);
          final lngSum = poly.fold<double>(0, (s, p) => s + p[1]);
          centerLat = latSum / poly.length;
          centerLng = lngSum / poly.length;
        }

        final regNo = _activeUser!['regNo'] ?? _activeUser!['reg_no'] ?? '';
        await BackgroundLocationService.start(
          baseUrl: CollegeIPConfig.defaultURL,
          geofenceLat: centerLat,
          geofenceLng: centerLng,
          geofenceRadius: 250.0,
          token: _activeToken!,
          regNo: regNo.toString(),
          deviceSessionId: _deviceSessionId ?? '',
        );
      } catch (_) {}
    } else {
      _trackingSuspended = false;
    }
  }

  Future<bool> checkTrackingActive() async {
    if (_activeToken == null) return false;
    try {
      final queryParam = _deviceSessionId != null ? '?device_id=$_deviceSessionId' : '';
      final response = await apiClient.get(
        '${CollegeIPConfig.defaultURL}/staff/tracking-status$queryParam',
        token: _activeToken,
      );
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body['reason'] == 'device_mismatch') {
          await stopTracking();
          lifecycleState.value = TrackingLifecycleState.pausedError;
          statusDetailMessage.value = 'Device session mismatch';
          return false;
        }
        
        final active = body['tracking_active'] == true;
        final state = body['state']?.toString() ?? '';
        final winEnd = body['window_end']?.toString();
        windowEndTime.value = winEnd;

        if (state == 'waiting_for_check_in') {
          lifecycleState.value = TrackingLifecycleState.standbyWaitingCheckIn;
          statusDetailMessage.value = 'Starts automatically upon check-in';
        } else if (state == 'window_ended' || state == 'checked_out') {
          lifecycleState.value = TrackingLifecycleState.completedForToday;
          statusDetailMessage.value = state == 'checked_out'
              ? 'Checked out for today'
              : 'Tracking completed at ${winEnd ?? 'end time'}';
          try {
            await BackgroundLocationService.stop();
          } catch (_) {}
        } else if (active) {
          lifecycleState.value = TrackingLifecycleState.activeInWindow;
          statusDetailMessage.value = 'Tracking active until ${winEnd ?? '17:30'}';
        } else {
          lifecycleState.value = TrackingLifecycleState.standbyWaitingCheckIn;
        }

        if (active && body['force_update'] == true) {
          _captureAndQueue(source: 'force_update_instant').then((_) => _flushPending());
        }
        
        return active;
      } else if (response.statusCode == 403) {
        await stopTracking();
        lifecycleState.value = TrackingLifecycleState.pausedError;
        return false;
      }
    } catch (_) {}
    return false;
  }

  void _startHeartbeat() {
    // Poll tracking status and flush positions every 2 minutes for dynamic updates
    _heartbeatTimer = Timer.periodic(const Duration(minutes: 2), (timer) async {
      if (!_running) return;
      
      await updateLocalAttendanceStatus();
      final active = await checkTrackingActive();
      if (active) {
        if (_trackingSuspended) {
          _trackingSuspended = false;
        }
        // Auto-heal native service if interrupted
        try {
          final status = await BackgroundLocationService.getServiceStatus();
          if (!status.running) {
            await BackgroundLocationService.restart();
          }
        } catch (_) {}
      } else {
        if (!_trackingSuspended) {
          _trackingSuspended = true;
        }
      }
    });
  }

  Future<void> _captureAndQueue({required String source}) async {
    if (_trackingSuspended) return;
    Position? position;
    try {
      position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 7),
      );
    } catch (_) {
      try {
        position = await Geolocator.getLastKnownPosition();
      } catch (_) {}
    }

    if (position == null) {
      try {
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
          timeLimit: const Duration(seconds: 5),
        );
      } catch (_) {}
    }

    if (position != null) {
      _queuePosition(position, source: source);
    }
  }


  Future<void> _queuePosition(Position position, {required String source}) async {
    if (!_running || _trackingSuspended || _activeToken == null || _activeUser == null) return;
    
    // Ignore noisy location updates with error margin > 50 meters
    if (position.accuracy > 50.0) return;



    final ist = position.timestamp.toUtc().add(const Duration(hours: 5, minutes: 30));
    final iso = ist.toIso8601String();
    final capturedAtIST = '${iso.endsWith('Z') ? iso.substring(0, iso.length - 1) : iso}+05:30';

    final payload = <String, dynamic>{
      'latitude': position.latitude,
      'longitude': position.longitude,
      'captured_at': capturedAtIST,
    };

    final connectivityResult = await Connectivity().checkConnectivity();
    final isOffline = connectivityResult.contains(ConnectivityResult.none) || connectivityResult.isEmpty;

    try {
      final prefs = await SharedPreferences.getInstance();
      if (isOffline) {
        List<String> offlineLogs = prefs.getStringList('offline_locations') ?? [];
        offlineLogs.add(jsonEncode(payload));
        if (offlineLogs.length > 500) {
          offlineLogs.removeAt(0);
        }
        await prefs.setStringList('offline_locations', offlineLogs);
      } else {
        final regNo = _activeUser!.containsKey('regNo')
            ? _activeUser!['regNo'].toString()
            : (_activeUser!['reg_no']?.toString() ?? '');
        final updatePayload = <String, dynamic>{
          'latitude': position.latitude,
          'longitude': position.longitude,
          'accuracy_meters': position.accuracy,
          'speed_mps': position.speed,
          'heading_deg': position.heading,
          'altitude_m': position.altitude,
          'is_mocked': position.isMocked,
          'source': source,
          'app_state': 'foreground',
          'captured_at': capturedAtIST,
          'device_id': _deviceSessionId ?? 'app_$regNo',
        };
        final response = await apiClient.post(
          '${CollegeIPConfig.defaultURL}/location/update',
          token: _activeToken,
          body: jsonEncode(updatePayload),
        );
        if (response.statusCode >= 200 && response.statusCode < 300) {
          final data = jsonDecode(response.body);
          if (data['boundary_warning'] == true && data['warning'] != null) {
            _warningController.add(data['warning'].toString());
            _showBreachNotification(data['warning'].toString());
          } else {
            _localNotifications.cancel(1001);
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _flushPending() async {
    flushAllCachesInstantly();
  }

  Future<bool> _ensureLocationPermission() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return false;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return false;
      }

      // Mobile permissions:
      if (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS) {
        if (permission == LocationPermission.whileInUse) {
          try {
            // Best-effort request for locationAlways
            await Permission.locationAlways.request();
          } catch (_) {}
          // Note: On Android, a Foreground Service declared with foregroundServiceType="location"
          // is officially foreground access and operates with whileInUse permission.
        }

        // Request battery-optimisation exemption so OEM battery killers cannot
        // terminate the foreground service. Opens the system dialog once.
        if (defaultTargetPlatform == TargetPlatform.android) {
          try {
            final alreadyExempt =
                await BackgroundLocationService.isIgnoringBatteryOptimisations();
            if (!alreadyExempt) {
              await BackgroundLocationService.requestBatteryOptimisationExemption();
            }
          } catch (_) {}
        }

        // Ensure notification permission is also granted (Android 13+)
        if (await Permission.notification.status.isDenied) {
          final status = await Permission.notification.request();
          if (!status.isGranted) {
            return false;
          }
        }
      }

      return true;
    } catch (_) {
      return true;
    }
  }

  Future<void> updateLocalAttendanceStatus() async {
    if (_activeToken == null || _activeUser == null) return;
    try {
      final today = DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30)).toString().split(' ')[0];
      final regNo = _activeUser!['regNo'] ?? _activeUser!['reg_no'] ?? '';
      
      final response = await apiClient.get(
        '${CollegeIPConfig.defaultURL}/staff/attendance?date=$today',
        token: _activeToken,
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final attendance = data['attendance'] as List? ?? [];
        final userRecords = attendance.where((record) => record['reg_no'].toString() == regNo.toString()).toList();
        
        final hasCheckIn = userRecords.any((record) => record['status'] == 'check_in');
        final hasCheckOut = userRecords.any((record) => record['status'] == 'check_out');
        
        final prefs = await SharedPreferences.getInstance();
        if (hasCheckIn) {
          await prefs.setString('checked_in_date', today);
        } else {
          await prefs.remove('checked_in_date');
        }
        
        if (hasCheckOut) {
          await prefs.setString('checked_out_date', today);
        } else {
          await prefs.remove('checked_out_date');
        }
      }
    } catch (_) {}
  }
}
