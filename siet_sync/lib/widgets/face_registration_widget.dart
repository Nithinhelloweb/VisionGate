import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import '../config/college_ip_config.dart';
import '../utils/wifi_check.dart';
import '../utils/geofence_check.dart';
import '../utils/vpn_check.dart';
import '../services/pre_verification_service.dart';
import '../services/client_face_prefilter.dart';

String get API_URL => CollegeIPConfig.defaultURL;

class FaceRegistrationWidget extends StatefulWidget {
  final String token;
  final String role;
  final String? initialRegNo;
  final String? initialName;
  final String? initialDept;
  final String registerEndpoint;
  final VoidCallback? onSuccess;
  final VoidCallback? onCancel;

  const FaceRegistrationWidget({
    super.key,
    required this.token,
    required this.role,
    this.initialRegNo,
    this.initialName,
    this.initialDept,
    required this.registerEndpoint,
    this.onSuccess,
    this.onCancel,
  });

  @override
  State<FaceRegistrationWidget> createState() => _FaceRegistrationWidgetState();
}

class _FaceRegistrationWidgetState extends State<FaceRegistrationWidget> with SingleTickerProviderStateMixin {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isInitialized = false;
  bool _isCapturing = false;
  String _statusMessage = "Position your face in the frame";
  XFile? _capturedImage;
  bool _hasFace = false;

  bool _isRegistering = false;
  bool _isRegistrationSuccess = false;
  bool _isRegistrationError = false;
  String _registrationErrorMessage = '';

  final regNoCtrl = TextEditingController();
  final nameCtrl = TextEditingController();
  final deptCtrl = TextEditingController();
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    regNoCtrl.text = widget.initialRegNo ?? '';
    nameCtrl.text = widget.initialName ?? '';
    deptCtrl.text = widget.initialDept ?? '';
    _initCamera();
  }

  @override
  void dispose() {
    _controller?.dispose();
    _animationController.dispose();
    regNoCtrl.dispose();
    nameCtrl.dispose();
    deptCtrl.dispose();
    super.dispose();
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        setState(() => _statusMessage = "No camera found on this device");
        return;
      }
      final camera = _cameras!.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras!.first,
      );
      _controller = CameraController(
        camera,
        kIsWeb ? ResolutionPreset.medium : ResolutionPreset.high,
        enableAudio: false,
      );
      await _controller!.initialize();
      if (mounted) {
        setState(() => _isInitialized = true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _statusMessage = "Camera error: $e");
      }
    }
  }

  Future<void> _captureFrame() async {
    if (_isCapturing || !_isInitialized || _controller == null) return;

    setState(() => _isCapturing = true);
    _statusMessage = "Capturing face...";

    try {
      final XFile imageFile = await _controller!.takePicture();
      
      // On-device Google ML Kit pre-filter
      final prefilter = await ClientFacePreFilterService.evaluateImagePath(
        imageFile.path,
        targetPose: FaceTargetPose.front,
        allowMultipleFaces: false,
      );

      if (!prefilter.isValid) {
        if (mounted) {
          setState(() {
            _hasFace = false;
            _statusMessage = prefilter.message ?? "Face not detected clearly. Position your face in center.";
          });
        }
        return;
      }

      if (mounted) {
        setState(() {
          _capturedImage = imageFile;
          _hasFace = true;
          _statusMessage = "Face captured! Tap Register to complete.";
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = "Capture failed: $e";
        });
      }
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  void _retakePhoto() {
    setState(() {
      _capturedImage = null;
      _hasFace = false;
      _isRegistrationError = false;
      _isRegistrationSuccess = false;
      _registrationErrorMessage = '';
      _statusMessage = "Position your face in the frame";
    });
  }

  Future<void> _registerFace() async {
    if (_capturedImage == null) {
      setState(() => _statusMessage = "Please capture your face first");
      return;
    }

    if (nameCtrl.text.trim().isEmpty) {
      setState(() => _statusMessage = "Please fill in your name");
      return;
    }

    setState(() {
      _isRegistering = true;
      _isRegistrationSuccess = false;
      _isRegistrationError = false;
      _registrationErrorMessage = '';
      _statusMessage = "Checking VPN status...";
    });

    try {
      // Check VPN connection only for face registration
      final isVpn = await VpnChecker.isVpnActive();
      if (isVpn) {
        setState(() {
          _isRegistering = false;
          _isRegistrationError = true;
          _registrationErrorMessage = "VPN/Proxy detected. Please disconnect VPN to register your face.";
          _statusMessage = _registrationErrorMessage;
        });
        return;
      }

      setState(() {
        _statusMessage = "Registering face biometrics...";
      });

      var request = http.MultipartRequest(
        "POST",
        Uri.parse("$API_URL${widget.registerEndpoint}"),
      );

      final clientPlatform = kIsWeb ? 'web' : 'app';
      request.headers['Authorization'] = 'Bearer ${widget.token}';
      request.headers['X-Client-Platform'] = clientPlatform;
      request.fields['name'] = nameCtrl.text.trim();
      request.fields['reg_no'] = regNoCtrl.text.trim();
      request.fields['dept'] = deptCtrl.text.trim();
      request.fields['role'] = widget.role;
      final bytes = await _capturedImage!.readAsBytes();
      request.files.add(
        http.MultipartFile.fromBytes(
          "image",
          bytes,
          filename: "face_capture.jpg",
        ),
      );

      var response = await request.send();
      var body = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        final json = jsonDecode(body);
        setState(() {
          _isRegistering = false;
          _isRegistrationSuccess = true;
          _statusMessage = (json is Map ? json['message'] : null) ?? 'Registration successful';
        });
        widget.onSuccess?.call();
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) Navigator.pop(context);
      } else {
        final errorJson = jsonDecode(body);
        setState(() {
          _isRegistering = false;
          _isRegistrationError = true;
          _registrationErrorMessage =
              (errorJson is Map ? (errorJson['detail'] ?? errorJson['message'] ?? errorJson['error']) : null)?.toString() ?? 'Registration failed';
          _statusMessage = _registrationErrorMessage;
        });
      }
    } catch (e) {
      setState(() {
        _isRegistering = false;
        _isRegistrationError = true;
        _registrationErrorMessage = "Error: $e";
        _statusMessage = _registrationErrorMessage;
      });
    }
  }

  void _retryRegistration() {
    setState(() {
      _isRegistrationError = false;
      _registrationErrorMessage = '';
    });
    _registerFace();
  }

  Widget _buildSafeCameraPreview(CameraController ctrl) {
    final size = ctrl.value.previewSize;
    if (size == null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: CameraPreview(ctrl),
      );
    }
    final double previewW = kIsWeb ? size.width : (size.height < size.width ? size.height : size.width);
    final double previewH = kIsWeb ? size.height : (size.height < size.width ? size.width : size.height);

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: previewW,
            height: previewH,
            child: CameraPreview(ctrl),
          ),
        ),
      ),
    );
  }

  Widget _buildCameraViewfinderCard({required bool isDark, required double height}) {
    final Color borderColor = _isRegistrationSuccess
        ? const Color(0xFF10B981)
        : (_isRegistrationError
            ? const Color(0xFFEF4444)
            : (_hasFace
                ? const Color(0xFF10B981)
                : (_isRegistering
                    ? Colors.amber
                    : const Color(0xFF2563EB))));

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.black87,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: borderColor,
          width: 2.5,
        ),
        boxShadow: [
          BoxShadow(
            color: borderColor.withValues(alpha: 0.15),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          fit: StackFit.expand,
          alignment: Alignment.center,
          children: [
            if (_isInitialized && _controller != null && _controller!.value.isInitialized) ...[
              if (_hasFace && _capturedImage != null)
                FutureBuilder<Uint8List>(
                  future: _capturedImage!.readAsBytes(),
                  builder: (context, snapshot) {
                    if (snapshot.hasData) {
                      return Image.memory(snapshot.data!, fit: BoxFit.cover);
                    }
                    return const Center(child: CircularProgressIndicator(color: Color(0xFF2563EB)));
                  },
                )
              else
                _buildSafeCameraPreview(_controller!),

              // Clean Biometric Viewfinder Painter (Zero Text)
              CustomPaint(
                painter: FaceScannerMaskPainter(
                  scanProgress: _animationController.value,
                  faceDetected: _hasFace,
                  faceQuality: _isRegistrationSuccess ? 1.0 : (_hasFace ? 0.95 : 0.0),
                ),
              ),
            ] else
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: Color(0xFF2563EB)),
                    const SizedBox(height: 16),
                    Text(
                      "Starting camera...",
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13),
                    ),
                  ],
                ),
              ),

            // Top-right control: Retake photo when captured
            if (_isInitialized && _hasFace)
              Positioned(
                top: 12,
                right: 12,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.refresh_rounded, color: Colors.white, size: 18),
                    tooltip: "Retake Photo",
                    onPressed: _retakePhoto,
                  ),
                ),
              ),

            // Processing Loading Indicator in center
            if (_isCapturing || _isRegistering)
              Container(
                color: Colors.black.withValues(alpha: 0.4),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(
                        strokeWidth: 3,
                        color: _isRegistering ? const Color(0xFF10B981) : const Color(0xFF2563EB),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _isRegistering ? "Registering Biometrics..." : "Capturing...",
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),

            // Success Confirmation Overlay
            if (_isRegistrationSuccess)
              Container(
                color: const Color(0xFF10B981).withValues(alpha: 0.25),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: const BoxDecoration(
                      color: Color(0xFF10B981),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check_rounded, color: Colors.white, size: 36),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCleanStatusChip(bool isDark) {
    final Color color = _isRegistrationSuccess
        ? const Color(0xFF10B981)
        : (_isRegistrationError
            ? const Color(0xFFEF4444)
            : (_hasFace
                ? const Color(0xFF10B981)
                : (_isRegistering
                    ? Colors.amber
                    : const Color(0xFF2563EB))));

    final IconData icon = _isRegistrationSuccess
        ? Icons.check_circle_rounded
        : (_isRegistrationError
            ? Icons.error_outline_rounded
            : (_hasFace
                ? Icons.verified_user_rounded
                : (_isRegistering
                    ? Icons.hourglass_top_rounded
                    : Icons.face_retouching_natural_rounded)));

    final message = _registrationErrorMessage.isNotEmpty
        ? _registrationErrorMessage
        : (_isRegistering
            ? "Enrolling biometric embeddings into secure database..."
            : (_isRegistrationSuccess
                ? "Face biometrics registered successfully!"
                : (_hasFace
                    ? "Face frame captured ready for enrollment"
                    : _statusMessage)));

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (_isRegistering)
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: color),
            )
          else
            Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              message,
              style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(bool isDark) {
    if (_isRegistrationError) {
      return ElevatedButton.icon(
        onPressed: _retryRegistration,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF2563EB),
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        icon: const Icon(Icons.refresh_rounded, size: 20),
        label: const Text("Retry Registration", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
      );
    }

    if (!_hasFace) {
      return ElevatedButton.icon(
        onPressed: (_isInitialized && !_isCapturing) ? _captureFrame : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF2563EB),
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 2,
        ),
        icon: _isCapturing
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.camera_alt_rounded, size: 20),
        label: const Text("Capture Face Frame", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
      );
    }

    return Row(
      children: [
        Expanded(
          flex: 4,
          child: OutlinedButton.icon(
            onPressed: (!_isRegistering && !_isRegistrationSuccess) ? _retakePhoto : null,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              side: BorderSide(color: isDark ? Colors.white38 : Colors.grey.shade400),
            ),
            icon: const Icon(Icons.restart_alt_rounded, size: 18),
            label: const Text("Retake", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 6,
          child: ElevatedButton.icon(
            onPressed: (!_isRegistering && !_isRegistrationSuccess) ? _registerFace : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 2,
            ),
            icon: _isRegistering
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.check_circle_rounded, size: 20),
            label: Text(
              _isRegistering ? "Registering..." : (_isRegistrationSuccess ? "Completed" : "Submit & Register"),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildUserInfoCard(bool isDark) {
    final roleName = widget.role.toUpperCase();
    final roleColor = widget.role.toLowerCase() == 'admin'
        ? const Color(0xFF2563EB)
        : (widget.role.toLowerCase() == 'hod' ? const Color(0xFF0D9488) : const Color(0xFF4F46E5));

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Biometric Profile Details",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: roleColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  roleName,
                  style: TextStyle(color: roleColor, fontWeight: FontWeight.bold, fontSize: 11),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: regNoCtrl,
            enabled: false,
            decoration: InputDecoration(
              labelText: "Registration / Staff ID",
              prefixIcon: const Icon(Icons.badge_outlined, size: 20),
              filled: true,
              fillColor: isDark ? const Color(0xFF0F172A) : Colors.grey.shade100,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: nameCtrl,
            decoration: InputDecoration(
              labelText: "Full Name",
              prefixIcon: const Icon(Icons.person_outline, size: 20),
              filled: true,
              fillColor: isDark ? const Color(0xFF0F172A) : Colors.grey.shade100,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: const [
              'CSE', 'IT', 'AIDS', 'AIML', 'CYBER', 'ECE', 'EEE', 'VLSI', 'MECH', 'BME', 'BT', 'FT', 'AGRI', 'CIVIL'
            ].contains(deptCtrl.text.trim().toUpperCase())
                ? deptCtrl.text.trim().toUpperCase()
                : 'CSE',
            decoration: InputDecoration(
              labelText: "Department",
              prefixIcon: const Icon(Icons.school_outlined, size: 20),
              filled: true,
              fillColor: isDark ? const Color(0xFF0F172A) : Colors.grey.shade100,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
            items: const [
              'CSE', 'IT', 'AIDS', 'AIML', 'CYBER', 'ECE', 'EEE', 'VLSI', 'MECH', 'BME', 'BT', 'FT', 'AGRI', 'CIVIL'
            ].map((d) => DropdownMenuItem<String>(value: d, child: Text(d))).toList(),
            onChanged: (val) {
              if (val != null) {
                setState(() {
                  deptCtrl.text = val;
                });
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildGuidelinesCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.shield_outlined, color: Color(0xFF2563EB), size: 18),
              SizedBox(width: 8),
              Text(
                'Enrollment Instructions',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildInfoRow(Icons.face_retouching_natural_rounded, 'Look directly into the camera in balanced lighting.', isDark),
          const SizedBox(height: 8),
          _buildInfoRow(Icons.vpn_lock_outlined, 'Ensure VPN/proxy is turned off before registration.', isDark),
          const SizedBox(height: 8),
          _buildInfoRow(Icons.verified_outlined, 'Once submitted, biometrics are securely locked & encrypted.', isDark),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text, bool isDark) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: const Color(0xFF2563EB)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.grey.shade700, height: 1.3),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isWide = MediaQuery.of(context).size.width >= 900;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          "${widget.role.toUpperCase()} Face Registration",
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFF2563EB),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (widget.onCancel != null)
            TextButton(
              onPressed: widget.onCancel,
              child: const Text("Cancel", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
      body: isWide
          ? SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left Column: Hero Viewfinder & Controls
                  Expanded(
                    flex: 5,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildCameraViewfinderCard(isDark: isDark, height: 420),
                        const SizedBox(height: 14),
                        _buildCleanStatusChip(isDark),
                        const SizedBox(height: 14),
                        _buildActionButtons(isDark),
                      ],
                    ),
                  ),
                  const SizedBox(width: 24),
                  // Right Column: Profile Form & Guidelines
                  Expanded(
                    flex: 5,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildUserInfoCard(isDark),
                        const SizedBox(height: 16),
                        _buildGuidelinesCard(isDark),
                      ],
                    ),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildCameraViewfinderCard(isDark: isDark, height: 360),
                  const SizedBox(height: 12),
                  _buildCleanStatusChip(isDark),
                  const SizedBox(height: 14),
                  _buildActionButtons(isDark),
                  const SizedBox(height: 16),
                  _buildUserInfoCard(isDark),
                  const SizedBox(height: 14),
                  _buildGuidelinesCard(isDark),
                ],
              ),
            ),
    );
  }
}

// Staff Face Registration Widget (with permission check)
class StaffFaceRegistrationWidget extends StatefulWidget {
  final String token;
  final String regNo;
  final String name;
  final String dept;

  const StaffFaceRegistrationWidget({
    super.key,
    required this.token,
    required this.regNo,
    required this.name,
    required this.dept,
  });

  @override
  State<StaffFaceRegistrationWidget> createState() =>
      _StaffFaceRegistrationWidgetState();
}

class _StaffFaceRegistrationWidgetState
    extends State<StaffFaceRegistrationWidget> {
  bool _isRegistered = false;
  bool _hasPermission = false;
  bool _isLoading = true;
  String _message = "";

  @override
  void initState() {
    super.initState();
    _checkFaceStatus();
  }

  Future<void> _checkFaceStatus() async {
    try {
      final response = await http.get(
        Uri.parse("$API_URL/face/status/${widget.regNo}"),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            _isRegistered = data['face_registered'] ?? false;
            _hasPermission = data['can_reregister'] ?? false;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _message = "Error checking status: $e";
          _isLoading = false;
        });
      }
    }
  }

  void _navigateToRegistration() {
    if (_isRegistered && !_hasPermission) {
      setState(
        () => _message = "Please contact your HOD for permission to re-register.",
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FaceRegistrationWidget(
          token: widget.token,
          role: 'staff',
          initialRegNo: widget.regNo,
          initialName: widget.name,
          initialDept: widget.dept,
          registerEndpoint: '/staff/face/register',
          onSuccess: () => _checkFaceStatus(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF2563EB)));
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: _isRegistered
              ? const Color(0xFF10B981).withValues(alpha: 0.3)
              : const Color(0xFFF59E0B).withValues(alpha: 0.3),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (_isRegistered ? const Color(0xFF10B981) : const Color(0xFFF59E0B))
                      .withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _isRegistered ? Icons.verified_user_rounded : Icons.face_retouching_natural_rounded,
                  color: _isRegistered ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Face Biometrics Status",
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _isRegistered ? "Biometrics Active & Enrolled" : "No face registered yet",
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: _isRegistered ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                      ),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: _navigateToRegistration,
                icon: Icon(_isRegistered ? Icons.refresh_rounded : Icons.camera_alt_rounded, size: 16),
                label: Text(_isRegistered ? "Re-register" : "Register"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isRegistered ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ],
          ),
          if (_message.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded, color: Color(0xFFEF4444), size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _message,
                      style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_isRegistered && _hasPermission) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF2563EB).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF2563EB).withValues(alpha: 0.25)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.check_circle_outline_rounded, color: Color(0xFF2563EB), size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "HOD Permission Granted: You are eligible to update face biometrics.",
                      style: TextStyle(color: Color(0xFF2563EB), fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// Face Verification Widget for attendance marking
class FaceVerificationWidget extends StatefulWidget {
  final String token;
  final String regNo;
  final String name;
  final String dept;
  final VoidCallback? onVerified;
  final Function(Map<String, dynamic> data)? onVerifiedData;
  final VoidCallback? onCancel;

  const FaceVerificationWidget({
    super.key,
    required this.token,
    required this.regNo,
    required this.name,
    required this.dept,
    this.onVerified,
    this.onVerifiedData,
    this.onCancel,
  });

  @override
  State<FaceVerificationWidget> createState() => _FaceVerificationWidgetState();
}

class _FaceVerificationWidgetState extends State<FaceVerificationWidget> with SingleTickerProviderStateMixin {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isInitialized = false;
  bool _isVerifying = false;
  String _statusMessage = "Position your face in the frame";
  bool _hasFace = false;
  bool _isVerified = false;
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _initCamera();
  }

  @override
  void dispose() {
    _controller?.dispose();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        setState(() => _statusMessage = "No camera found on this device");
        return;
      }
      final camera = _cameras!.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras!.first,
      );
      _controller = CameraController(
        camera,
        kIsWeb ? ResolutionPreset.medium : ResolutionPreset.high,
        enableAudio: false,
      );
      await _controller!.initialize();
      if (mounted) {
        setState(() => _isInitialized = true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _statusMessage = "Camera error: $e");
      }
    }
  }

  Future<void> _verifyFace() async {
    if (_isVerifying || !_isInitialized || _controller == null) return;

    setState(() {
      _isVerifying = true;
      _statusMessage = "Checking credentials...";
    });

    try {
      final preVerif = await PreVerificationService.instance.getOrRefresh();

      // VPN Check
      if (preVerif.vpnError != null) {
        setState(() {
          _statusMessage = "Error: ${preVerif.vpnError}";
        });
        return;
      }

      // Geofence check
      final geoDecision = preVerif.geoDecision;
      if (geoDecision != null && geoDecision.error != null) {
        setState(() {
          _statusMessage = "Error: ${geoDecision.error}";
        });
        _showGeofenceWarningDialog(geoDecision.error!);
        return;
      }

      // WiFi check
      if (!kIsWeb &&
          CollegeIPConfig.isWifiCheckEnabled &&
          !AppSettings.allowAnyNetwork &&
          preVerif.wifiError != null) {
        setState(() {
          _statusMessage = "Error: ${preVerif.wifiError}";
        });
        if (preVerif.wifiError!.contains("SSID") ||
            preVerif.wifiError!.contains("location") ||
            preVerif.wifiError!.contains("Location")) {
          _showGeofenceWarningDialog("To verify WiFi connection, please turn on Location Services (GPS) and grant permission.");
        }
        return;
      }

      final effectiveGeoDecision = geoDecision ??
          const GeoFenceDecision(
            enforced: false,
            insideOuter: null,
            insideInner: null,
            error: null,
          );

      setState(() => _statusMessage = "Verifying biometrics...");

      final XFile imageFile = await _controller!.takePicture();

      // On-device Google ML Kit edge pre-filter (fast mobile check)
      final prefilter = await ClientFacePreFilterService.evaluateImagePath(
        imageFile.path,
        targetPose: FaceTargetPose.any,
        allowMultipleFaces: false,
      );

      if (!prefilter.isValid) {
        if (mounted) {
          setState(() {
            _hasFace = false;
            _statusMessage = prefilter.message ?? "Face not detected clearly. Position your face in center.";
          });
        }
        return;
      }

      var request = http.MultipartRequest(
        "POST",
        Uri.parse("$API_URL/mark_attendance"),
      );

      request.headers['Authorization'] = 'Bearer ${widget.token}';
      request.fields['reg_no'] = widget.regNo;

      Position? position = preVerif.position ?? GeoFenceChecker.lastFetchedPosition;

      if (position == null && kIsWeb && effectiveGeoDecision.enforced) {
        try {
          position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.low,
            timeLimit: const Duration(seconds: 20),
          );
        } catch (_) {
          try {
            position = await Geolocator.getLastKnownPosition();
          } catch (_) {}
        }

        if (position == null) {
          setState(() {
            _statusMessage =
                "Error: Unable to get location. Please allow browser location access.";
          });
          return;
        }
      }

      if (effectiveGeoDecision.enforced && position == null) {
        setState(() {
          _statusMessage = "Error: Unable to verify location.";
        });
        _showGeofenceWarningDialog("Unable to verify your location. Please enable GPS and try again.");
        return;
      }

      final clientPlatform = kIsWeb ? 'web' : 'app';
      request.fields['client_platform'] = clientPlatform;
      request.headers['X-Client-Platform'] = clientPlatform;

      if (effectiveGeoDecision.enforced && position != null) {
        request.fields['client_lat'] = position.latitude.toString();
        request.fields['client_lng'] = position.longitude.toString();
      }

      final bytes = await imageFile.readAsBytes();
      request.files.add(
        http.MultipartFile.fromBytes(
          "image",
          bytes,
          filename: "face_verify.jpg",
        ),
      );

      var response = await request.send();
      var body = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        final json = jsonDecode(body);
        final resMap = json is Map<String, dynamic> ? json : <String, dynamic>{'message': json.toString()};
        final serverMsg = resMap['message']?.toString() ?? 'Attendance marked successfully!';
        setState(() {
          _hasFace = true;
          _isVerified = true;
          _statusMessage = serverMsg;
        });
        widget.onVerifiedData?.call(resMap);
        widget.onVerified?.call();
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) Navigator.pop(context);
      } else {
        String errorMsg = 'Verification failed';
        try {
          final errorJson = jsonDecode(body);
          errorMsg =
              (errorJson is Map ? (errorJson['error'] ?? errorJson['detail'] ?? errorJson['message']) : null)?.toString() ??
              'Verification failed';
        } catch (_) {
          errorMsg = response.statusCode == 500
              ? "Server error. Please try again."
              : "Verification failed";
        }
        setState(() {
          _hasFace = true;
          _statusMessage = errorMsg;
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = "Error: $e";
      });
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  void _showGeofenceWarningDialog(String error) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.gpp_bad_rounded, color: Colors.redAccent, size: 28),
            SizedBox(width: 10),
            Text(
              "Geofence Warning",
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Attendance Denied",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              style: const TextStyle(fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.orange, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "Please ensure you are physically present inside the designated college campus boundaries.",
                      style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("OK", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildSafeCameraPreview(CameraController ctrl) {
    final size = ctrl.value.previewSize;
    if (size == null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: CameraPreview(ctrl),
      );
    }
    final double previewW = kIsWeb ? size.width : (size.height < size.width ? size.height : size.width);
    final double previewH = kIsWeb ? size.height : (size.height < size.width ? size.width : size.height);

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: previewW,
            height: previewH,
            child: CameraPreview(ctrl),
          ),
        ),
      ),
    );
  }

  Widget _buildCameraViewfinderCard({required bool isDark, required double height}) {
    final Color borderColor = _isVerified
        ? const Color(0xFF10B981)
        : (_isVerifying ? const Color(0xFFF59E0B) : const Color(0xFF2563EB));

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.black87,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borderColor, width: 2.5),
        boxShadow: [
          BoxShadow(
            color: borderColor.withValues(alpha: 0.15),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          fit: StackFit.expand,
          alignment: Alignment.center,
          children: [
            if (_isInitialized && _controller != null && _controller!.value.isInitialized) ...[
              _buildSafeCameraPreview(_controller!),
              CustomPaint(
                painter: FaceScannerMaskPainter(
                  scanProgress: _animationController.value,
                  faceDetected: _hasFace,
                  faceQuality: _isVerified ? 1.0 : (_hasFace ? 0.8 : 0.0),
                ),
              ),
            ] else
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: Color(0xFF2563EB)),
                    const SizedBox(height: 16),
                    Text(
                      "Starting camera...",
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13),
                    ),
                  ],
                ),
              ),

            // Top-right Refresh button
            if (_isInitialized)
              Positioned(
                top: 12,
                right: 12,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.refresh_rounded, color: Colors.white, size: 18),
                    tooltip: "Refresh Camera",
                    onPressed: () => _initCamera(),
                  ),
                ),
              ),

            // Processing overlay
            if (_isVerifying)
              Container(
                color: Colors.black.withValues(alpha: 0.4),
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(strokeWidth: 3, color: Color(0xFF2563EB)),
                      SizedBox(height: 12),
                      Text(
                        "Verifying Face Biometrics...",
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),

            // Success Confirmation Overlay
            if (_isVerified)
              Container(
                color: const Color(0xFF10B981).withValues(alpha: 0.25),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: const BoxDecoration(
                      color: Color(0xFF10B981),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check_rounded, color: Colors.white, size: 36),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCleanStatusChip(bool isDark) {
    final Color color = _isVerified
        ? const Color(0xFF10B981)
        : (_statusMessage.toLowerCase().contains("error") || _statusMessage.toLowerCase().contains("failed")
            ? const Color(0xFFEF4444)
            : (_isVerifying ? const Color(0xFFF59E0B) : const Color(0xFF2563EB)));

    final IconData icon = _isVerified
        ? Icons.check_circle_rounded
        : (_statusMessage.toLowerCase().contains("error") || _statusMessage.toLowerCase().contains("failed")
            ? Icons.error_outline_rounded
            : (_isVerifying ? Icons.hourglass_top_rounded : Icons.face_retouching_natural_rounded));

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (_isVerifying)
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: color),
            )
          else
            Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              _statusMessage,
              style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isWide = MediaQuery.of(context).size.width >= 900;

    final userInfo = Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF2563EB).withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.person_rounded, color: Color(0xFF2563EB), size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.name,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(height: 2),
                Text(
                  "${widget.regNo} • ${widget.dept}",
                  style: TextStyle(color: isDark ? Colors.white60 : Colors.grey.shade600, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    final actionButton = ElevatedButton.icon(
      onPressed: (_isInitialized && !_isVerifying && !_isVerified) ? _verifyFace : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF2563EB),
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 2,
      ),
      icon: _isVerifying
          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : const Icon(Icons.check_circle_rounded, size: 20),
      label: Text(
        _isVerifying ? "Verifying..." : (_isVerified ? "Verified!" : "Mark Attendance"),
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text("Face Verification", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFF2563EB),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (widget.onCancel != null)
            TextButton(
              onPressed: widget.onCancel,
              child: const Text("Cancel", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
      body: isWide
          ? SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 5,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildCameraViewfinderCard(isDark: isDark, height: 420),
                        const SizedBox(height: 14),
                        _buildCleanStatusChip(isDark),
                        const SizedBox(height: 14),
                        actionButton,
                      ],
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    flex: 5,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        userInfo,
                      ],
                    ),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  userInfo,
                  const SizedBox(height: 14),
                  _buildCameraViewfinderCard(isDark: isDark, height: 360),
                  const SizedBox(height: 12),
                  _buildCleanStatusChip(isDark),
                  const SizedBox(height: 14),
                  actionButton,
                ],
              ),
            ),
    );
  }
}

/// Custom painter for sleek biometric scanning HUD with corner brackets and oval mask
class FaceScannerMaskPainter extends CustomPainter {
  final double scanProgress;
  final bool faceDetected;
  final double faceQuality;

  FaceScannerMaskPainter({
    required this.scanProgress,
    required this.faceDetected,
    required this.faceQuality,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Dimensions of the viewport scanning oval
    final ovalWidth = size.width * 0.68;
    final ovalHeight = ovalWidth * 1.25;
    final center = Offset(size.width / 2, size.height / 2);
    final rect = Rect.fromCenter(center: center, width: ovalWidth, height: ovalHeight);

    // Subtle dark backdrop outside oval
    final maskPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;
    final backgroundPath = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final cutoutPath = Path()..addOval(rect);
    final maskPath = Path.combine(PathOperation.difference, backgroundPath, cutoutPath);
    canvas.drawPath(maskPath, maskPaint);

    // Dynamic scanning ring colors
    final Color ringColor = faceDetected
        ? (faceQuality > 0.75 ? const Color(0xFF10B981) : const Color(0xFFF59E0B))
        : const Color(0xFF3B82F6);

    // Draw subtle oval guide
    final borderPaint = Paint()
      ..color = ringColor.withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;
    canvas.drawOval(rect, borderPaint);

    // Draw modern corner brackets
    final cornerPaint = Paint()
      ..color = ringColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    final bracketSize = math.min(ovalWidth * 0.16, 28.0);
    // Top-Left
    canvas.drawPath(
      Path()
        ..moveTo(rect.left, rect.top + bracketSize)
        ..lineTo(rect.left, rect.top)
        ..lineTo(rect.left + bracketSize, rect.top),
      cornerPaint,
    );
    // Top-Right
    canvas.drawPath(
      Path()
        ..moveTo(rect.right - bracketSize, rect.top)
        ..lineTo(rect.right, rect.top)
        ..lineTo(rect.right, rect.top + bracketSize),
      cornerPaint,
    );
    // Bottom-Left
    canvas.drawPath(
      Path()
        ..moveTo(rect.left, rect.bottom - bracketSize)
        ..lineTo(rect.left, rect.bottom)
        ..lineTo(rect.left + bracketSize, rect.bottom),
      cornerPaint,
    );
    // Bottom-Right
    canvas.drawPath(
      Path()
        ..moveTo(rect.right - bracketSize, rect.bottom)
        ..lineTo(rect.right, rect.bottom)
        ..lineTo(rect.right, rect.bottom - bracketSize),
      cornerPaint,
    );

    // Subtle laser beam moving across oval
    final double laserY = rect.top + (rect.height * scanProgress);
    final double distFromCenterY = (laserY - center.dy).abs();
    final double ratioY = distFromCenterY / (ovalHeight / 2);
    if (ratioY < 1.0) {
      final double factorX = math.sqrt(1.0 - ratioY * ratioY);
      final double boundX = (ovalWidth / 2) * factorX;
      final double actualX1 = center.dx - (boundX * 0.85);
      final double actualX2 = center.dx + (boundX * 0.85);

      final laserPaint = Paint()
        ..shader = LinearGradient(
          colors: [
            ringColor.withValues(alpha: 0.0),
            ringColor.withValues(alpha: 0.8),
            ringColor.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromLTRB(actualX1, laserY - 2, actualX2, laserY + 2))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5;

      canvas.drawLine(Offset(actualX1, laserY), Offset(actualX2, laserY), laserPaint);
    }
  }

  @override
  bool shouldRepaint(covariant FaceScannerMaskPainter oldDelegate) {
    return oldDelegate.scanProgress != scanProgress ||
        oldDelegate.faceDetected != faceDetected ||
        oldDelegate.faceQuality != faceQuality;
  }
}


