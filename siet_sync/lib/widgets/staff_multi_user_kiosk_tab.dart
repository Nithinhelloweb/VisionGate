import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:camera/camera.dart';

import '../config/college_ip_config.dart';
import '../services/client_face_prefilter.dart';

// ─────────────────────────────────────────────────────────────────────────────
// StaffMultiUserKioskTab
// Provides two modes via a segmented control:
//   • Scanner  – Start/End session, live camera face-scan with HUD, recent scans list
//   • Register – Form to register a new student face (3-photo capture with preview)
// ─────────────────────────────────────────────────────────────────────────────
class StaffMultiUserKioskTab extends StatefulWidget {
  final String token;
  final Map<String, dynamic> user;

  const StaffMultiUserKioskTab({
    super.key,
    required this.token,
    required this.user,
  });

  @override
  State<StaffMultiUserKioskTab> createState() => _StaffMultiUserKioskTabState();
}

enum _KioskMode { markAttendance, register, manageStudents }
enum _RegStep {
  detailsForm,
  instructions,
  capturingFront,
  capturingLeft,
  capturingRight,
  reviewPhotos,
  success,
}

class _StaffMultiUserKioskTabState extends State<StaffMultiUserKioskTab>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {

  @override
  bool get wantKeepAlive => true;
  // ── mode ──────────────────────────────────────────────────────────────────
  _KioskMode _mode = _KioskMode.markAttendance;

  // ── scanner state ─────────────────────────────────────────────────────────
  String _scanMessage = '';
  bool _scanSuccess = false;

  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  bool _isCameraReady = false;
  bool _isCameraInitializing = false;
  bool _isScanning = false;
  bool _hasCameraError = false;
  String _cameraErrorMessage = '';

  Map<String, dynamic>? _lastScannedStudent;
  bool _showVerificationOverlay = false;
  Timer? _overlayTimer;

  List<Map<String, dynamic>> _recentScans = [];
  int _totalScans = 0;

  // ── HUD animation controller ──────────────────────────────────────────────
  late AnimationController _animationController;

  // ── registration state ────────────────────────────────────────────────────
  final _regNoCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _deptCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  _RegStep _regStep = _RegStep.detailsForm;
  bool _isPoseSatisfying = false;
  String _satisfactionStatusText = '';
  final Map<String, String> _capturedAngles = {}; // 'front', 'left', 'right' -> base64
  final List<String> _capturedImages = []; // base64 strings
  bool _isRegistering = false;
  bool _isOverwriteMode = false;
  bool _isCheckingDuplicate = false;
  String _regMessage = '';
  bool _regSuccess = false;
  Map<String, dynamic>? _registeredStudentResult;

  CameraController? _regCameraController;
  bool _isRegCameraReady = false;
  bool _isRegCameraInitializing = false;

  // ── student management state ──────────────────────────────────────────────
  List<Map<String, dynamic>> _registeredStudents = [];
  bool _isLoadingStudents = false;
  String _studentSearchQuery = '';
  final _studentSearchCtrl = TextEditingController();

  // ── shared ────────────────────────────────────────────────────────────────
  String get _apiUrl => CollegeIPConfig.defaultURL;

  // ─────────────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    // Fetch records on tab load (camera will only start when camera section is explicitly opened)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _fetchRecentRecords();
        _fetchRegisteredStudents();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _animationController.dispose();
    _overlayTimer?.cancel();
    _cameraController?.dispose();
    _cameraController = null;
    _isCameraReady = false;
    _regCameraController?.dispose();
    _regCameraController = null;
    _isRegCameraReady = false;
    _regNoCtrl.dispose();
    _nameCtrl.dispose();
    _deptCtrl.dispose();
    _studentSearchCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Keep camera preview session continuously active.
    // Do not interrupt the WebRTC/Camera preview on notification slider or OS shade drags.
  }

  // ─────────────────────────────────────────────────────────────────────────
  // MARK ATTENDANCE LOGIC
  // ─────────────────────────────────────────────────────────────────────────

  Future<List<CameraDescription>> _getFastAvailableCameras() async {
    if (_cameras.isNotEmpty) {
      return _cameras;
    }
    try {
      _cameras = await availableCameras().timeout(
        const Duration(seconds: 3),
        onTimeout: () => [],
      );
    } catch (_) {
      _cameras = [];
    }
    return _cameras;
  }

  Future<void> _initScanCamera({bool forceRetry = false}) async {
    if (!mounted) return;
    if (forceRetry) {
      _isCameraInitializing = false;
      _isCameraReady = false;
      await _cameraController?.dispose();
      _cameraController = null;
    }
    if (_isCameraInitializing) return;
    if (_isCameraReady && _cameraController != null && _cameraController!.value.isInitialized) {
      return;
    }

    _isCameraInitializing = true;
    if (mounted) {
      setState(() {
        _hasCameraError = false;
        _cameraErrorMessage = '';
      });
    }

    try {
      if (_cameraController != null) {
        await _cameraController!.dispose();
        _cameraController = null;
      }

      final cameras = await _getFastAvailableCameras();

      if (cameras.isEmpty) {
        if (mounted) {
          setState(() {
            _hasCameraError = true;
            _cameraErrorMessage = 'No camera device found on this system. Please attach a camera or enable camera permissions.';
            _scanMessage = '❌ No camera found on this device.';
          });
        }
        return;
      }

      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      // Sub-second instant launch with ResolutionPreset.medium
      CameraController ctrl = CameraController(
        front,
        ResolutionPreset.medium,
        imageFormatGroup: kIsWeb ? null : ImageFormatGroup.jpeg,
        enableAudio: false,
      );

      try {
        await ctrl.initialize().timeout(
          const Duration(seconds: 4),
          onTimeout: () => throw TimeoutException('Camera initialization timed out'),
        );
      } catch (_) {
        // Fast Fallback to ResolutionPreset.low
        ctrl = CameraController(
          front,
          ResolutionPreset.low,
          imageFormatGroup: kIsWeb ? null : ImageFormatGroup.jpeg,
          enableAudio: false,
        );
        await ctrl.initialize().timeout(
          const Duration(seconds: 4),
          onTimeout: () => throw TimeoutException('Fallback camera setup timed out'),
        );
      }

      if (mounted) {
        setState(() {
          _cameraController = ctrl;
          _isCameraReady = true;
          _hasCameraError = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasCameraError = true;
          _cameraErrorMessage = 'Camera access error: $e. Please allow camera permissions in your browser.';
          _scanMessage = '❌ Camera error: $e';
        });
      }
    } finally {
      _isCameraInitializing = false;
    }
  }

  Future<void> _stopScanCamera() async {
    _isCameraInitializing = false;
    _isCameraReady = false;
    await _cameraController?.dispose();
    _cameraController = null;
    if (mounted) setState(() {});
  }

  Future<void> _stopRegCamera() async {
    _isRegCameraInitializing = false;
    _isRegCameraReady = false;
    await _regCameraController?.dispose();
    _regCameraController = null;
    if (mounted) setState(() {});
  }

  Future<void> _fetchRecentRecords() async {
    try {
      final res = await http.get(
        Uri.parse('$_apiUrl/staff/kiosk/recent-records'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );
      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body);
        setState(() {
          _recentScans = List<Map<String, dynamic>>.from(data['records'] ?? []);
          _totalScans = data['total_scans'] ?? 0;
        });
      }
    } catch (_) {}
  }

  Future<void> _scanFace() async {
    if (_isScanning) return;
    if (!_isCameraReady || _cameraController == null || !_cameraController!.value.isInitialized) {
      await _initScanCamera();
      if (!_isCameraReady || _cameraController == null || !_cameraController!.value.isInitialized) return;
    }
    setState(() {
      _isScanning = true;
      _scanMessage = 'Verifying student face...';
      _scanSuccess = false;
    });
    try {
      final file = await _cameraController!.takePicture();

      // On-device Google ML Kit pre-filter
      final prefilter = await ClientFacePreFilterService.evaluateImagePath(
        file.path,
        targetPose: FaceTargetPose.any,
        allowMultipleFaces: false,
      );

      if (!prefilter.isValid) {
        _overlayTimer?.cancel();
        if (mounted) {
          setState(() {
            _lastScannedStudent = null;
            _showVerificationOverlay = true;
            _scanMessage = '❌ ${prefilter.message ?? "Face not detected clearly. Position your face in center."}';
            _scanSuccess = false;
            _isScanning = false;
          });
        }
        _overlayTimer = Timer(const Duration(seconds: 4), () {
          if (mounted) setState(() => _showVerificationOverlay = false);
        });
        return;
      }

      final bytes = await file.readAsBytes();
      final b64 = base64Encode(bytes);

      final currentHour = DateTime.now().hour;
      final sessionType = currentHour < 13 ? 'FN' : 'AN';

      final res = await http.post(
        Uri.parse('$_apiUrl/staff/kiosk/quick-scan'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'image_base64': b64,
          'session_type': sessionType,
        }),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final student = data['student'];
        _overlayTimer?.cancel();
        if (mounted) {
          setState(() {
            _lastScannedStudent = student;
            _showVerificationOverlay = true;
            _scanMessage = '✅ Attendance Marked: ${student['name']} (${student['reg_no']})';
            _scanSuccess = true;
          });
        }
        _fetchRecentRecords();
        _overlayTimer = Timer(const Duration(seconds: 4), () {
          if (mounted) setState(() => _showVerificationOverlay = false);
        });
      } else {
        final errText = _parseError(res.body);
        _overlayTimer?.cancel();
        if (mounted) {
          setState(() {
            _lastScannedStudent = null;
            _showVerificationOverlay = true;
            _scanMessage = (errText.contains('Not a valid face') ||
                    errText.contains('already marked') ||
                    errText.contains('already') ||
                    errText.contains('Controlled Access Error') ||
                    errText.contains('permission'))
                ? errText
                : '❌ Not a valid face. Student is not registered.';
            _scanSuccess = false;
          });
        }
        _overlayTimer = Timer(const Duration(seconds: 4), () {
          if (mounted) setState(() => _showVerificationOverlay = false);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _scanMessage = '❌ Error: $e';
          _scanSuccess = false;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isScanning = false;
        });
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // REGISTRATION LOGIC
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _initRegCamera({bool forceRetry = false}) async {
    if (!mounted) return;
    if (forceRetry) {
      _isRegCameraInitializing = false;
      _isRegCameraReady = false;
      await _regCameraController?.dispose();
      _regCameraController = null;
    }
    if (_isRegCameraInitializing) return;
    if (_isRegCameraReady && _regCameraController != null && _regCameraController!.value.isInitialized) {
      return;
    }

    _isRegCameraInitializing = true;
    try {
      if (_regCameraController != null) {
        await _regCameraController!.dispose();
        _regCameraController = null;
      }

      final cameras = await _getFastAvailableCameras();
      if (cameras.isEmpty) return;

      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      // Fast initialization with ResolutionPreset.medium
      CameraController ctrl = CameraController(
        front,
        ResolutionPreset.medium,
        imageFormatGroup: kIsWeb ? null : ImageFormatGroup.jpeg,
        enableAudio: false,
      );

      try {
        await ctrl.initialize().timeout(
          const Duration(seconds: 4),
          onTimeout: () => throw TimeoutException('Camera setup timed out'),
        );
      } catch (_) {
        ctrl = CameraController(
          front,
          ResolutionPreset.low,
          imageFormatGroup: kIsWeb ? null : ImageFormatGroup.jpeg,
          enableAudio: false,
        );
        await ctrl.initialize().timeout(
          const Duration(seconds: 4),
          onTimeout: () => throw TimeoutException('Fallback camera setup timed out'),
        );
      }

      if (mounted) {
        setState(() {
          _regCameraController = ctrl;
          _isRegCameraReady = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _regMessage = '❌ Camera error: $e';
        });
      }
    } finally {
      _isRegCameraInitializing = false;
    }
  }

  Future<void> _start3AngleCaptureSequence() async {
    if (!_isRegCameraReady || _regCameraController == null) {
      await _initRegCamera();
      if (!_isRegCameraReady) return;
    }
    setState(() {
      _regStep = _RegStep.capturingFront;
      _isPoseSatisfying = false;
      _satisfactionStatusText = '';
    });
  }

  Future<void> _satisfyAndCaptureCurrentPose() async {
    if (!_isRegCameraReady || _regCameraController == null || _isPoseSatisfying) return;

    setState(() {
      _isPoseSatisfying = true;
      if (_regStep == _RegStep.capturingFront) {
        _satisfactionStatusText = '✓ Front View Satisfied!';
      } else if (_regStep == _RegStep.capturingLeft) {
        _satisfactionStatusText = '✓ Left View Satisfied!';
      } else if (_regStep == _RegStep.capturingRight) {
        _satisfactionStatusText = '✓ Right View Satisfied!';
      }
    });

    try {
      final file = await _regCameraController!.takePicture();

      final FaceTargetPose targetPose = _regStep == _RegStep.capturingFront
          ? FaceTargetPose.front
          : (_regStep == _RegStep.capturingLeft ? FaceTargetPose.left : FaceTargetPose.right);

      final prefilter = await ClientFacePreFilterService.evaluateImagePath(
        file.path,
        targetPose: targetPose,
        allowMultipleFaces: false,
      );

      if (!prefilter.isValid) {
        if (mounted) {
          setState(() {
            _regMessage = '❌ ${prefilter.message ?? "Invalid pose alignment."}';
            _isPoseSatisfying = false;
          });
        }
        return;
      }

      final bytes = await file.readAsBytes();
      final b64 = base64Encode(bytes);

      String angleKey = 'front';
      if (_regStep == _RegStep.capturingFront) angleKey = 'front';
      if (_regStep == _RegStep.capturingLeft) angleKey = 'left';
      if (_regStep == _RegStep.capturingRight) angleKey = 'right';

      setState(() {
        _capturedAngles[angleKey] = b64;
        _syncCapturedImagesList();
      });

      await Future.delayed(const Duration(milliseconds: 500));

      if (!mounted) return;

      if (_regStep == _RegStep.capturingFront) {
        setState(() {
          _regStep = _RegStep.capturingLeft;
          _isPoseSatisfying = false;
          _satisfactionStatusText = '';
        });
      } else if (_regStep == _RegStep.capturingLeft) {
        setState(() {
          _regStep = _RegStep.capturingRight;
          _isPoseSatisfying = false;
          _satisfactionStatusText = '';
        });
      } else if (_regStep == _RegStep.capturingRight) {
        setState(() {
          _regStep = _RegStep.reviewPhotos;
          _isPoseSatisfying = false;
          _satisfactionStatusText = '';
        });
        _regCameraController?.dispose();
        _regCameraController = null;
        _isRegCameraReady = false;
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _regMessage = '❌ Capture error: $e';
          _isPoseSatisfying = false;
        });
      }
    }
  }

  void _syncCapturedImagesList() {
    _capturedImages.clear();
    if (_capturedAngles.containsKey('front')) _capturedImages.add(_capturedAngles['front']!);
    if (_capturedAngles.containsKey('left')) _capturedImages.add(_capturedAngles['left']!);
    if (_capturedAngles.containsKey('right')) _capturedImages.add(_capturedAngles['right']!);
  }

  void _resetRegistrationFlow() {
    setState(() {
      _regStep = _RegStep.detailsForm;
      _capturedAngles.clear();
      _capturedImages.clear();
      _regNoCtrl.clear();
      _nameCtrl.clear();
      _deptCtrl.clear();
      _regMessage = '';
      _regSuccess = false;
      _isPoseSatisfying = false;
      _satisfactionStatusText = '';
      _registeredStudentResult = null;
      _isOverwriteMode = false;
      _isCheckingDuplicate = false;
    });
  }

  Future<void> _validateFormAndContinueToCapture() async {
    final regNo = _regNoCtrl.text.trim();
    final name = _nameCtrl.text.trim();
    final dept = _deptCtrl.text.trim();

    // 1. Mandatory Field Validations
    if (regNo.isEmpty) {
      setState(() {
        _regMessage = '❌ Registration Number is required.';
        _regSuccess = false;
      });
      return;
    }
    if (regNo.length < 3) {
      setState(() {
        _regMessage = '❌ Registration Number must be at least 3 characters long.';
        _regSuccess = false;
      });
      return;
    }
    if (!RegExp(r'^[a-zA-Z0-9/\-_]+$').hasMatch(regNo)) {
      setState(() {
        _regMessage = '❌ Registration Number contains invalid characters. Use letters, numbers, -, /, or _ only.';
        _regSuccess = false;
      });
      return;
    }

    if (name.isEmpty) {
      setState(() {
        _regMessage = '❌ Full Name is required.';
        _regSuccess = false;
      });
      return;
    }
    if (name.length < 2) {
      setState(() {
        _regMessage = '❌ Full Name must be at least 2 characters long.';
        _regSuccess = false;
      });
      return;
    }
    if (!RegExp(r'^[a-zA-Z\s.]+$').hasMatch(name)) {
      setState(() {
        _regMessage = '❌ Full Name should contain only letters, spaces, and dots.';
        _regSuccess = false;
      });
      return;
    }

    if (dept.isEmpty) {
      setState(() {
        _regMessage = '❌ Department is required.';
        _regSuccess = false;
      });
      return;
    }
    if (dept.length < 2) {
      setState(() {
        _regMessage = '❌ Department must be at least 2 characters long.';
        _regSuccess = false;
      });
      return;
    }

    // 2. Duplicate Check unless in explicit Re-Register / Overwrite mode
    if (!_isOverwriteMode) {
      final existingLocal = _registeredStudents.firstWhere(
        (s) => (s['reg_no'] ?? '').toString().toLowerCase() == regNo.toLowerCase(),
        orElse: () => {},
      );
      if (existingLocal.isNotEmpty) {
        final exName = existingLocal['name'] ?? 'existing student';
        final exDept = existingLocal['dept'] ?? '';
        setState(() {
          _regMessage = '❌ Registration Number "$regNo" is ALREADY registered to $exName ($exDept). Duplicate registrations are not allowed.';
          _regSuccess = false;
        });
        return;
      }

      setState(() {
        _isCheckingDuplicate = true;
        _regMessage = 'Checking for duplicate registration number...';
      });

      try {
        final res = await http.get(
          Uri.parse('$_apiUrl/staff/kiosk/student/check/$regNo'),
          headers: {
            'Authorization': 'Bearer ${widget.token}',
            'Content-Type': 'application/json',
          },
        );
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          if (data['exists'] == true) {
            final exName = data['name'] ?? 'existing student';
            final exDept = data['dept'] ?? '';
            setState(() {
              _regMessage = '❌ Student with Registration Number "$regNo" is ALREADY registered to $exName ($exDept). Use Manage tab to edit.';
              _regSuccess = false;
              _isCheckingDuplicate = false;
            });
            return;
          }
        }
      } catch (e) {
        debugPrint('Duplicate API check error: $e');
      } finally {
        if (mounted) {
          setState(() {
            _isCheckingDuplicate = false;
          });
        }
      }
    }

    setState(() {
      _regMessage = '';
      _regStep = _RegStep.instructions;
    });
    await _initRegCamera();
  }

  void _retakePhotos() {
    setState(() {
      _capturedAngles.clear();
      _capturedImages.clear();
      _isPoseSatisfying = false;
      _satisfactionStatusText = '';
      _regStep = _RegStep.instructions;
    });
    _initRegCamera();
  }

  Future<void> _registerStudent() async {
    final regNo = _regNoCtrl.text.trim();
    final name = _nameCtrl.text.trim();
    final dept = _deptCtrl.text.trim();

    if (regNo.isEmpty || name.isEmpty || dept.isEmpty) {
      setState(() {
        _regMessage = '❌ Please enter Registration Number, Full Name, and Department.';
        _regSuccess = false;
        _regStep = _RegStep.detailsForm;
      });
      return;
    }

    _syncCapturedImagesList();

    if (_capturedImages.length < 3) {
      setState(() {
        _regMessage = '❌ Please capture all 3 angles (Front, Left, Right) first.';
        _regSuccess = false;
        _regStep = _RegStep.instructions;
      });
      return;
    }

    setState(() {
      _isRegistering = true;
      _regMessage = '';
    });

    try {
      final res = await http.post(
        Uri.parse('$_apiUrl/staff/kiosk/student/register'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'reg_no': regNo,
          'name': name,
          'dept': dept,
          'images_base64': _capturedImages,
          'overwrite': _isOverwriteMode,
        }),
      );
      if (res.statusCode == 200) {
        setState(() {
          _registeredStudentResult = {
            'reg_no': regNo,
            'name': name,
            'dept': dept,
          };
          _regMessage = '✅ Student registered successfully!';
          _regSuccess = true;
          _regStep = _RegStep.success;
        });
        await _fetchRegisteredStudents();
      } else {
        setState(() {
          _regMessage = '❌ ${_parseError(res.body)}';
          _regSuccess = false;
        });
      }
    } catch (e) {
      setState(() {
        _regMessage = '❌ $e';
        _regSuccess = false;
      });
    } finally {
      setState(() {
        _isRegistering = false;
      });
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────────────────────────────────

  String _parseError(String body) {
    try {
      final d = jsonDecode(body);
      String errStr = d['detail'] ?? d['error'] ?? d['message'] ?? body;
      if (errStr.startsWith('{') && errStr.endsWith('}')) {
        try {
          final inner = jsonDecode(errStr);
          errStr = inner['detail'] ?? inner['error'] ?? inner['message'] ?? errStr;
        } catch (_) {}
      }
      return errStr;
    } catch (_) {
      return body;
    }
  }

  Future<void> _onModeChanged(_KioskMode m) async {
    if (m == _mode) return;
    setState(() {
      _mode = m;
    });

    await _stopScanCamera();
    await _stopRegCamera();
    if (m == _KioskMode.manageStudents) {
      await _fetchRegisteredStudents();
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final int selectedIndex = _mode == _KioskMode.markAttendance
        ? 0
        : (_mode == _KioskMode.register ? 1 : 2);

    return Container(
      color: Colors.transparent,
      child: Column(
        children: [
          _buildSegmentedControl(isDark),
          Expanded(
            child: IndexedStack(
              index: selectedIndex,
              children: [
                _buildMarkAttendanceMode(isDark),
                _buildRegisterMode(isDark),
                _buildManageStudentsMode(isDark),
              ],
            ),
          ),
        ],
      ),
    );
  }



  // ── Segmented control ──────────────────────────────────────────────────────
  Widget _buildSegmentedControl(bool isDark) {
    final bg = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF5F5F5);
    return Container(
      color: isDark ? const Color(0xFF121212) : Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.all(4),
        child: Row(
          children: [
            _segmentBtn(_KioskMode.markAttendance, Icons.touch_app_rounded, 'Attendance', isDark),
            const SizedBox(width: 4),
            _segmentBtn(_KioskMode.register, Icons.person_add_alt_1, 'Register', isDark),
            const SizedBox(width: 4),
            _segmentBtn(_KioskMode.manageStudents, Icons.people_alt_rounded, 'Manage', isDark),
          ],
        ),
      ),
    );
  }

  Widget _segmentBtn(_KioskMode mode, IconData icon, String label, bool isDark) {
    final selected = _mode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () => _onModeChanged(mode),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 2),
          decoration: BoxDecoration(
            color: selected
                ? (isDark ? const Color(0xFF3949AB) : const Color(0xFF3949AB))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            boxShadow: selected
                ? [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 6, offset: const Offset(0, 2))]
                : [],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: selected ? Colors.white : (isDark ? Colors.grey[400] : Colors.grey[600])),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: selected ? Colors.white : (isDark ? Colors.grey[400] : Colors.grey[600]),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // MARK ATTENDANCE MODE UI (Responsive & Modern)
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildMarkAttendanceMode(bool isDark) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 900;
        final isTablet = constraints.maxWidth >= 600 && constraints.maxWidth < 900;

        return Stack(
          children: [
            SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                children: [

                  // Stat bar
                  Container(
                    color: isDark ? const Color(0xFF13151D) : const Color(0xFFF0F0FF),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    child: Row(
                      children: [
                        _statChip(Icons.people, '$_totalScans verified today', const Color(0xFF6366F1)),
                        const Spacer(),
                        IconButton(
                          onPressed: _fetchRecentRecords,
                          icon: const Icon(Icons.refresh, size: 20, color: Color(0xFF6366F1)),
                          tooltip: 'Refresh History',
                        ),
                      ],
                    ),
                  ),

                  if (isDesktop)
                    // ─────────────────────────────────────────────────────────────
                    // DESKTOP 2-COLUMN STUDIO KIOSK LAYOUT
                    // ─────────────────────────────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // LEFT CONTROL & INSTRUCTION SIDEBAR (350px)
                          SizedBox(
                            width: 350,
                            child: Column(
                              children: [
                                // Kiosk Studio Info Box
                                Container(
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    color: isDark ? const Color(0xFF1E293B) : Colors.white,
                                    borderRadius: BorderRadius.circular(24),
                                    border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.25)),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.08),
                                        blurRadius: 15,
                                        offset: const Offset(0, 4),
                                      )
                                    ],
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(10),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(Icons.center_focus_strong_rounded, color: Color(0xFF6366F1), size: 22),
                                          ),
                                          const SizedBox(width: 12),
                                          const Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Face Scanner Kiosk',
                                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                                ),
                                                Text(
                                                  'AI Attendance Verification',
                                                  style: TextStyle(fontSize: 12, color: Colors.grey),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 16),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF10B981).withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(20),
                                          border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.circle, color: Color(0xFF10B981), size: 8),
                                            SizedBox(width: 8),
                                            Text(
                                              'SYSTEM ONLINE & READY',
                                              style: TextStyle(color: Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.bold),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 14),

                                // Instructions Box
                                Container(
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    color: isDark ? const Color(0xFF1E293B) : Colors.white,
                                    borderRadius: BorderRadius.circular(24),
                                    border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.05),
                                        blurRadius: 10,
                                      )
                                    ],
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Positioning Guidelines',
                                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                      ),
                                      const SizedBox(height: 14),
                                      _instructionItemDesktop(Icons.face_outlined, 'Position full face', 'Center your head inside scanner oval'),
                                      const SizedBox(height: 12),
                                      _instructionItemDesktop(Icons.wb_sunny_outlined, 'Ensure good lighting', 'Avoid strong backlight behind face'),
                                      const SizedBox(height: 12),
                                      _instructionItemDesktop(Icons.do_not_disturb_on_outlined, 'No face obstruction', 'Remove dark glasses, hats, or masks'),
                                      const SizedBox(height: 12),
                                      _instructionItemDesktop(Icons.crop_free_rounded, 'Uncropped View', 'Full head, neck & shoulders visible'),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 14),

                                // Desktop Primary Verification Action Button
                                Container(
                                  width: double.infinity,
                                  height: 60,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(20),
                                    gradient: _isScanning
                                        ? null
                                        : const LinearGradient(
                                            colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
                                          ),
                                    boxShadow: _isScanning
                                        ? null
                                        : [
                                            BoxShadow(
                                              color: const Color(0xFF4F46E5).withValues(alpha: 0.4),
                                              blurRadius: 16,
                                              offset: const Offset(0, 6),
                                            ),
                                          ],
                                  ),
                                  child: ElevatedButton(
                                    onPressed: _isScanning ? null : _scanFace,
                                    style: ElevatedButton.styleFrom(
                                      elevation: 0,
                                      backgroundColor: Colors.transparent,
                                      foregroundColor: Colors.white,
                                      shadowColor: Colors.transparent,
                                      disabledBackgroundColor: Colors.black54,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        if (_isScanning)
                                          const SizedBox(
                                            width: 22,
                                            height: 22,
                                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                                          )
                                        else
                                          const Icon(Icons.verified_user_rounded, color: Colors.white, size: 22),
                                        const SizedBox(width: 10),
                                        Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              _isScanning ? 'Verifying Face...' : 'Verify Face & Mark Attendance',
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                                            ),
                                            const Text(
                                              'Click button or tap camera feed',
                                              style: TextStyle(fontSize: 10, color: Colors.white70),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 20),

                          // RIGHT CAMERA VIEWPORT (Expanded, Height 540)
                          Expanded(
                            child: Container(
                              height: 540,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.4), width: 1.5),
                                color: const Color(0xFF090D16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.4),
                                    blurRadius: 20,
                                    offset: const Offset(0, 8),
                                  )
                                ],
                              ),
                              clipBehavior: Clip.hardEdge,
                              child: _buildCameraContainer(isDark, isDesktop, isTablet),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    // ─────────────────────────────────────────────────────────────
                    // MOBILE / TABLET SINGLE COLUMN LAYOUT
                    // ─────────────────────────────────────────────────────────────
                    Column(
                      children: [
                        Container(
                          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                          height: isTablet ? 460 : 420,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: const Color(0xFF3949AB).withValues(alpha: 0.5), width: 1.5),
                            color: const Color(0xFF090D16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.4),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              )
                            ],
                          ),
                          clipBehavior: Clip.hardEdge,
                          child: _buildCameraContainer(isDark, isDesktop, isTablet),
                        ),
                      ],
                    ),

                  // Scan message alert bar
                  if (_scanMessage.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: (_isScanning || _scanMessage.contains('Verifying'))
                            ? Colors.orange.withValues(alpha: 0.1)
                            : (_scanSuccess ? Colors.green.withValues(alpha: 0.1) : Colors.red.withValues(alpha: 0.1)),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: (_isScanning || _scanMessage.contains('Verifying'))
                              ? Colors.orange.withValues(alpha: 0.4)
                              : (_scanSuccess ? Colors.green.withValues(alpha: 0.4) : Colors.red.withValues(alpha: 0.4)),
                        ),
                      ),
                      child: Text(
                        _scanMessage,
                        style: TextStyle(
                          color: (_isScanning || _scanMessage.contains('Verifying'))
                              ? Colors.orange[800]
                              : (_scanSuccess ? Colors.green[700] : Colors.red[700]),
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),

                  // Recent scans list history
                  Container(
                    margin: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                          child: Row(
                            children: [
                              const Icon(Icons.history_rounded, size: 20, color: Color(0xFF6366F1)),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text(
                                  'Recent Attendance Records',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 6),
                              InkWell(
                                onTap: _fetchRecentRecords,
                                borderRadius: BorderRadius.circular(8),
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text('View all', style: TextStyle(color: Color(0xFF6366F1), fontSize: 12, fontWeight: FontWeight.w600)),
                                      SizedBox(width: 2),
                                      Icon(Icons.chevron_right_rounded, size: 16, color: Color(0xFF6366F1)),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                        _recentScans.isEmpty
                            ? const Padding(
                                padding: EdgeInsets.symmetric(vertical: 24),
                                child: Center(
                                  child: Text('No attendance marked yet today — tap the button to verify face!',
                                      style: TextStyle(color: Colors.grey, fontSize: 13)),
                                ),
                              )
                            : ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: math.min(_recentScans.length, 5),
                                separatorBuilder: (ctx, index) => const Divider(height: 1, indent: 16, endIndent: 16),
                                itemBuilder: (ctx, i) {
                                  final s = _recentScans[i];
                                  final t = DateTime.tryParse(s['scanned_at'] ?? '');
                                  final timeStr = t != null
                                      ? '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}'
                                      : '08:50 AM';
                                  return ListTile(
                                    dense: true,
                                    leading: Container(
                                      width: 36,
                                      height: 36,
                                      decoration: const BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Color(0xFFDCFCE7),
                                      ),
                                      child: const Icon(Icons.check_rounded, color: Color(0xFF16A34A), size: 20),
                                    ),
                                    title: Text(s['name'] ?? 'Unknown',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                    subtitle: Text('${s['reg_no'] ?? ''} • ${s['dept'] ?? ''}',
                                        style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                    trailing: Text('$timeStr\nToday',
                                        textAlign: TextAlign.end,
                                        style: const TextStyle(fontSize: 11, color: Colors.grey, height: 1.3)),
                                  );
                                },
                              ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            _buildStudentVerificationOverlay(),
          ],
        );
      },
    );
  }

  Widget _instructionItemDesktop(IconData icon, String title, String sub) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF6366F1).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: const Color(0xFF6366F1), size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              Text(sub, style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSafeCameraPreview(CameraController? controller, {BoxFit fit = BoxFit.contain}) {
    if (controller == null || !controller.value.isInitialized) {
      return Container(
        color: const Color(0xFF090D16),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Color(0xFF6366F1)),
              SizedBox(height: 14),
              Text('Initializing Camera...', style: TextStyle(color: Colors.white, fontSize: 13)),
            ],
          ),
        ),
      );
    }

    final previewSize = controller.value.previewSize;
    if (previewSize == null) {
      return CameraPreview(controller, key: ValueKey(controller.hashCode));
    }

    return ClipRect(
      child: Container(
        color: const Color(0xFF090D16),
        alignment: Alignment.center,
        child: FittedBox(
          fit: fit,
          child: SizedBox(
            width: previewSize.height,
            height: previewSize.width,
            child: CameraPreview(controller, key: ValueKey(controller.hashCode)),
          ),
        ),
      ),
    );
  }

  Widget _buildCameraContainer(bool isDark, bool isDesktop, bool isTablet) {
    if (_hasCameraError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.videocam_off_rounded, color: Colors.redAccent, size: 52),
              const SizedBox(height: 12),
              const Text(
                'Camera Feed Unavailable',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                _cameraErrorMessage.isNotEmpty ? _cameraErrorMessage : 'Check camera permissions or device connection.',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              ElevatedButton.icon(
                onPressed: () => _initScanCamera(forceRetry: true),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Retry Camera'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (!_isCameraReady && !_isCameraInitializing) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                  border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.4), width: 2),
                ),
                child: const Icon(Icons.videocam_outlined, color: Color(0xFF6366F1), size: 44),
              ),
              const SizedBox(height: 18),
              const Text(
                'Camera Scanner Standby',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Camera is off to save system resources. Tap below to activate live face scanner.',
                style: TextStyle(color: Colors.white70, fontSize: 12),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _initScanCamera,
                icon: const Icon(Icons.videocam_rounded, size: 20),
                label: const Text('Open Camera Scanner', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 4,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_isCameraInitializing || _cameraController == null || !_cameraController!.value.isInitialized) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Color(0xFF6366F1)),
            const SizedBox(height: 16),
            const Text(
              'Opening Camera Scanner...',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: _isScanning ? null : _scanFace,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Uncropped Safe Camera Preview
          _buildSafeCameraPreview(_cameraController, fit: BoxFit.contain),

          // 2. HUD Mask Overlay (Dark vignette + center scanner oval + corner brackets + grid)
          AnimatedBuilder(
            animation: _animationController,
            builder: (context, child) {
              return CustomPaint(
                painter: _KioskFaceScannerMaskPainter(
                  scanProgress: _animationController.value,
                  faceDetected: true,
                  faceQuality: 0.90,
                ),
              );
            },
          ),

          // 4. Top Status Overlay Bar
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < 360;
                return Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.4)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.circle, color: Color(0xFF10B981), size: 8),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                isNarrow ? 'Live Camera Feed' : 'Live Camera Feed • Full Face View',
                                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: _stopScanCamera,
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: isNarrow ? 8 : 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white30),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.power_settings_new_rounded, color: Colors.white, size: 14),
                            if (!isNarrow) ...[
                              const SizedBox(width: 6),
                              const Text(
                                'Turn Off Camera',
                                style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ] else ...[
                              const SizedBox(width: 4),
                              const Text(
                                'Turn Off',
                                style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),

          // 5. Bottom Tap Instruction Pill
          Positioned(
            bottom: 16,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white24),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _isScanning ? Icons.sync_rounded : Icons.touch_app_rounded,
                      color: const Color(0xFF818CF8),
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _isScanning ? 'Verifying face with AI...' : 'Tap camera feed or click button to scan face',
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }



  Widget _buildStudentVerificationOverlay() {
    if (!_showVerificationOverlay) {
      return const SizedBox.shrink();
    }

    // FAILURE CASE: Not a valid face / Not registered / Duplicate Attendance
    if (_lastScannedStudent == null) {
      final cleanMsg = _scanMessage.replaceAll('❌ ', '').replaceAll('⚠️ ', '').trim();
      final isControlledAccess = cleanMsg.contains('Controlled Access Error') || cleanMsg.contains('permission');
      final isDuplicate = cleanMsg.contains('already marked') || cleanMsg.contains('already');
      final isNotRegistered = cleanMsg.contains('not registered') || cleanMsg.contains('not found');

      // Theme Colors & Icons based on type
      final Color badgeBg = isControlledAccess
          ? const Color(0xFFF3E8FF)
          : (isDuplicate
              ? const Color(0xFFFEF3C7)
              : (isNotRegistered ? const Color(0xFFFEE2E2) : const Color(0xFFFFF7ED)));
      final Color accentColor = isControlledAccess
          ? const Color(0xFF7E22CE)
          : (isDuplicate
              ? const Color(0xFFD97706)
              : (isNotRegistered ? const Color(0xFFDC2626) : const Color(0xFFEA580C)));
      final IconData badgeIcon = isControlledAccess
          ? Icons.admin_panel_settings_rounded
          : (isDuplicate
              ? Icons.history_toggle_off_rounded
              : (isNotRegistered ? Icons.person_off_rounded : Icons.face_retouching_off_rounded));

      final String cardTitle = isControlledAccess
          ? 'Controlled Access Error'
          : (isDuplicate
              ? 'Attendance Already Marked'
              : (isNotRegistered ? 'Student Profile Not Registered' : 'Not A Valid Face'));

      final String subTitleText = isControlledAccess
          ? cleanMsg
          : (isDuplicate
              ? 'Validation Rule: Each user can only mark attendance once per session (FN/AN).'
              : (isNotRegistered
                  ? 'This face profile is not found in database. Please register the student profile first.'
                  : 'Position face clearly inside the camera scanner frame.'));

      return Positioned.fill(
        child: Container(
          color: Colors.black.withValues(alpha: 0.8),
          child: Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.all(28),
              constraints: const BoxConstraints(maxWidth: 460),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(color: accentColor.withValues(alpha: 0.35), blurRadius: 28, offset: const Offset(0, 10))
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Glowing Circular Icon Badge
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: badgeBg,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: accentColor.withValues(alpha: 0.2), blurRadius: 16)
                      ],
                    ),
                    child: Icon(badgeIcon, color: accentColor, size: 48),
                  ),
                  const SizedBox(height: 18),

                  // Professional Title
                  Text(
                    cardTitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: accentColor, fontWeight: FontWeight.bold, fontSize: 20),
                  ),
                  const SizedBox(height: 10),

                  // Dynamic Error / Validation Detail Box
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: accentColor.withValues(alpha: 0.2)),
                    ),
                    child: Text(
                      cleanMsg.isNotEmpty ? cleanMsg : cardTitle,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.black87, fontSize: 14, fontWeight: FontWeight.w600, height: 1.35),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Subtitle Context Explanation
                  Text(
                    subTitleText,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12, height: 1.3),
                  ),
                  const SizedBox(height: 24),

                  // Action Buttons
                  if (isDuplicate)
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accentColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                        onPressed: () => setState(() => _showVerificationOverlay = false),
                        icon: const Icon(Icons.check_circle_outline_rounded, size: 20),
                        label: const Text('Understood & Close', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      ),
                    )
                  else
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onPressed: () => setState(() => _showVerificationOverlay = false),
                            child: const Text('Close', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
                          ),
                        ),
                        if (isNotRegistered) ...[
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF6366F1),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                              onPressed: () {
                                setState(() {
                                  _showVerificationOverlay = false;
                                  _mode = _KioskMode.register;
                                  _regStep = _RegStep.detailsForm;
                                });
                              },
                              icon: const Icon(Icons.person_add_alt_1_rounded, color: Colors.white, size: 18),
                              label: const Text('Register Now', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ],
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // SUCCESS CASE: Student Verified
    final student = _lastScannedStudent!;
    final name = student['name'] ?? 'Student';
    final regNo = student['reg_no'] ?? '';
    final dept = student['dept'] ?? '';

    final now = DateTime.now();
    final timeStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} ${now.hour >= 12 ? 'PM' : 'AM'}';

    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.75),
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981),
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(color: const Color(0xFF10B981).withValues(alpha: 0.4), blurRadius: 20)
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle_rounded, color: Colors.white, size: 22),
                        SizedBox(width: 8),
                        Text('Verified!', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text('Attendance marked successfully', style: TextStyle(color: Colors.white70, fontSize: 13)),
                ],
              ),
            ),
            Positioned(
              top: 20,
              left: 20,
              child: TextButton(
                onPressed: () {
                  setState(() {
                    _showVerificationOverlay = false;
                  });
                },
                child: const Text('Cancel', style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600)),
              ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 18),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$regNo • $dept',
                              style: const TextStyle(color: Colors.grey, fontSize: 13),
                            ),
                          ],
                        ),
                        const Spacer(),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              timeStr,
                              style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            const SizedBox(height: 4),
                            const Text('Today', style: TextStyle(color: Colors.grey, fontSize: 12)),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _showVerificationOverlay = false;
                          });
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6366F1),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: const Text('Done', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // REGISTRATION MODE UI (Guided 3-Angle Auto-Capture Wizard)
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildRegisterMode(bool isDark) {
    int index = 0;
    switch (_regStep) {
      case _RegStep.detailsForm:
        index = 0;
        break;
      case _RegStep.instructions:
        index = 1;
        break;
      case _RegStep.capturingFront:
      case _RegStep.capturingLeft:
      case _RegStep.capturingRight:
        index = 2;
        break;
      case _RegStep.reviewPhotos:
        index = 3;
        break;
      case _RegStep.success:
        index = 4;
        break;
    }

    return IndexedStack(
      index: index,
      children: [
        _buildRegDetailsForm(isDark),
        _buildRegInstructions(isDark),
        _buildRegCameraScanner(isDark),
        _buildRegReviewPhotos(isDark),
        _buildRegSuccessScreen(isDark),
      ],
    );
  }

  // Step 1: Student Profile Details Form
  Widget _buildRegDetailsForm(bool isDark) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [

              // Info Banner Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF4F46E5).withValues(alpha: 0.12),
                  const Color(0xFF7C3AED).withValues(alpha: 0.12),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.person_add_alt_1_rounded, color: Color(0xFF6366F1), size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Face Profile Registration',
                        style: TextStyle(color: Color(0xFF6366F1), fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Register student details and capture face automatically from 3 angles.',
                        style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 12, height: 1.4),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Form Card
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade200),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05), blurRadius: 16, offset: const Offset(0, 6)),
              ],
            ),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.badge_outlined, color: Color(0xFF6366F1), size: 22),
                      const SizedBox(width: 8),
                      const Text('Student Profile Details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _buildTextField(_regNoCtrl, 'Registration Number', Icons.badge_outlined,
                      validator: (v) => (v?.trim().isEmpty ?? true) ? 'Registration Number is required' : null),
                  const SizedBox(height: 14),
                  _buildTextField(_nameCtrl, 'Full Name', Icons.person_outline,
                      validator: (v) => (v?.trim().isEmpty ?? true) ? 'Full Name is required' : null),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: const [
                      'CSE', 'IT', 'AIDS', 'AIML', 'CYBER', 'ECE', 'EEE', 'VLSI', 'MECH', 'BME', 'BT', 'FT', 'AGRI', 'CIVIL'
                    ].contains(_deptCtrl.text.trim().toUpperCase())
                        ? _deptCtrl.text.trim().toUpperCase()
                        : 'CSE',
                    decoration: InputDecoration(
                      labelText: 'Department',
                      prefixIcon: const Icon(Icons.school_outlined, size: 20, color: Color(0xFF3949AB)),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.3)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFF3949AB), width: 1.5),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    ),
                    items: const [
                      'CSE', 'IT', 'AIDS', 'AIML', 'CYBER', 'ECE', 'EEE', 'VLSI', 'MECH', 'BME', 'BT', 'FT', 'AGRI', 'CIVIL'
                    ].map((d) => DropdownMenuItem<String>(value: d, child: Text(d))).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _deptCtrl.text = val;
                        });
                      }
                    },
                  ),
                  
                  if (_regMessage.isNotEmpty && !_regSuccess) ...[
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline_rounded, color: Colors.red, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _regMessage,
                              style: const TextStyle(color: Colors.red, fontSize: 13, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Continue Button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: _isCheckingDuplicate
                    ? null
                    : const LinearGradient(colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)]),
                boxShadow: _isCheckingDuplicate
                    ? null
                    : [
                        BoxShadow(color: const Color(0xFF4F46E5).withValues(alpha: 0.4), blurRadius: 14, offset: const Offset(0, 4)),
                      ],
              ),
              child: ElevatedButton(
                onPressed: _isCheckingDuplicate ? null : _validateFormAndContinueToCapture,
                style: ElevatedButton.styleFrom(
                  elevation: 0,
                  backgroundColor: Colors.transparent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                ),
                child: _isCheckingDuplicate
                    ? const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                          SizedBox(width: 10),
                          Text('Checking Duplicate...', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        ],
                      )
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('Continue to Face Capture', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          SizedBox(width: 8),
                          Icon(Icons.arrow_forward_rounded, size: 20),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  },
);
}

  // Step 2: Onboarding Instructions Screen
  Widget _buildRegInstructions(bool isDark) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [

              // Step Header
          Row(
            children: [
              IconButton(
                onPressed: () => setState(() => _regStep = _RegStep.detailsForm),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              const SizedBox(width: 4),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Register New Profile', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  Text('Step 1 of 4', style: TextStyle(color: isDark ? Colors.white60 : Colors.grey[600], fontSize: 12)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Illustration & Instructions Card
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade200),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05), blurRadius: 16, offset: const Offset(0, 6)),
              ],
            ),
            child: Column(
              children: [
                // Glowing Avatar Icon Circle
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: const Color(0xFF6366F1).withValues(alpha: 0.2), blurRadius: 20)
                    ],
                  ),
                  child: const Center(
                    child: Icon(Icons.person_rounded, size: 42, color: Color(0xFF6366F1)),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  "Let's get started!",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                ),
                const SizedBox(height: 6),
                Text(
                  'We will capture your face from multiple angles automatically.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: isDark ? Colors.white70 : Colors.grey[600], fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 22),

                // Checklist Items
                _regChecklistItem(Icons.check_circle_outline_rounded, 'Follow the on-screen instructions', isDark),
                const SizedBox(height: 12),
                _regChecklistItem(Icons.wb_sunny_outlined, 'Ensure good lighting', isDark),
                const SizedBox(height: 12),
                _regChecklistItem(Icons.visibility_outlined, 'Remove glasses, mask or cap', isDark),
                const SizedBox(height: 12),
                _regChecklistItem(Icons.sentiment_satisfied_alt_rounded, 'Keep a neutral expression', isDark),

                const SizedBox(height: 28),

                // Start Capture Button
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      gradient: const LinearGradient(colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)]),
                      boxShadow: [
                        BoxShadow(color: const Color(0xFF4F46E5).withValues(alpha: 0.4), blurRadius: 14, offset: const Offset(0, 4)),
                      ],
                    ),
                    child: ElevatedButton(
                      onPressed: _start3AngleCaptureSequence,
                      style: ElevatedButton.styleFrom(
                        elevation: 0,
                        backgroundColor: Colors.transparent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                      ),
                      child: const Text('Start Capture', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  },
);
}

  Widget _regChecklistItem(IconData icon, String label, bool isDark) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: const Color(0xFF10B981).withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check, size: 14, color: Color(0xFF10B981)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }

  // Step 3: Guided 3-Angle Camera Scanner (Front, Left, Right)
  Widget _buildRegCameraScanner(bool isDark) {
    String stepTitle = 'Front View';
    int stepNum = 2;
    String instructionText = 'Look straight at the camera';
    bool isLeft = false;
    bool isRight = false;

    if (_regStep == _RegStep.capturingLeft) {
      stepTitle = 'Left View';
      stepNum = 3;
      instructionText = 'Turn your face slightly to your left';
      isLeft = true;
    } else if (_regStep == _RegStep.capturingRight) {
      stepTitle = 'Right View';
      stepNum = 4;
      instructionText = 'Turn your face slightly to your right';
      isRight = true;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [

              // Step Header Bar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: () {
                  setState(() => _regStep = _RegStep.instructions);
                },
                icon: const Icon(Icons.close_rounded),
              ),
              Column(
                children: [
                  const Text('Capture Your Face', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  Text('Step $stepNum of 5', style: TextStyle(color: isDark ? Colors.white60 : Colors.grey[600], fontSize: 12)),
                ],
              ),
              const SizedBox(width: 48),
            ],
          ),
          const SizedBox(height: 10),

          // Top Status Pill
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF6366F1).withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF6366F1), width: 1.2),
              ),
              child: Text(
                stepTitle,
                style: const TextStyle(color: Color(0xFF6366F1), fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Large Camera Viewport with Blueprint Grid, Face Oval, Corners & Directional Arrows
          if (_isRegCameraReady && _regCameraController != null)
            AnimatedBuilder(
              animation: _animationController,
              builder: (context, child) {
                return Container(
                  height: 380,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0xFF6366F1), width: 2),
                    color: const Color(0xFF111319),
                    boxShadow: [
                      BoxShadow(color: const Color(0xFF6366F1).withValues(alpha: 0.25), blurRadius: 20)
                    ],
                  ),
                  clipBehavior: Clip.hardEdge,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Blueprint Grid Background
                      CustomPaint(painter: _KioskGridBackgroundPainter()),

                      // Camera Feed with Tap Gesture
                      GestureDetector(
                        onTap: _satisfyAndCaptureCurrentPose,
                        child: _buildSafeCameraPreview(_regCameraController),
                      ),

                      // HUD Face Mask & Corner Brackets [ ]
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _KioskFaceScannerMaskPainter(
                            scanProgress: _animationController.value,
                            faceDetected: true,
                            faceQuality: 0.90,
                          ),
                        ),
                      ),

                      // Directional Arc Arrow Overlay (Left/Right)
                      if (isLeft || isRight)
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _KioskDirectionalArrowPainter(isLeft: isLeft, isRight: isRight),
                          ),
                        ),

                      // Bottom Dark Instruction Pill
                      Positioned(
                        bottom: 76,
                        left: 20,
                        right: 20,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF161822).withValues(alpha: 0.85),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.white24),
                            ),
                            child: Text(
                              instructionText,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ),

                      // Position Satisfaction Action & Guidance Bar
                      Positioned(
                        bottom: 14,
                        left: 20,
                        right: 20,
                        child: Center(
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              gradient: LinearGradient(
                                colors: _isPoseSatisfying
                                    ? [const Color(0xFF10B981), const Color(0xFF059669)]
                                    : [const Color(0xFF4F46E5), const Color(0xFF7C3AED)],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: (_isPoseSatisfying ? const Color(0xFF10B981) : const Color(0xFF4F46E5)).withValues(alpha: 0.4),
                                  blurRadius: 10,
                                ),
                              ],
                            ),
                            child: ElevatedButton.icon(
                              onPressed: _isPoseSatisfying ? null : _satisfyAndCaptureCurrentPose,
                              icon: _isPoseSatisfying
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Icon(Icons.center_focus_strong_rounded, size: 18, color: Colors.white),
                              label: Text(
                                _isPoseSatisfying
                                    ? (_satisfactionStatusText.isNotEmpty ? _satisfactionStatusText : '✓ Position Satisfied!')
                                    : 'Position Satisfied — Capture Pose',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              style: ElevatedButton.styleFrom(
                                elevation: 0,
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            )
          else
            Container(
              height: 320,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                color: Colors.black12,
              ),
              child: const Center(
                child: CircularProgressIndicator(color: Color(0xFF6366F1)),
              ),
            ),

          const SizedBox(height: 20),

          // Bottom Step Progress Dots (● ○ ○ -> ● ● ○ -> ● ● ●)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _stepDotIndicator(1, _regStep == _RegStep.capturingFront, _capturedAngles.containsKey('front')),
              const SizedBox(width: 12),
              _stepDotIndicator(2, _regStep == _RegStep.capturingLeft, _capturedAngles.containsKey('left')),
              const SizedBox(width: 12),
              _stepDotIndicator(3, _regStep == _RegStep.capturingRight, _capturedAngles.containsKey('right')),
            ],
          ),
        ],
      ),
    );
  },
);
}

  Widget _stepDotIndicator(int stepNum, bool isCurrent, bool isCompleted) {
    Color color = Colors.grey.withValues(alpha: 0.3);
    Widget child = Text('$stepNum', style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold));

    if (isCompleted) {
      color = const Color(0xFF10B981);
      child = const Icon(Icons.check, size: 14, color: Colors.white);
    } else if (isCurrent) {
      color = const Color(0xFF6366F1);
      child = Text('$stepNum', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold));
    }

    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: isCurrent ? [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 8)] : null,
      ),
      child: Center(child: child),
    );
  }

  // Step 4: Photo Review & Confirm Screen
  Widget _buildRegReviewPhotos(bool isDark) {
    final frontBytes = _capturedAngles['front'] != null ? base64Decode(_capturedAngles['front']!) : null;
    final leftBytes = _capturedAngles['left'] != null ? base64Decode(_capturedAngles['left']!) : null;
    final rightBytes = _capturedAngles['right'] != null ? base64Decode(_capturedAngles['right']!) : null;

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [

              // Step Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: _retakePhotos,
                icon: const Icon(Icons.close_rounded),
              ),
              Column(
                children: [
                  const Text('Review Your Photos', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  Text('Step 5 of 5', style: TextStyle(color: isDark ? Colors.white60 : Colors.grey[600], fontSize: 12)),
                ],
              ),
              const SizedBox(width: 48),
            ],
          ),
          const SizedBox(height: 20),

          // 3 Angles Photo Cards
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _reviewAngleCard('Front View', frontBytes),
              _reviewAngleCard('Left View', leftBytes),
              _reviewAngleCard('Right View', rightBytes),
            ],
          ),

          const SizedBox(height: 24),

          // Status & Instructions
          Center(
            child: Column(
              children: [
                const Text(
                  'Great! All views captured successfully.',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(height: 4),
                Text(
                  'Please review your photos before final submission.',
                  style: TextStyle(color: isDark ? Colors.white70 : Colors.grey[600], fontSize: 12),
                ),
              ],
            ),
          ),

          const SizedBox(height: 28),

          // Submit Registration Button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: _isRegistering
                    ? null
                    : const LinearGradient(colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)]),
                boxShadow: _isRegistering
                    ? null
                    : [
                        BoxShadow(color: const Color(0xFF4F46E5).withValues(alpha: 0.4), blurRadius: 14, offset: const Offset(0, 4)),
                      ],
              ),
              child: ElevatedButton.icon(
                onPressed: _isRegistering ? null : _registerStudent,
                icon: _isRegistering
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.check_circle_rounded, size: 20),
                label: Text(
                  _isRegistering ? 'Submitting Registration...' : 'Submit Registration',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                style: ElevatedButton.styleFrom(
                  elevation: 0,
                  backgroundColor: Colors.transparent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Retake Photos Button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: TextButton.icon(
              onPressed: _retakePhotos,
              icon: const Icon(Icons.refresh_rounded, color: Color(0xFF6366F1), size: 18),
              label: const Text('Retake Photos', style: TextStyle(color: Color(0xFF6366F1), fontWeight: FontWeight.bold, fontSize: 14)),
            ),
          ),

          if (_regMessage.isNotEmpty && !_regSuccess)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
                ),
                child: Text(
                  _regMessage,
                  style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  },
);
}

  Widget _reviewAngleCard(String label, Uint8List? bytes) {
    return Column(
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 95,
              height: 115,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFF10B981), width: 2.5),
                boxShadow: [
                  BoxShadow(color: const Color(0xFF10B981).withValues(alpha: 0.25), blurRadius: 10)
                ],
              ),
              clipBehavior: Clip.hardEdge,
              child: bytes != null
                  ? Image.memory(bytes, fit: BoxFit.cover)
                  : Container(color: Colors.grey.shade800),
            ),
            Positioned(
              bottom: -8,
              right: -8,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Color(0xFF10B981),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check, color: Colors.white, size: 14),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
        ),
      ],
    );
  }

  // Step 5: Registration Success Screen
  Widget _buildRegSuccessScreen(bool isDark) {
    final regNo = _registeredStudentResult?['reg_no'] ?? _regNoCtrl.text;
    final name = _registeredStudentResult?['name'] ?? _nameCtrl.text;
    final dept = _registeredStudentResult?['dept'] ?? _deptCtrl.text;

    return LayoutBuilder(
      builder: (context, constraints) {
        return Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [

                Container(
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade200),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08), blurRadius: 24, offset: const Offset(0, 8)),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Celebration Green Checkmark Badge
                      Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(color: const Color(0xFF10B981).withValues(alpha: 0.3), blurRadius: 20)
                          ],
                        ),
                        child: const Center(
                          child: Icon(Icons.check_circle_rounded, size: 48, color: Color(0xFF10B981)),
                        ),
                      ),
                      const SizedBox(height: 20),

                      const Text(
                        'Registration Complete!',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Face profile and 512-D vector embeddings saved successfully to database.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: isDark ? Colors.white70 : Colors.grey[600], fontSize: 13),
                      ),
                      const SizedBox(height: 24),

                      // Registered Student Card Summary
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF13151D) : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.25)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: const BoxDecoration(
                                color: Color(0xFFEEF2FF),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.person_rounded, color: Color(0xFF4F46E5), size: 28),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Reg: $regNo • Dept: $dept',
                                    style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.grey[600]),
                                  ),
                                  const SizedBox(height: 4),
                                  const Row(
                                    children: [
                                      Icon(Icons.verified_rounded, size: 14, color: Color(0xFF10B981)),
                                      SizedBox(width: 4),
                                      Text(
                                        'Verified & Database Enrolled',
                                        style: TextStyle(color: Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Mark Attendance Now Button
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            gradient: const LinearGradient(colors: [Color(0xFF10B981), Color(0xFF059669)]),
                            boxShadow: [
                              BoxShadow(color: const Color(0xFF10B981).withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 4)),
                            ],
                          ),
                          child: ElevatedButton.icon(
                            onPressed: () {
                              _resetRegistrationFlow();
                              setState(() {
                                _mode = _KioskMode.markAttendance;
                              });
                              _initScanCamera();
                            },
                            icon: const Icon(Icons.bolt_rounded, size: 20, color: Colors.white),
                            label: const Text('Verify & Mark Attendance Now', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white)),
                            style: ElevatedButton.styleFrom(
                              elevation: 0,
                              backgroundColor: Colors.transparent,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      // Go to Kiosk Home Outlined Button
                      SizedBox(
                        width: double.infinity,
                        height: 46,
                        child: OutlinedButton(
                          onPressed: () {
                            _resetRegistrationFlow();
                            setState(() {
                              _mode = _KioskMode.markAttendance;
                            });
                            _initScanCamera();
                          },
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: isDark ? Colors.white24 : Colors.grey.shade300),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          child: Text('Go to Kiosk Home', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: isDark ? Colors.white70 : Colors.grey[700])),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Student Management Methods ─────────────────────────────────────────────

  Future<void> _fetchRegisteredStudents() async {
    setState(() {
      _isLoadingStudents = true;
    });
    try {
      final res = await http.get(
        Uri.parse('$_apiUrl/staff/kiosk/students'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Content-Type': 'application/json',
        },
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final list = List<Map<String, dynamic>>.from(data['students'] ?? []);
        if (mounted) {
          setState(() {
            _registeredStudents = list;
          });
        }
      }
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingStudents = false;
        });
      }
    }
  }

  Future<void> _deleteStudentProfile(String regNo, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Entire Student Data?', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to remove ALL data for $name ($regNo)?\n\nThis will permanently remove the student profile, face embeddings, attendance records, leave logs, and all related database records across the entire system. This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete Entire Data', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final res = await http.delete(
        Uri.parse('$_apiUrl/staff/kiosk/student/$regNo'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Content-Type': 'application/json',
        },
      );
      if (res.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('✓ Completely removed all data for $regNo from the entire database'), backgroundColor: Colors.green),
          );
        }
        _fetchRegisteredStudents();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('❌ Error: ${_parseError(res.body)}'), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Connection error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _clearStudentAttendance(String regNo, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Clear Attendance Record Only?', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to clear all attendance records for $name ($regNo)?\n\nThis will remove their attendance logs while preserving their student profile and face registration.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber.shade800,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear Attendance', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final res = await http.delete(
        Uri.parse('$_apiUrl/staff/kiosk/student/$regNo/attendance'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Content-Type': 'application/json',
        },
      );
      if (res.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('✓ Cleared attendance records for $regNo'), backgroundColor: Colors.green),
          );
        }
        _fetchRegisteredStudents();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('❌ Error: ${_parseError(res.body)}'), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Connection error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _reRegisterStudent(Map<String, dynamic> student) {
    _resetRegistrationFlow();
    setState(() {
      _regNoCtrl.text = (student['reg_no'] ?? '').toString();
      _nameCtrl.text = (student['name'] ?? '').toString();
      _deptCtrl.text = (student['dept'] ?? '').toString();
      _mode = _KioskMode.register;
      _regStep = _RegStep.detailsForm;
    });
  }

  Future<void> _showStudentAttendanceHistory(Map<String, dynamic> student) async {
    final regNo = (student['reg_no'] ?? '').toString();
    final name = (student['name'] ?? 'Student').toString();
    final dept = (student['dept'] ?? '').toString();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final historyFuture = _fetchStudentHistoryData(regNo);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          height: MediaQuery.of(ctx).size.height * 0.75,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 20,
                spreadRadius: 2,
              )
            ],
          ),
          child: Column(
            children: [
              // Modal Handle & Header Bar
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: const Color(0xFF6366F1).withValues(alpha: 0.15),
                      child: Text(
                        name.isNotEmpty ? name[0].toUpperCase() : 'S',
                        style: const TextStyle(color: Color(0xFF6366F1), fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (dept.isNotEmpty)
                            Text(
                              dept,
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? Colors.white60 : Colors.grey[600],
                              ),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.cleaning_services_rounded, color: Colors.amber),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _clearStudentAttendance(regNo, name);
                      },
                      tooltip: 'Clear Attendance Record Only',
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(ctx),
                      tooltip: 'Close',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const Divider(height: 1),
              
              // Attendance History Content
              Expanded(
                child: FutureBuilder<Map<String, dynamic>>(
                  future: historyFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(color: Color(0xFF6366F1)),
                      );
                    }
                    if (snapshot.hasError) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.error_outline_rounded, size: 44, color: Colors.redAccent),
                              const SizedBox(height: 12),
                              Text(
                                'Error loading attendance history:\n${snapshot.error}',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: isDark ? Colors.white70 : Colors.grey[700], fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    final data = snapshot.data ?? {};
                    final history = List<Map<String, dynamic>>.from(data['history'] ?? []);
                    final totalRecords = data['total_records'] ?? history.length;

                    if (history.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.history_rounded, size: 54, color: Colors.grey[400]),
                              const SizedBox(height: 12),
                              const Text(
                                'No Attendance Records Yet',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'No check-in logs recorded for this student.',
                                style: TextStyle(color: isDark ? Colors.white60 : Colors.grey[600], fontSize: 13),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.history_toggle_off_rounded, size: 18, color: Color(0xFF6366F1)),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Attendance Logs',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: isDark ? Colors.white70 : Colors.grey[800],
                                    ),
                                  ),
                                ],
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF6366F1).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '$totalRecords Total Scans',
                                  style: const TextStyle(
                                    color: Color(0xFF6366F1),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                            itemCount: history.length,
                            separatorBuilder: (c, i) => const SizedBox(height: 10),
                            itemBuilder: (c, idx) {
                              final log = history[idx];
                              var dtStr = (log['date_time'] ?? '').toString();
                              if (dtStr.contains('.')) {
                                dtStr = dtStr.split('.').first;
                              }
                              dtStr = dtStr.replaceAll('T', ' ');

                              final sessionType = (log['session_type'] ?? 'FN').toString();
                              final status = (log['status'] ?? 'Present').toString();
                              final markedBy = (log['marked_by'] ?? 'Staff Panel Kiosk').toString();
                              final score = (log['score'] is num) ? (log['score'] as num).toDouble() : 1.0;
                              final scorePct = (score <= 1.0 ? score * 100 : score).toStringAsFixed(1);

                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF2A2A3E) : Colors.grey.shade50,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: isDark ? Colors.white10 : Colors.grey.shade200,
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF10B981).withValues(alpha: 0.12),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.check_circle_rounded,
                                        color: Color(0xFF10B981),
                                        size: 18,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Wrap(
                                            crossAxisAlignment: WrapCrossAlignment.center,
                                            spacing: 6,
                                            runSpacing: 2,
                                            children: [
                                              Text(
                                                dtStr.isNotEmpty ? dtStr : 'Recorded',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12.5,
                                                ),
                                              ),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: sessionType == 'FN'
                                                      ? Colors.amber.withValues(alpha: 0.15)
                                                      : Colors.orange.withValues(alpha: 0.15),
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: Text(
                                                  sessionType,
                                                  style: TextStyle(
                                                    color: sessionType == 'FN' ? Colors.amber[800] : Colors.orange[800],
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 10,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            'By: $markedBy • Match: $scorePct%',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: isDark ? Colors.white60 : Colors.grey[600],
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF10B981).withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: const Color(0xFF10B981).withValues(alpha: 0.3),
                                        ),
                                      ),
                                      child: Text(
                                        status,
                                        style: const TextStyle(
                                          color: Color(0xFF10B981),
                                          fontWeight: FontWeight.bold,
                                          fontSize: 10.5,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<Map<String, dynamic>> _fetchStudentHistoryData(String regNo) async {
    final res = await http.get(
      Uri.parse('$_apiUrl/staff/kiosk/student/$regNo/history'),
      headers: {
        'Authorization': 'Bearer ${widget.token}',
        'Content-Type': 'application/json',
      },
    );
    if (res.statusCode == 200) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    } else {
      throw Exception(_parseError(res.body));
    }
  }

  // ── Manage Students View ───────────────────────────────────────────────────

  Widget _buildManageStudentsMode(bool isDark) {
    final filteredList = _registeredStudents.where((s) {
      final q = _studentSearchQuery.toLowerCase();
      final reg = (s['reg_no'] ?? '').toString().toLowerCase();
      final name = (s['name'] ?? '').toString().toLowerCase();
      final dept = (s['dept'] ?? '').toString().toLowerCase();
      return q.isEmpty || reg.contains(q) || name.contains(q) || dept.contains(q);
    }).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        return RefreshIndicator(
          onRefresh: _fetchRegisteredStudents,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [

                // Search Bar & Filter Header Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade200),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05), blurRadius: 10)
                ],
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.people_alt_rounded, color: Color(0xFF6366F1), size: 20),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'My Registered Students',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          '${_registeredStudents.length} Profiles',
                          style: const TextStyle(color: Color(0xFF6366F1), fontWeight: FontWeight.bold, fontSize: 11),
                        ),
                      ),
                      IconButton(
                        onPressed: _fetchRegisteredStudents,
                        icon: const Icon(Icons.refresh_rounded, size: 20),
                        tooltip: 'Refresh Student List',
                        padding: const EdgeInsets.all(4),
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Search TextField
                  TextField(
                    controller: _studentSearchCtrl,
                    onChanged: (val) {
                      setState(() {
                        _studentSearchQuery = val.trim();
                      });
                    },
                    decoration: InputDecoration(
                      hintText: 'Search by Reg No, Name, or Department...',
                      prefixIcon: const Icon(Icons.search_rounded, size: 20, color: Color(0xFF6366F1)),
                      suffixIcon: _studentSearchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _studentSearchCtrl.clear();
                                setState(() {
                                  _studentSearchQuery = '';
                                });
                              },
                            )
                          : null,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.3)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFF6366F1), width: 1.5),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      isDense: true,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Student Cards List / Loading / Empty State
            if (_isLoadingStudents)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: CircularProgressIndicator(color: Color(0xFF6366F1)),
                ),
              )
            else if (filteredList.isEmpty)
              Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade200),
                ),
                child: Column(
                  children: [
                    Icon(Icons.person_search_rounded, size: 48, color: Colors.grey[400]),
                    const SizedBox(height: 12),
                    Text(
                      _registeredStudents.isEmpty ? 'No Students Registered Under You' : 'No Students Match Search Filter',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _registeredStudents.isEmpty
                          ? 'Register new student face profiles under your account using the Register tab.'
                          : 'Try adjusting your search keyword or filter toggle.',
                      style: TextStyle(color: isDark ? Colors.white60 : Colors.grey[600], fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: filteredList.length,
                separatorBuilder: (ctx, idx) => const SizedBox(height: 12),
                itemBuilder: (ctx, idx) {
                  final student = filteredList[idx];
                  return _buildStudentCard(student, isDark);
                },
              ),
          ],
        ),
      ),
    );
  },
);
}

  Widget _buildStudentCard(Map<String, dynamic> student, bool isDark) {
    final regNo = (student['reg_no'] ?? '').toString();
    final name = (student['name'] ?? '').toString();
    final dept = (student['dept'] ?? '').toString();
    final registeredBy = (student['registered_by'] ?? '').toString();
    final createdAt = (student['created_at'] ?? '').toString();
    final isMyRegistration = registeredBy.isNotEmpty && registeredBy == (widget.user['reg_no'] ?? '').toString();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showStudentAttendanceHistory(student),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade200),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04), blurRadius: 8, offset: const Offset(0, 2))
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Avatar Circle with Initials
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: const Color(0xFF6366F1).withValues(alpha: 0.15),
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : 'S',
                      style: const TextStyle(color: Color(0xFF6366F1), fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          dept.isNotEmpty ? dept : 'Registered Student',
                          style: TextStyle(color: isDark ? Colors.white70 : Colors.grey[700], fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                  // Face Registered Pill Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.circle, size: 7, color: Color(0xFF10B981)),
                        SizedBox(width: 5),
                        Text('512-D Active', style: TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 11)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(height: 1, color: Colors.black12),
              const SizedBox(height: 10),

              // Details Metadata & View History Indicator
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (registeredBy.isNotEmpty)
                    Expanded(
                      child: Row(
                        children: [
                          Icon(Icons.person_pin_rounded, size: 14, color: isMyRegistration ? const Color(0xFF6366F1) : Colors.grey),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              isMyRegistration ? 'Registered by You' : 'By: $registeredBy',
                              style: TextStyle(
                                color: isMyRegistration ? const Color(0xFF6366F1) : (isDark ? Colors.white60 : Colors.grey[600]),
                                fontSize: 11,
                                fontWeight: isMyRegistration ? FontWeight.bold : FontWeight.normal,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.history_rounded, size: 13, color: Color(0xFF6366F1)),
                      const SizedBox(width: 3),
                      const Text(
                        'View History',
                        style: TextStyle(color: Color(0xFF6366F1), fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                      if (createdAt.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Text(
                          createdAt.length > 10 ? createdAt.substring(0, 10) : createdAt,
                          style: TextStyle(color: isDark ? Colors.white54 : Colors.grey[500], fontSize: 11),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Action Buttons: Re-Register, Verify Attendance, Delete
              Row(
                children: [
                  // Re-Register Button
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _reRegisterStudent(student),
                      icon: const Icon(Icons.camera_alt_rounded, size: 15, color: Color(0xFF6366F1)),
                      label: const Text('Re-Register', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF6366F1))),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        side: const BorderSide(color: Color(0xFF6366F1)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Verify Attendance Button
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        setState(() {
                          _mode = _KioskMode.markAttendance;
                        });
                        _initScanCamera();
                      },
                      icon: const Icon(Icons.bolt_rounded, size: 16, color: Colors.white),
                      label: const Text('Verify', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        backgroundColor: const Color(0xFF10B981),
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Clear Attendance Button
                  IconButton(
                    onPressed: () => _clearStudentAttendance(regNo, name),
                    icon: Icon(Icons.cleaning_services_rounded, color: Colors.amber.shade800, size: 20),
                    tooltip: 'Clear Attendance Record Only',
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.amber.withValues(alpha: 0.12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(width: 6),

                  // Delete Entire Data Button
                  IconButton(
                    onPressed: () => _deleteStudentProfile(regNo, name),
                    icon: const Icon(Icons.delete_forever_rounded, color: Colors.redAccent, size: 20),
                    tooltip: 'Delete Entire Student Data',
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.red.withValues(alpha: 0.1),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: ctrl,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20, color: const Color(0xFF3949AB)),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF3949AB), width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    );
  }
}

/// Blueprint grid background painter for high-tech AI aesthetic
class _KioskGridBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = const Color(0xFF111319);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 1.0;

    const double gridSpacing = 36.0;
    for (double x = 0; x < size.width; x += gridSpacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);
    }
    for (double y = 0; y < size.height; y += gridSpacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Custom painter for futuristic scanning HUD with 4 corner brackets & oval mask
class _KioskFaceScannerMaskPainter extends CustomPainter {
  final double scanProgress;
  final bool faceDetected;
  final double faceQuality;

  _KioskFaceScannerMaskPainter({
    required this.scanProgress,
    required this.faceDetected,
    required this.faceQuality,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final maskPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.50)
      ..style = PaintingStyle.fill;

    // Full Face Oval dimensions
    final ovalWidth = math.min(size.width * 0.42, math.min(size.height * 0.48, 240.0));
    final ovalHeight = ovalWidth * 1.35;
    final center = Offset(size.width / 2, size.height / 2 - 10);
    final rect = Rect.fromCenter(center: center, width: ovalWidth, height: ovalHeight);

    final backgroundPath = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final cutoutPath = Path()..addOval(rect);
    final maskPath = Path.combine(PathOperation.difference, backgroundPath, cutoutPath);
    canvas.drawPath(maskPath, maskPaint);

    final Color ringColor = faceDetected ? const Color(0xFF10B981) : const Color(0xFF6366F1);

    // Glowing face oval stroke
    final borderPaint = Paint()
      ..color = ringColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawOval(rect, borderPaint);

    // 4 Corner Brackets [ ] surrounding face frame
    final bracketPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.95)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    const double bracketLen = 28.0;
    final bracketRect = rect.inflate(20);

    // Top-Left Corner Bracket
    canvas.drawLine(Offset(bracketRect.left, bracketRect.top + bracketLen), Offset(bracketRect.left, bracketRect.top), bracketPaint);
    canvas.drawLine(Offset(bracketRect.left, bracketRect.top), Offset(bracketRect.left + bracketLen, bracketRect.top), bracketPaint);

    // Top-Right Corner Bracket
    canvas.drawLine(Offset(bracketRect.right - bracketLen, bracketRect.top), Offset(bracketRect.right, bracketRect.top), bracketPaint);
    canvas.drawLine(Offset(bracketRect.right, bracketRect.top), Offset(bracketRect.right, bracketRect.top + bracketLen), bracketPaint);

    // Bottom-Left Corner Bracket
    canvas.drawLine(Offset(bracketRect.left, bracketRect.bottom - bracketLen), Offset(bracketRect.left, bracketRect.bottom), bracketPaint);
    canvas.drawLine(Offset(bracketRect.left, bracketRect.bottom), Offset(bracketRect.left + bracketLen, bracketRect.bottom), bracketPaint);

    // Bottom-Right Corner Bracket
    canvas.drawLine(Offset(bracketRect.right - bracketLen, bracketRect.bottom), Offset(bracketRect.right, bracketRect.bottom), bracketPaint);
    canvas.drawLine(Offset(bracketRect.right, bracketRect.bottom - bracketLen), Offset(bracketRect.right, bracketRect.bottom), bracketPaint);

    // Animated Laser Scan Line inside face oval
    if (faceDetected) {
      final double laserY = rect.top + (rect.height * scanProgress);
      final double distFromCenterY = (laserY - center.dy).abs();
      final double ratioY = distFromCenterY / (ovalHeight / 2);
      if (ratioY < 1.0) {
        final double factorX = math.sqrt(1.0 - ratioY * ratioY);
        final double boundX = (ovalWidth / 2) * factorX;
        final double actualX1 = center.dx - (boundX * 0.88);
        final double actualX2 = center.dx + (boundX * 0.88);

        final laserPaint = Paint()
          ..shader = LinearGradient(
            colors: [
              ringColor.withValues(alpha: 0.0),
              ringColor.withValues(alpha: 0.9),
              ringColor.withValues(alpha: 0.0),
            ],
          ).createShader(Rect.fromLTRB(actualX1, laserY - 2, actualX2, laserY + 2))
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.5;

        canvas.drawLine(Offset(actualX1, laserY), Offset(actualX2, laserY), laserPaint);

        final glowPaint = Paint()
          ..color = ringColor.withValues(alpha: 0.15)
          ..style = PaintingStyle.fill;
        canvas.drawOval(
          Rect.fromCenter(center: Offset(center.dx, laserY), width: (actualX2 - actualX1), height: 16),
          glowPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _KioskFaceScannerMaskPainter oldDelegate) {
    return oldDelegate.scanProgress != scanProgress ||
        oldDelegate.faceDetected != faceDetected ||
        oldDelegate.faceQuality != faceQuality;
  }
}

class _KioskDirectionalArrowPainter extends CustomPainter {
  final bool isLeft;
  final bool isRight;

  _KioskDirectionalArrowPainter({
    required this.isLeft,
    required this.isRight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (!isLeft && !isRight) return;

    final paint = Paint()
      ..color = const Color(0xFF10B981)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) * 0.38;

    if (isLeft) {
      final path = Path();
      path.addArc(
        Rect.fromCircle(center: center, radius: radius),
        math.pi * 0.9,
        math.pi * 0.45,
      );
      canvas.drawPath(path, paint);

      final arrowHead = Path();
      final endX = center.dx - radius * math.cos(math.pi * 0.35);
      final endY = center.dy + radius * math.sin(math.pi * 0.35);
      arrowHead.moveTo(endX - 10, endY - 6);
      arrowHead.lineTo(endX, endY);
      arrowHead.lineTo(endX - 4, endY - 12);
      canvas.drawPath(arrowHead, paint..style = PaintingStyle.fill);
    } else if (isRight) {
      final path = Path();
      path.addArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi * 0.35,
        math.pi * 0.45,
      );
      canvas.drawPath(path, paint);

      final arrowHead = Path();
      final endX = center.dx + radius * math.cos(math.pi * 0.1);
      final endY = center.dy + radius * math.sin(math.pi * 0.1);
      arrowHead.moveTo(endX + 10, endY - 6);
      arrowHead.lineTo(endX, endY);
      arrowHead.lineTo(endX + 4, endY - 12);
      canvas.drawPath(arrowHead, paint..style = PaintingStyle.fill);
    }
  }

  @override
  bool shouldRepaint(covariant _KioskDirectionalArrowPainter oldDelegate) {
    return oldDelegate.isLeft != isLeft || oldDelegate.isRight != isRight;
  }
}

