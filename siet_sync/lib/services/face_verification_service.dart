import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:camera/camera.dart';
import '../config/college_ip_config.dart';
import '../utils/geofence_check.dart';
import '../utils/wifi_check.dart';
import '../utils/api_response_utils.dart';
import 'pre_verification_service.dart';
import 'client_face_prefilter.dart';

/// Secure face verification service with liveness detection and audit logging
class FaceVerificationService {
  static String get API_URL => CollegeIPConfig.defaultURL;

  // Verification state
  static int _failedAttempts = 0;
  static DateTime? _lockoutEndTime;
  static const int _maxFailedAttempts = 20;
  static const Duration _lockoutDuration = Duration(minutes: 5);

  /// Check if user is locked out
  static bool isLockedOut() {
    if (_lockoutEndTime == null) return false;
    if (DateTime.now().isAfter(_lockoutEndTime!)) {
      // Lockout expired
      _lockoutEndTime = null;
      _failedAttempts = 0;
      return false;
    }
    return true;
  }

  /// Get remaining lockout time in seconds
  static int? getRemainingLockoutSeconds() {
    if (_lockoutEndTime == null) return null;
    if (DateTime.now().isAfter(_lockoutEndTime!)) return null;
    return _lockoutEndTime!.difference(DateTime.now()).inSeconds;
  }

  /// Get verification status
  static Future<Map<String, dynamic>> getVerificationStatus(
    String regNo,
  ) async {
    try {
      final response = await http.get(
        Uri.parse("$API_URL/audit/status/$regNo"),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return {'is_locked': isLockedOut(), 'failed_attempts': _failedAttempts};
    } catch (e) {
      return {
        'is_locked': isLockedOut(),
        'failed_attempts': _failedAttempts,
        'error': e.toString(),
      };
    }
  }

  /// Get security configuration from server
  static Future<Map<String, dynamic>> getConfig() async {
    try {
      final response = await http.get(Uri.parse("$API_URL/config"));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return {};
    } catch (e) {
      return {};
    }
  }

  /// Capture face with liveness detection
  static Future<XFile?> captureFaceWithLiveness(
    CameraController controller, {
    int framesForLiveness = 3,
    bool requireMovement = true,
  }) async {
    try {
      final capturedFrames = <XFile>[];
      final frameInterval = const Duration(milliseconds: 300);

      for (int i = 0; i < framesForLiveness; i++) {
        final image = await controller.takePicture();
        capturedFrames.add(image);

        if (i < framesForLiveness - 1) {
          await Future.delayed(frameInterval);
        }
      }

      if (capturedFrames.isEmpty) {
        return null;
      }

      // Return the last captured frame (server will do quality check)
      return capturedFrames.last;
    } catch (e) {
      debugPrint("Face capture error: $e");
      return null;
    }
  }

  /// Secure face verification with user identity binding
  static Future<Map<String, dynamic>> verifyAndMarkAttendance({
    required String regNo,
    required XFile imageFile,
    VoidCallback? onVerificationComplete,
    VoidCallback? onVerificationFailed,
    Function(String)? onError,
  }) async {
    // Check lockout
    if (isLockedOut()) {
      final remaining = getRemainingLockoutSeconds();
      final errorMsg =
          "Account locked. Try again in ${remaining ?? _lockoutDuration.inSeconds} seconds.";
      onError?.call(errorMsg);
      return {
        'success': false,
        'error': errorMsg,
        'locked_out': true,
        'remaining_seconds': remaining,
      };
    }

    // ── Use pre-verified background cache (VPN + WiFi + Geofence) ────────────
    // getOrRefresh() returns the cached status if it is fresh (< 90 s old).
    // If the cache is stale it runs a synchronous re-check before continuing.
    final preVerif = await PreVerificationService.instance.getOrRefresh();

    // 1. VPN Check
    if (preVerif.vpnError != null) {
      onError?.call(preVerif.vpnError!);
      return {'success': false, 'error': preVerif.vpnError, 'vpn_blocked': true};
    }

    // 2. WiFi/Network check (app only)
    if (!kIsWeb && !AppSettings.allowAnyNetwork && preVerif.wifiError != null) {
      onError?.call(preVerif.wifiError!);
      return {'success': false, 'error': preVerif.wifiError, 'wifi_blocked': true};
    }

    // 3. Geofence check
    final geoDecision = preVerif.geoDecision;
    if (geoDecision != null && geoDecision.error != null) {
      onError?.call(geoDecision.error!);
      return {'success': false, 'error': geoDecision.error, 'geo_blocked': true};
    }

    // Resolve the effective geo decision — use cached one from the service.
    // If no geo decision is cached (geofence disabled), create a no-enforce sentinel.
    final effectiveGeoDecision = geoDecision ??
        const GeoFenceDecision(
          enforced: false,
          insideOuter: null,
          insideInner: null,
          error: null,
        );

    // On-device Google ML Kit edge pre-filter (fast mobile check)
    final prefilter = await ClientFacePreFilterService.evaluateImagePath(imageFile.path);
    if (!prefilter.isValid) {
      final errorMsg = prefilter.message ?? "Face not detected clearly. Position your face in center.";
      onError?.call(errorMsg);
      return {'success': false, 'error': errorMsg, 'face_invalid': true};
    }

    try {
      // Read image bytes
      final bytes = await imageFile.readAsBytes();

      // Build multipart request
      final clientPlatform = kIsWeb ? 'web' : 'app';
      var request = http.MultipartRequest(
        'POST',
        Uri.parse(
          "$API_URL/mark_attendance?reg_no=$regNo",
        ), // Also add as query param
      );

      // Add reg_no as a field (form data)
      request.fields['reg_no'] = regNo;

      // Always send client platform — backend check_wifi and _enforce_web_geofence
      // both rely on this to distinguish web vs app requests
      request.fields['client_platform'] = clientPlatform;
      request.headers['X-Client-Platform'] = clientPlatform;

      // Send location coordinates when geofence was enforced and position was fetched.
      // Use the position cached by PreVerificationService, falling back to the
      // static GeoFenceChecker cache if needed.
      final position = preVerif.position ?? GeoFenceChecker.lastFetchedPosition;
      if (effectiveGeoDecision.enforced) {
        if (position == null) {
          final errorMsg = "Unable to verify your location. Please enable GPS/location services and try again.";
          onError?.call(errorMsg);
          return {'success': false, 'error': errorMsg, 'geo_blocked': true};
        }
        request.fields['client_lat'] = position.latitude.toString();
        request.fields['client_lng'] = position.longitude.toString();
      }


      // Add image as multipart file
      request.files.add(
        http.MultipartFile.fromBytes(
          'image',
          bytes,
          filename: 'face_${DateTime.now().millisecondsSinceEpoch}.jpg',
        ),
      );

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();

      debugPrint("DEBUG: Mark attendance response status: ${response.statusCode}");
      debugPrint("DEBUG: Mark attendance response body: $responseBody");

      // Parse JSON response - handle case where response is not JSON
      Map<String, dynamic> result;
      try {
        result = jsonDecode(responseBody);
      } catch (e) {
        // Server returned non-JSON response (likely HTML error page)
        // Use the response body as the error message
        final errorMsg = _statusDefaultMessage(response.statusCode);
        onError?.call(errorMsg);
        return {'success': false, 'error': errorMsg};
      }

      if (response.statusCode == 200) {
        // Success
        _failedAttempts = 0;
        _lockoutEndTime = null;
        onVerificationComplete?.call();

        return {
          'success': true,
          'message': result['message'] ?? 'Attendance marked successfully',
          'data': result,
        };
      } else if (response.statusCode == 401) {
        // Verification failed
        _failedAttempts++;
        onVerificationFailed?.call();

        // Check if locked out
        if (_failedAttempts >= _maxFailedAttempts) {
          _lockoutEndTime = DateTime.now().add(_lockoutDuration);
        }

        // Handle both 'error' (new format) and 'detail' (legacy format)
        final rawError = (result['error'] ?? result['detail'] ?? '').toString();
        final errorMsg = _friendlyAttendanceError(
          statusCode: response.statusCode,
          rawError: rawError,
        );
        onError?.call(errorMsg);

        return {
          'success': false,
          'error': errorMsg,
          'failed_attempts': _failedAttempts,
          'max_attempts': _maxFailedAttempts,
          'locked_out': _failedAttempts >= _maxFailedAttempts,
          'remaining_seconds': _failedAttempts >= _maxFailedAttempts
              ? _lockoutDuration.inSeconds
              : null,
        };
      } else if (response.statusCode == 423) {
        // Locked out
        final remaining = result['remaining_seconds'] ?? 300;
        _lockoutEndTime = DateTime.now().add(Duration(seconds: remaining));

        final rawError = (result['error'] ?? result['detail'] ?? '').toString();
        final errorMsg = _friendlyAttendanceError(
          statusCode: response.statusCode,
          rawError: rawError,
        );
        onError?.call(errorMsg);

        return {
          'success': false,
          'error': errorMsg,
          'locked_out': true,
          'remaining_seconds': remaining,
        };
      } else {
        // Other error - handle both 'error' (new format) and 'detail' (legacy)
        final rawError = (result['error'] ?? result['detail'] ?? '').toString();
        final errorMsg = _friendlyAttendanceError(
          statusCode: response.statusCode,
          rawError: rawError,
        );
        onError?.call(errorMsg);

        final isGeoBlocked = errorMsg.contains('outside') ||
            errorMsg.contains('geofence') ||
            errorMsg.contains('campus') ||
            errorMsg.contains('location');

        return {
          'success': false,
          'error': errorMsg,
          'geo_blocked': isGeoBlocked,
        };
      }
    } catch (e) {
      final errorMsg = ApiResponseUtils.sanitize(e);
      onError?.call(errorMsg);

      return {'success': false, 'error': errorMsg};
    }
  }

  static String _statusDefaultMessage(int statusCode) {
    switch (statusCode) {
      case 400:
        return 'Invalid capture input. Please retake your photo clearly.';
      case 401:
        return 'Face does not match. Please try again.';
      case 403:
        return 'Action blocked by policy (VPN, WiFi, geofence, or time window).';
      case 404:
        return 'User not found. Please check your registration number.';
      case 423:
        return 'Account locked due to multiple failed attempts.';
      case 500:
        return 'Server error. Please try again later.';
      default:
        return 'Verification failed (HTTP $statusCode). Please try again.';
    }
  }

  static String _friendlyAttendanceError({
    required int statusCode,
    required String rawError,
  }) {
    final msg = rawError.toLowerCase();

    // 1. Presentation Attack Detection (Photo, Video, Screen Replay, Bezel)
    if (msg.contains('liveness') ||
        msg.contains('spoof') ||
        msg.contains('photo') ||
        msg.contains('screen') ||
        msg.contains('replay') ||
        msg.contains('border') ||
        msg.contains('bezel') ||
        msg.contains('printout')) {
      return 'Liveness check failed: Photo, printout, or video replay rejected. Please use a live camera view.';
    }

    // 2. Face Alignment & Detection
    if (msg.contains('no face') ||
        msg.contains('unable to detect') ||
        msg.contains('face not detected') ||
        msg.contains('face is unable')) {
      return 'No face detected. Center your face in the camera frame and try again.';
    }

    // 3. Multiple Faces
    if (msg.contains('multiple faces')) {
      return 'Multiple faces detected. Make sure only your face is visible.';
    }

    // 4. Identity Mismatch
    if (msg.contains('does not match') ||
        msg.contains('verification failed') ||
        statusCode == 401) {
      return 'Face verification failed. Your face does not match the registered profile.';
    }

    // 5. Camera stability & motion blur
    if (msg.contains('blurry') || msg.contains('hold camera steady')) {
      return 'Image is blurry. Hold your phone steady and keep your face inside the frame.';
    }

    // 6. Complete darkness (uncovered lens / pitch black only)
    if (msg.contains('pitch dark') || msg.contains('completely dark')) {
      return 'Camera view is completely dark. Please ensure camera lens is uncovered.';
    }

    // 7. Overexposure / strong direct glare
    if (msg.contains('too bright') || msg.contains('overexposed')) {
      return 'Image is too bright. Avoid strong direct glare and try again.';
    }

    if (msg.contains('face not registered')) {
      return 'Face not registered. Please register your face before marking attendance.';
    }
    if (statusCode == 423 || msg.contains('locked')) {
      return 'Too many failed attempts. Account is temporarily locked. Try again later.';
    }
    if (msg.contains('outside') ||
        msg.contains('fence') ||
        msg.contains('allowed location') ||
        msg.contains('wifi') ||
        msg.contains('wi-fi')) {
      return 'You are outside the allowed geofence area. Please move inside the campus to mark your attendance.';
    }
    if (msg.contains('vpn') || msg.contains('proxy')) {
      return 'VPN/proxy detected. Turn it off and try again.';
    }
    if (msg.contains('not allowed at this time') ||
        msg.contains('available slots') ||
        msg.contains('already marked')) {
      return rawError.trim().isNotEmpty ? rawError : 'Attendance is not allowed at this time.';
    }
    if (msg.contains('empty image')) {
      return 'No image received. Please capture your face again.';
    }

    if (rawError.trim().isNotEmpty) return rawError;
    return _statusDefaultMessage(statusCode);
  }

  /// Legacy attendance marking (without identity binding - less secure)
  static Future<Map<String, dynamic>> markAttendanceLegacy({
    required XFile imageFile,
    VoidCallback? onSuccess,
    Function(String)? onError,
  }) async {
    try {
      final bytes = await imageFile.readAsBytes();
      final multipartFile = http.MultipartFile.fromBytes(
        'image',
        bytes,
        filename: 'face_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );

      final request = http.MultipartRequest(
        'POST',
        Uri.parse("$API_URL/mark_attendance_legacy"),
      );
      request.files.add(multipartFile);

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();

      // Parse JSON response - handle case where response is not JSON
      Map<String, dynamic> result;
      try {
        result = jsonDecode(responseBody);
      } catch (e) {
        final errorMsg = response.statusCode == 500
            ? "Server error. Please try again later."
            : "Unexpected response from server";
        onError?.call(errorMsg);
        return {'success': false, 'error': errorMsg};
      }

      if (response.statusCode == 200) {
        onSuccess?.call();
        return {
          'success': true,
          'message': result['message'] ?? 'Attendance marked',
          'data': result,
          'warning': result['warning'] ?? 'Legacy mode - identity not verified',
        };
      } else {
        // Handle both 'error' (new format) and 'detail' (legacy format)
        final errorMsg =
            result['error'] ?? result['detail'] ?? 'Attendance marking failed';
        onError?.call(errorMsg);
        return {'success': false, 'error': errorMsg};
      }
    } catch (e) {
      final errorMsg = ApiResponseUtils.sanitize(e);
      onError?.call(errorMsg);
      return {'success': false, 'error': errorMsg};
    }
  }

  /// Get audit logs
  static Future<Map<String, dynamic>> getAuditLogs({
    String? regNo,
    int limit = 100,
  }) async {
    try {
      final url = regNo != null
          ? "$API_URL/audit/logs?reg_no=$regNo&limit=$limit"
          : "$API_URL/audit/logs?limit=$limit";

      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return {'logs': [], 'count': 0};
    } catch (e) {
      return {'logs': [], 'count': 0, 'error': e.toString()};
    }
  }

  /// Reset failed attempts (for testing or admin use)
  static void resetFailedAttempts() {
    _failedAttempts = 0;
    _lockoutEndTime = null;
  }

  /// Verify admin face specifically for settings verification (no checks for wifi/gps/etc)
  static Future<Map<String, dynamic>> verifyAdminExclusive({
    required XFile image,
    required String token,
    VoidCallback? onSuccess,
    Function(String)? onError,
  }) async {
    // On-device Google ML Kit edge pre-filter (fast mobile check)
    final prefilter = await ClientFacePreFilterService.evaluateImagePath(
      image.path,
      targetPose: FaceTargetPose.any,
      allowMultipleFaces: false,
    );
    if (!prefilter.isValid) {
      final errorMsg = prefilter.message ?? "Face not detected clearly. Position your face in center.";
      onError?.call(errorMsg);
      return {'success': false, 'error': errorMsg, 'face_invalid': true};
    }

    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$API_URL/admin/face/verify-own-exclusive'),
      );
      request.headers['Authorization'] = 'Bearer $token';

      final fileBytes = await image.readAsBytes();
      request.files.add(
        http.MultipartFile.fromBytes(
          'image',
          fileBytes,
          filename: 'admin_verify.jpg',
        ),
      );

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        onSuccess?.call();
        return {
          'success': true,
          'message': result['message'] ?? 'Admin verified successfully',
        };
      } else {
        final data = jsonDecode(response.body);
        final errorMsg = data['detail'] ?? data['error'] ?? 'Face verification failed';
        onError?.call(errorMsg);
        return {'success': false, 'error': errorMsg};
      }
    } catch (e) {
      final errorMsg = ApiResponseUtils.sanitize(e);
      onError?.call(errorMsg);
      return {'success': false, 'error': errorMsg};
    }
  }

  /// Mark Student Attendance with Biometric Face & Geofence Verification
  static Future<Map<String, dynamic>> markStudentAttendance({
    required String token,
    required XFile imageFile,
    VoidCallback? onVerificationComplete,
    VoidCallback? onVerificationFailed,
    Function(String)? onError,
  }) async {
    // 1. Check pre-verification cache (VPN + WiFi + Geofence)
    final preVerif = await PreVerificationService.instance.getOrRefresh();

    if (preVerif.vpnError != null) {
      onError?.call(preVerif.vpnError!);
      return {'success': false, 'error': preVerif.vpnError, 'vpn_blocked': true};
    }

    // On-device Google ML Kit edge pre-filter (fast mobile check)
    final prefilter = await ClientFacePreFilterService.evaluateImagePath(
      imageFile.path,
      targetPose: FaceTargetPose.any,
      allowMultipleFaces: false,
    );
    if (!prefilter.isValid) {
      final errorMsg = prefilter.message ?? "Face not detected clearly. Position your face in center.";
      onError?.call(errorMsg);
      return {'success': false, 'error': errorMsg, 'face_invalid': true};
    }

    try {
      final bytes = await imageFile.readAsBytes();
      final clientPlatform = kIsWeb ? 'web' : 'app';

      var request = http.MultipartRequest(
        'POST',
        Uri.parse("$API_URL/student/mark-attendance"),
      );

      request.headers['Authorization'] = 'Bearer $token';
      request.headers['X-Client-Platform'] = clientPlatform;
      request.fields['client_platform'] = clientPlatform;

      final position = preVerif.position ?? GeoFenceChecker.lastFetchedPosition;
      if (position != null) {
        request.fields['client_lat'] = position.latitude.toString();
        request.fields['client_lng'] = position.longitude.toString();
      }

      request.files.add(
        http.MultipartFile.fromBytes(
          'image',
          bytes,
          filename: 'stu_face_${DateTime.now().millisecondsSinceEpoch}.jpg',
        ),
      );

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();

      Map<String, dynamic> result;
      try {
        result = jsonDecode(responseBody);
      } catch (e) {
        final errorMsg = _statusDefaultMessage(response.statusCode);
        onError?.call(errorMsg);
        return {'success': false, 'error': errorMsg};
      }

      if (response.statusCode == 200) {
        onVerificationComplete?.call();
        return {
          'success': true,
          'message': result['message'] ?? 'Attendance marked successfully',
          'data': result,
          'summary': result['summary'],
          'session': result['session'],
          'session_display': result['session_display'],
          'time': result['time'],
          'confidence_score': result['confidence_score'],
        };
      } else {
        onVerificationFailed?.call();
        final rawError = (result['detail'] ?? result['error'] ?? 'Attendance marking failed').toString();
        final friendlyError = _friendlyAttendanceError(
          statusCode: response.statusCode,
          rawError: rawError,
        );
        onError?.call(friendlyError);
        return {
          'success': false,
          'error': friendlyError,
          'statusCode': response.statusCode,
        };
      }
    } catch (e) {
      final errorMsg = ApiResponseUtils.sanitize(e);
      onError?.call(errorMsg);
      return {'success': false, 'error': errorMsg};
    }
  }

  /// Mark student biometric face check-out
  static Future<Map<String, dynamic>> markStudentCheckout({
    required String token,
    required XFile imageFile,
    String? sessionId,
    VoidCallback? onVerificationComplete,
    VoidCallback? onVerificationFailed,
    Function(String)? onError,
  }) async {
    // 1. Check pre-verification cache (VPN + WiFi + Geofence)
    final preVerif = await PreVerificationService.instance.getOrRefresh();

    if (preVerif.vpnError != null) {
      onError?.call(preVerif.vpnError!);
      return {'success': false, 'error': preVerif.vpnError, 'vpn_blocked': true};
    }

    // On-device Google ML Kit edge pre-filter (fast mobile check)
    final prefilter = await ClientFacePreFilterService.evaluateImagePath(
      imageFile.path,
      targetPose: FaceTargetPose.any,
      allowMultipleFaces: false,
    );
    if (!prefilter.isValid) {
      final errorMsg = prefilter.message ?? "Face not detected clearly. Position your face in center.";
      onError?.call(errorMsg);
      return {'success': false, 'error': errorMsg, 'face_invalid': true};
    }

    try {
      final bytes = await imageFile.readAsBytes();
      final clientPlatform = kIsWeb ? 'web' : 'app';

      var request = http.MultipartRequest(
        'POST',
        Uri.parse("$API_URL/api/v1/class-session/student-checkout"),
      );

      request.headers['Authorization'] = 'Bearer $token';
      request.headers['X-Client-Platform'] = clientPlatform;
      request.fields['client_platform'] = clientPlatform;
      if (sessionId != null && sessionId.isNotEmpty) {
        request.fields['session_id'] = sessionId;
      }

      final position = preVerif.position ?? GeoFenceChecker.lastFetchedPosition;
      if (position != null) {
        request.fields['client_lat'] = position.latitude.toString();
        request.fields['client_lng'] = position.longitude.toString();
      }

      request.files.add(
        http.MultipartFile.fromBytes(
          'image',
          bytes,
          filename: 'stu_checkout_${DateTime.now().millisecondsSinceEpoch}.jpg',
        ),
      );

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();

      Map<String, dynamic> result;
      try {
        result = jsonDecode(responseBody);
      } catch (e) {
        final errorMsg = _statusDefaultMessage(response.statusCode);
        onError?.call(errorMsg);
        return {'success': false, 'error': errorMsg};
      }

      if (response.statusCode == 200) {
        onVerificationComplete?.call();
        return {
          'success': true,
          'message': result['message'] ?? 'Check-Out marked successfully',
          'data': result,
          'checkout_time': result['checkout_time'],
          'session_display': result['session_display'],
          'time': result['time'],
          'confidence_score': result['confidence_score'],
          'is_checkout': true,
        };
      } else {
        onVerificationFailed?.call();
        final rawError = (result['detail'] ?? result['error'] ?? 'Check-Out verification failed').toString();
        final friendlyError = _friendlyAttendanceError(
          statusCode: response.statusCode,
          rawError: rawError,
        );
        onError?.call(friendlyError);
        return {'success': false, 'error': friendlyError};
      }
    } catch (e) {
      final errorMsg = 'Check-Out connection error: ${ApiResponseUtils.sanitize(e)}';
      onError?.call(errorMsg);
      return {'success': false, 'error': errorMsg};
    }
  }

  /// Submit 3 Multi-Angle Biometric Face Samples & Register Profile
  static Future<Map<String, dynamic>> submitStudentFaceRegistration({
    required String token,
    required List<XFile> imageFiles,
    String notes = '',
    String requestType = 'FIRST_TIME_SELF_ENROLLMENT',
    Function(String)? onError,
  }) async {
    // Validate each angle with on-device ML Kit
    if (imageFiles.length >= 3) {
      const poses = [FaceTargetPose.front, FaceTargetPose.left, FaceTargetPose.right];
      const poseLabels = ['Front', 'Left', 'Right'];
      for (int i = 0; i < 3; i++) {
        final prefilter = await ClientFacePreFilterService.evaluateImagePath(
          imageFiles[i].path,
          targetPose: poses[i],
          allowMultipleFaces: false,
        );
        if (!prefilter.isValid) {
          final errorMsg = "${poseLabels[i]} sample: ${prefilter.message ?? 'Invalid face alignment.'}";
          onError?.call(errorMsg);
          return {'success': false, 'error': errorMsg, 'face_invalid': true};
        }
      }
    }

    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse("$API_URL/student/face-registration/submit"),
      );

      request.headers['Authorization'] = 'Bearer $token';
      request.fields['notes'] = notes;
      request.fields['request_type'] = requestType;

      for (int i = 0; i < imageFiles.length; i++) {
        final bytes = await imageFiles[i].readAsBytes();
        request.files.add(
          http.MultipartFile.fromBytes(
            'image${i + 1}',
            bytes,
            filename: 'pose_${i + 1}_${DateTime.now().millisecondsSinceEpoch}.jpg',
          ),
        );
      }

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();

      Map<String, dynamic> result;
      try {
        result = jsonDecode(responseBody);
      } catch (e) {
        final errorMsg = _statusDefaultMessage(response.statusCode);
        onError?.call(errorMsg);
        return {'success': false, 'error': errorMsg};
      }

      if (response.statusCode == 200) {
        return {
          'success': true,
          'message': result['message'] ?? 'Face biometric profile registered successfully.',
          'is_first_time': result['is_first_time'] ?? false,
          'status': result['status'] ?? 'AUTO_APPROVED',
          'data': result,
        };
      } else {
        final err = (result['detail'] ?? result['error'] ?? 'Registration failed').toString();
        onError?.call(err);
        return {'success': false, 'error': err, 'statusCode': response.statusCode};
      }
    } catch (e) {
      final errorMsg = ApiResponseUtils.sanitize(e);
      onError?.call(errorMsg);
      return {'success': false, 'error': errorMsg};
    }
  }

  /// Fetch Student Face Registration & Prototype Status from Server
  static Future<Map<String, dynamic>> getStudentFaceRegistrationStatus({
    required String token,
  }) async {
    try {
      final res = await http.get(
        Uri.parse("$API_URL/student/face-registration/status"),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200) {
        return jsonDecode(res.body);
      }
      return {'success': false};
    } catch (e) {
      debugPrint("Error fetching face registration status: $e");
      return {'success': false};
    }
  }

  /// Request Permission to Re-register Face from Class Advisor
  static Future<Map<String, dynamic>> requestFaceReregistrationPermission({
    required String token,
    required String reason,
  }) async {
    try {
      final res = await http.post(
        Uri.parse("$API_URL/student/face-registration/request-reregistration"),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'notes': reason}),
      );
      if (res.statusCode == 200) {
        return jsonDecode(res.body);
      }
      final err = jsonDecode(res.body);
      return {'success': false, 'message': err['detail'] ?? 'Failed to submit re-registration request'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  /// Request In-Person Face Registration Session with Class Advisor
  static Future<Map<String, dynamic>> requestAdvisorEnrollmentSession({
    required String token,
    required String notes,
  }) async {
    try {
      final res = await http.post(
        Uri.parse("$API_URL/student/face-registration/request-advisor-session"),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'notes': notes}),
      );
      if (res.statusCode == 200) {
        return jsonDecode(res.body);
      }
      return {'success': false, 'message': 'Failed to submit request'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  /// Toggle Face Re-registration Permission for a student (Advisor / HOD / Admin)
  static Future<Map<String, dynamic>> toggleStudentReregisterPermission({
    required String token,
    required String regNo,
  }) async {
    try {
      final res = await http.post(
        Uri.parse("$API_URL/api/v1/students/$regNo/toggle-reregister-permission"),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200) {
        return jsonDecode(res.body);
      }
      final err = jsonDecode(res.body);
      return {'success': false, 'message': err['detail'] ?? 'Failed to toggle permission'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  /// Fetch list of Student Face Requests for Staff / Advisor / HOD / Admin
  static Future<Map<String, dynamic>> getStaffStudentFaceRequests({
    required String token,
    String? status,
    String? requestType,
    String? search,
    String? dept,
    String? batch,
    int limit = 100,
    int offset = 0,
  }) async {
    try {
      final queryParams = <String, String>{
        'limit': limit.toString(),
        'offset': offset.toString(),
      };
      if (status != null && status.isNotEmpty && status != 'ALL') {
        queryParams['status'] = status;
      }
      if (requestType != null && requestType.isNotEmpty && requestType != 'ALL') {
        queryParams['request_type'] = requestType;
      }
      if (search != null && search.trim().isNotEmpty) {
        queryParams['search'] = search.trim();
      }
      if (dept != null && dept.isNotEmpty && dept != 'ALL') {
        queryParams['dept'] = dept;
      }
      if (batch != null && batch.isNotEmpty && batch != 'ALL') {
        queryParams['batch'] = batch;
      }

      final uri = Uri.parse("$API_URL/api/v1/staff/student-face-requests").replace(
        queryParameters: queryParams,
      );

      final res = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      if (res.statusCode == 200) {
        return jsonDecode(res.body);
      }
      return {'success': false, 'requests': [], 'stats': {}};
    } catch (e) {
      debugPrint("Error fetching staff face requests: $e");
      return {'success': false, 'requests': [], 'stats': {}, 'error': e.toString()};
    }
  }

  /// Review (Approve / Reject) a Student Face Request (Advisor / HOD / Admin)
  static Future<Map<String, dynamic>> reviewStudentFaceRequest({
    required String token,
    required int requestId,
    required String action,
    String? feedback,
  }) async {
    try {
      final res = await http.post(
        Uri.parse("$API_URL/api/v1/staff/student-face-requests/$requestId/review"),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'action': action.toUpperCase(),
          'feedback': feedback ?? '',
        }),
      );

      if (res.statusCode == 200) {
        return jsonDecode(res.body);
      }
      final err = jsonDecode(res.body);
      return {'success': false, 'message': err['detail'] ?? 'Failed to review request'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  /// Bulk Review multiple Student Face Requests at once
  static Future<Map<String, dynamic>> bulkReviewStudentFaceRequests({
    required String token,
    required List<int> requestIds,
    required String action,
    String? feedback,
  }) async {
    try {
      final res = await http.post(
        Uri.parse("$API_URL/api/v1/staff/student-face-requests/bulk-review"),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'request_ids': requestIds,
          'action': action.toUpperCase(),
          'feedback': feedback ?? '',
        }),
      );

      if (res.statusCode == 200) {
        return jsonDecode(res.body);
      }
      final err = jsonDecode(res.body);
      return {'success': false, 'message': err['detail'] ?? 'Failed to bulk review requests'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }
}

/// Verification result model
class VerificationResult {
  final bool success;
  final String? message;
  final String? error;
  final Map<String, dynamic>? data;
  final bool lockedOut;
  final int? remainingSeconds;
  final int failedAttempts;

  VerificationResult({
    required this.success,
    this.message,
    this.error,
    this.data,
    this.lockedOut = false,
    this.remainingSeconds,
    this.failedAttempts = 0,
  });

  factory VerificationResult.fromMap(Map<String, dynamic> map) {
    return VerificationResult(
      success: map['success'] ?? false,
      message: map['message'],
      error: map['error'],
      data: map['data'],
      lockedOut: map['locked_out'] ?? false,
      remainingSeconds: map['remaining_seconds'],
      failedAttempts: map['failed_attempts'] ?? 0,
    );
  }
}
