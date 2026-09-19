import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:math' as math;
import '../services/face_verification_service.dart';
import '../services/leave_balance_notifier.dart';
import '../utils/face_recognition_helper.dart';

/// Secure face verification widget with real-time feedback
class SecureFaceVerificationWidget extends StatefulWidget {
  final String regNo;
  final String userName;
  final VoidCallback onVerificationSuccess;
  final VoidCallback onVerificationFailed;
  final Function(String) onError;
  final bool isSettingsAuth;
  final String? token;

  const SecureFaceVerificationWidget({
    super.key,
    required this.regNo,
    required this.userName,
    required this.onVerificationSuccess,
    required this.onVerificationFailed,
    required this.onError,
    this.isSettingsAuth = false,
    this.token,
  });

  @override
  State<SecureFaceVerificationWidget> createState() =>
      _SecureFaceVerificationWidgetState();
}

class _SecureFaceVerificationWidgetState
    extends State<SecureFaceVerificationWidget> with SingleTickerProviderStateMixin {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _isInitialized = false;
  bool _isProcessing = false;
  bool _faceDetected = false;
  double _faceQuality = 0.0;
  int _failedAttempts = 0;
  bool _isLockedOut = false;
  int? _remainingSeconds;
  String _statusMessage = "Initializing camera...";
  String _feedbackMessage = "";
  late AnimationController _animationController;
  bool _showTapToVerifyPrompt = false;
  String _lastErrorMessage = "";

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _initializeCamera();
  }

  @override
  void dispose() {
    _controller?.dispose();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        _updateStatus("No cameras found", isError: true);
        return;
      }

      // Use front camera
      final frontCamera = _cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras.first,
      );

      _controller = CameraController(
        frontCamera,
        kIsWeb ? ResolutionPreset.medium : ResolutionPreset.high,
        imageFormatGroup: ImageFormatGroup.jpeg,
        enableAudio: false,
      );

      await _controller!.initialize();

      if (mounted) {
        setState(() {
          _isInitialized = true;
          _statusMessage = "Ready to verify. Look at the camera.";
        });
        _startFaceDetection();
      }
    } catch (e) {
      _updateStatus("Camera initialization failed: $e", isError: true);
    }
  }

  void _startFaceDetection() {
    if (_controller == null || !_controller!.value.isInitialized) return;

    _controller!.startImageStream((cameraImage) async {
      if (_isProcessing || _isLockedOut) return;

      // Process every 10th frame to reduce load
      // In production, you'd use actual face detection here
      // For now, we simulate face detection status
      if (mounted) {
        setState(() {
          _faceDetected = true;
          _faceQuality = 0.7 + (0.3 * DateTime.now().millisecond % 100 / 100);
          _feedbackMessage = "Face detected. Hold steady...";
        });
      }
    });
  }

  void _updateStatus(String message, {bool isError = false}) {
    if (mounted) {
      setState(() {
        _statusMessage = message;
        _feedbackMessage = isError ? "" : _feedbackMessage;
      });
    }
  }

  Future<void> _captureAndVerify() async {
    if (_isProcessing || !_isInitialized || _controller == null) return;

    setState(() {
      _isProcessing = true;
      _statusMessage = "Verifying your identity...";
      _feedbackMessage = "Please wait while we verify your face.";
    });

    try {
      // Capture the best frame
      final XFile? capturedImage = await FaceRecognitionHelper.captureBestFrame(
        _controller!,
        maxFrames: 3,
      );

      if (capturedImage == null) {
        _handleVerificationError(
          "Could not capture a clear image. Please try again.",
        );
        return;
      }

      // Verify face and mark attendance
      final Map<String, dynamic> result;
      if (widget.isSettingsAuth && widget.token != null) {
        result = await FaceVerificationService.verifyAdminExclusive(
          image: capturedImage,
          token: widget.token!,
          onError: (error) {
            if (mounted) {
              setState(() {
                _feedbackMessage = error;
              });
            }
          },
        );
      } else {
        result = await FaceVerificationService.verifyAndMarkAttendance(
          regNo: widget.regNo,
          imageFile: capturedImage,
          onError: (error) {
            if (mounted) {
              setState(() {
                _feedbackMessage = error;
              });
            }
          },
        );
      }

      if (mounted) {
        if (result['success'] == true) {
          _handleVerificationSuccess(result);
        } else {
          _handleVerificationFailure(result);
        }
      }
    } catch (e) {
      _handleVerificationError("Verification failed: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  void _handleVerificationSuccess(Map<String, dynamic>? result) {
    _failedAttempts = 0;
    widget.onVerificationSuccess();
    LeaveBalanceNotifier.instance.notifyBalanceChanged();
    _updateStatus("✓ Verification successful!", isError: false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 48),
            const SizedBox(height: 8),
            Text((result != null ? result['message'] : null) ??
                (widget.isSettingsAuth
                    ? 'Identity verified successfully'
                    : 'Attendance marked successfully')),
            if (result != null && result['data']?['confidence'] != null)
              Text(
                'Confidence: ${(result['data']['confidence'] * 100).toStringAsFixed(1)}%',
                style: const TextStyle(fontSize: 12),
              ),
          ],
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _handleVerificationFailure(Map<String, dynamic> result) {
    _failedAttempts = result['failed_attempts'] ?? _failedAttempts + 1;
    _isLockedOut = result['locked_out'] ?? false;
    _remainingSeconds = result['remaining_seconds'];

    widget.onVerificationFailed();

    if (_isLockedOut) {
      _updateStatus("⚠ Account locked", isError: true);
    } else {
      _updateStatus("✗ Verification failed", isError: true);
    }

    final errorMessage = result['error'] ?? 'Face verification failed';
    widget.onError(errorMessage);

    // Show detailed error dialog or inline prompt
    if (mounted) {
      if (result['geo_blocked'] == true) {
        _showGeofenceWarningDialog(errorMessage);
      } else if (_isLockedOut) {
        _showErrorDialog(errorMessage, result);
      } else {
        setState(() {
          _showTapToVerifyPrompt = true;
          _lastErrorMessage = errorMessage;
        });
      }
    }
  }

  void _handleVerificationError(String error) {
    setState(() {
      _isProcessing = false;
      _statusMessage = "Error: $error";
      if (!_isLockedOut) {
        _showTapToVerifyPrompt = true;
        _lastErrorMessage = error;
      }
    });
    widget.onError(error);
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
                      "Please ensure you are within the designated college campus boundaries.",
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
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                _updateStatus("Ready to verify. Please move inside geofence.");
              });
            },
            child: const Text("OK", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showErrorDialog(String error, Map<String, dynamic> result) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Verification Failed"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              color: Colors.orange,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(error),
            if (_isLockedOut && _remainingSeconds != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  "Account locked for ${(_remainingSeconds! / 60).ceil()} minutes",
                  style: const TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              if (!_isLockedOut) {
                _updateStatus("Ready to verify. Try again.");
              }
            },
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  Widget _buildSafeCameraPreview(CameraController ctrl) {
    final size = ctrl.value.previewSize;
    if (size == null) {
      return SizedBox.expand(child: CameraPreview(ctrl));
    }
    final double previewW = kIsWeb ? size.width : (size.height < size.width ? size.height : size.width);
    final double previewH = kIsWeb ? size.height : (size.height < size.width ? size.width : size.height);

    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: previewW,
          height: previewH,
          child: CameraPreview(ctrl),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final cardBg = isDark ? const Color(0xFF1E1E24) : Colors.white;
    
    return Column(
      children: [
        // Camera preview viewport
        Expanded(
          child: Stack(
            children: [
              // Camera preview
              if (_isInitialized && _controller != null)
                _buildSafeCameraPreview(_controller!)
              else
                Container(
                  color: Colors.black,
                  child: const Center(
                    child: CircularProgressIndicator(color: Colors.deepPurpleAccent),
                  ),
                ),

              // Animated Scanning Mask HUD
              if (_isInitialized)
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _animationController,
                    builder: (context, child) {
                      return CustomPaint(
                        painter: FaceScannerMaskPainter(
                          scanProgress: _animationController.value,
                          faceDetected: _faceDetected,
                          faceQuality: _faceQuality,
                        ),
                      );
                    },
                  ),
                ),

              // Processing overlay
              if (_isProcessing)
                Container(
                  color: Colors.black.withValues(alpha: 0.72),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                      decoration: BoxDecoration(
                        color: cardBg.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(color: Colors.deepPurpleAccent),
                          const SizedBox(height: 16),
                          Text(
                            "Verifying...",
                            style: TextStyle(
                              color: textColor,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // Tap again to verify dialog/prompt in the cam scanner itself
              if (_showTapToVerifyPrompt && !_isProcessing)
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.65),
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: cardBg.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3), width: 1.5),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 15,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.redAccent.withValues(alpha: 0.12),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.face_retouching_off_rounded,
                                color: Colors.redAccent,
                                size: 36,
                              ),
                            ),
                            const SizedBox(height: 14),
                            const Text(
                              "Verification Failed",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.redAccent,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _lastErrorMessage.isNotEmpty ? _lastErrorMessage : "Face not recognized. Please align your face properly.",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                color: textColor.withValues(alpha: 0.8),
                              ),
                            ),
                            const SizedBox(height: 20),
                            SizedBox(
                              width: double.infinity,
                              height: 44,
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  setState(() {
                                    _showTapToVerifyPrompt = false;
                                  });
                                  _captureAndVerify();
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.deepPurpleAccent,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                icon: const Icon(Icons.refresh_rounded, size: 18),
                                label: const Text(
                                  "Tap to Verify Again",
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: () {
                                setState(() {
                                  _showTapToVerifyPrompt = false;
                                  _updateStatus("Ready to verify. Look at the camera.");
                                });
                              },
                              child: Text(
                                "Cancel",
                                style: TextStyle(
                                  color: textColor.withValues(alpha: 0.6),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),

        // Modern Glassmorphic Status and controls panel
        Container(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F0F12) : Colors.grey.shade50,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 15,
                offset: const Offset(0, -5),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // User identity info
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E1E22) : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark ? Colors.white10 : Colors.grey.shade200,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.deepPurpleAccent.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.person_rounded,
                        color: Colors.deepPurpleAccent,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.userName,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: textColor,
                            ),
                          ),
                          Text(
                            "Reg No: ${widget.regNo}",
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white60 : Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_failedAttempts > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          "$_failedAttempts/3 attempts",
                          style: const TextStyle(
                            color: Colors.orange,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    if (_isLockedOut)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                        ),
                        child: const Text(
                          "LOCKED",
                          style: TextStyle(
                            color: Colors.redAccent,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Status description message
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _statusMessage.contains("Error") || _statusMessage.contains("✗")
                        ? Icons.error_outline_rounded
                        : _statusMessage.contains("✓")
                            ? Icons.check_circle_outline_rounded
                            : Icons.info_outline_rounded,
                    size: 16,
                    color: _statusMessage.contains("Error") || _statusMessage.contains("✗")
                        ? Colors.redAccent
                        : _statusMessage.contains("✓")
                            ? Colors.green
                            : Colors.deepPurpleAccent,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      _statusMessage,
                      style: TextStyle(
                        color: _statusMessage.contains("Error") || _statusMessage.contains("✗")
                            ? Colors.redAccent
                            : _statusMessage.contains("✓")
                                ? Colors.green
                                : (isDark ? Colors.white70 : Colors.grey.shade800),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),

              if (_feedbackMessage.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _feedbackMessage,
                    style: TextStyle(
                      color: isDark ? Colors.white38 : Colors.grey.shade500,
                      fontSize: 11,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),

              const SizedBox(height: 20),

              // Premium verify button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: _isLockedOut || !_isInitialized
                        ? null
                        : const LinearGradient(
                            colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                          ),
                    boxShadow: _isLockedOut || !_isInitialized
                        ? null
                        : [
                            BoxShadow(
                              color: const Color(0xFF6366F1).withValues(alpha: 0.35),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                  ),
                  child: ElevatedButton(
                    onPressed: _isProcessing || _isLockedOut || !_isInitialized
                        ? null
                        : _captureAndVerify,
                    style: ElevatedButton.styleFrom(
                      elevation: 0,
                      backgroundColor: Colors.transparent,
                      foregroundColor: Colors.white,
                      shadowColor: Colors.transparent,
                      disabledBackgroundColor: isDark ? Colors.white10 : Colors.grey.shade300,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      _isLockedOut
                          ? "Account Temporarily Locked"
                          : _isProcessing
                              ? "Processing Verification..."
                              : widget.isSettingsAuth
                                  ? "Verify Admin Identity"
                                  : "Verify Face & Mark Attendance",
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Custom painter for futuristic scanning HUD with oval mask
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
    final maskPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.70)
      ..style = PaintingStyle.fill;

    // Dimensions of the viewport scanning oval (responsive to both width and height)
    final ovalWidth = math.min(size.width * 0.65, size.height * 0.5);
    final ovalHeight = ovalWidth * 1.3;
    final center = Offset(size.width / 2, size.height / 2);
    final rect = Rect.fromCenter(center: center, width: ovalWidth, height: ovalHeight);

    // Screen backdrop mask
    final backgroundPath = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final cutoutPath = Path()..addOval(rect);
    final maskPath = Path.combine(PathOperation.difference, backgroundPath, cutoutPath);
    canvas.drawPath(maskPath, maskPaint);

    // Dynamic scanning ring colors
    final Color ringColor = faceDetected
        ? (faceQuality > 0.75 ? const Color(0xFF10B981) : const Color(0xFFF59E0B))
        : const Color(0xFF6366F1); // Green, Orange, Indigo

    // Draw scanning border ring
    final borderPaint = Paint()
      ..color = ringColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;
    canvas.drawOval(rect, borderPaint);

    // Draw futuristic corner brackets around the scanner
    final cornerPaint = Paint()
      ..color = ringColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.0
      ..strokeCap = StrokeCap.round;

    // Top-Left corner bracket
    canvas.drawArc(Rect.fromLTWH(rect.left - 10, rect.top - 10, 40, 40), 3.14, 1.57, false, cornerPaint);
    // Top-Right corner bracket
    canvas.drawArc(Rect.fromLTWH(rect.right - 30, rect.top - 10, 40, 40), 4.71, 1.57, false, cornerPaint);
    // Bottom-Left corner bracket
    canvas.drawArc(Rect.fromLTWH(rect.left - 10, rect.bottom - 30, 40, 40), 1.57, 1.57, false, cornerPaint);
    // Bottom-Right corner bracket
    canvas.drawArc(Rect.fromLTWH(rect.right - 30, rect.bottom - 30, 40, 40), 0.0, 1.57, false, cornerPaint);

    // Draw active scanning line moving down the oval viewport
    if (faceDetected) {
      final double laserY = rect.top + (rect.height * scanProgress);

      // Verify that coordinates lie within the oval curve bound width
      final double distFromCenterY = (laserY - center.dy).abs();
      final double ratioY = distFromCenterY / (ovalHeight / 2);
      // Bound width dynamically at height Y using ellipse formula: (x/a)^2 + (y/b)^2 = 1
      if (ratioY < 1.0) {
        final double factorX = math.sqrt(1.0 - ratioY * ratioY);
        final double boundX = (ovalWidth / 2) * factorX;
        final double actualX1 = center.dx - (boundX * 0.85);
        final double actualX2 = center.dx + (boundX * 0.85);

        final laserPaint = Paint()
          ..shader = LinearGradient(
            colors: [
              ringColor.withValues(alpha: 0.0),
              ringColor.withValues(alpha: 0.85),
              ringColor.withValues(alpha: 0.0),
            ],
          ).createShader(Rect.fromLTRB(actualX1, laserY - 2, actualX2, laserY + 2))
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.5;

        canvas.drawLine(Offset(actualX1, laserY), Offset(actualX2, laserY), laserPaint);

        // Scan reflection glow
        final glowPaint = Paint()
          ..color = ringColor.withValues(alpha: 0.12)
          ..style = PaintingStyle.fill;
        canvas.drawOval(
          Rect.fromCenter(center: Offset(center.dx, laserY), width: (actualX2 - actualX1), height: 16),
          glowPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant FaceScannerMaskPainter oldDelegate) {
    return oldDelegate.scanProgress != scanProgress ||
        oldDelegate.faceDetected != faceDetected ||
        oldDelegate.faceQuality != faceQuality;
  }
}

/// Confirmation dialog for attendance
Future<bool> showAttendanceConfirmationDialog(
  BuildContext context, {
  required String userName,
  required String confidence,
}) async {
  return await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Confirm Attendance"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 48),
              const SizedBox(height: 16),
              Text("Mark attendance for $userName?"),
              const SizedBox(height: 8),
              Text(
                "Confidence: $confidence",
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("Confirm"),
            ),
          ],
        ),
      ) ??
      false;
}
