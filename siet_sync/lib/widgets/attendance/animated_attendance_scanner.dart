import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Hallmark-compliant Animated Attendance Scanner & Dynamic Validation Widget
/// Features:
/// - 100% Roman upright typography (font-style: normal)
/// - Locked semantic color tokens
/// - CustomPainter pulsating radar sweep animation
/// - Real-time dynamic validation badges (Timing, Geofence, Biometrics, Duplicate Check)
/// - 8-State interactive design
class AnimatedAttendanceScanner extends StatefulWidget {
  final bool isScanning;
  final bool isSuccess;
  final String? errorMessage;
  final Map<String, dynamic>? validationData;
  final VoidCallback? onScanPressed;
  final String activeSessionTitle;

  const AnimatedAttendanceScanner({
    super.key,
    required this.isScanning,
    this.isSuccess = false,
    this.errorMessage,
    this.validationData,
    this.onScanPressed,
    this.activeSessionTitle = 'Current Period',
  });

  @override
  State<AnimatedAttendanceScanner> createState() => _AnimatedAttendanceScannerState();
}

class _AnimatedAttendanceScannerState extends State<AnimatedAttendanceScanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _radarController;

  static const Color primaryBlue = Color(0xFF2563EB);
  static const Color emeraldGreen = Color(0xFF10B981);
  static const Color amberWarning = Color(0xFFF59E0B);
  static const Color roseError = Color(0xFFEF4444);

  @override
  void initState() {
    super.initState();
    _radarController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
  }

  @override
  void dispose() {
    _radarController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final checks = widget.validationData?['checks'] as Map<String, dynamic>? ?? {};

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: widget.isSuccess
              ? emeraldGreen.withValues(alpha: 0.5)
              : (widget.errorMessage != null && widget.errorMessage!.isNotEmpty
                  ? roseError.withValues(alpha: 0.5)
                  : (isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0))),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: (widget.isSuccess
                    ? emeraldGreen
                    : (isDark ? Colors.black45 : primaryBlue))
                .withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Header Section
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: (widget.isSuccess ? emeraldGreen : primaryBlue)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      widget.isSuccess
                          ? Icons.check_circle_rounded
                          : Icons.radar_rounded,
                      color: widget.isSuccess ? emeraldGreen : primaryBlue,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Live Attendance Scanner',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                        ),
                      ),
                      Text(
                        widget.activeSessionTitle,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12,
                          color: isDark ? Colors.white60 : const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: (widget.isSuccess
                          ? emeraldGreen
                          : (widget.isScanning ? amberWarning : primaryBlue))
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: widget.isSuccess
                            ? emeraldGreen
                            : (widget.isScanning ? amberWarning : primaryBlue),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      widget.isSuccess
                          ? 'VERIFIED'
                          : (widget.isScanning ? 'SCANNING' : 'READY'),
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                        color: widget.isSuccess
                            ? emeraldGreen
                            : (widget.isScanning ? amberWarning : primaryBlue),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Center Animated Visual Radar Scanner
          SizedBox(
            height: 180,
            width: 180,
            child: Stack(
              alignment: Alignment.center,
              children: [
                AnimatedBuilder(
                  animation: _radarController,
                  builder: (context, child) {
                    return CustomPaint(
                      size: const Size(180, 180),
                      painter: RadarScanPainter(
                        progress: _radarController.value,
                        isScanning: widget.isScanning,
                        isSuccess: widget.isSuccess,
                        hasError: widget.errorMessage != null && widget.errorMessage!.isNotEmpty,
                        primaryColor: primaryBlue,
                        successColor: emeraldGreen,
                        errorColor: roseError,
                      ),
                    );
                  },
                ),
                // Center Icon / Biometric Avatar
                AnimatedScale(
                  scale: widget.isSuccess ? 1.15 : 1.0,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.elasticOut,
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.isSuccess
                          ? emeraldGreen.withValues(alpha: 0.18)
                          : primaryBlue.withValues(alpha: 0.12),
                      border: Border.all(
                        color: widget.isSuccess ? emeraldGreen : primaryBlue,
                        width: 2,
                      ),
                    ),
                    child: Icon(
                      widget.isSuccess
                          ? Icons.verified_rounded
                          : (widget.isScanning
                              ? Icons.face_retouching_natural_rounded
                              : Icons.face_rounded),
                      size: 36,
                      color: widget.isSuccess ? emeraldGreen : primaryBlue,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Dynamic Real-Time Validation Chips
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
              ),
            ),
            child: Column(
              children: [
                _buildValidationRow(
                  icon: Icons.access_time_filled_rounded,
                  label: 'Period Timing Window',
                  status: checks['timing']?['status'] ?? 'Schedule slot active',
                  isValid: checks['timing']?['valid'] ?? true,
                  isDark: isDark,
                ),
                const Divider(height: 14, thickness: 0.5),
                _buildValidationRow(
                  icon: Icons.location_on_rounded,
                  label: 'Campus Geofence Boundary',
                  status: checks['geofence']?['status'] ?? 'Inside College Coordinates',
                  isValid: checks['geofence']?['valid'] ?? true,
                  isDark: isDark,
                ),
                const Divider(height: 14, thickness: 0.5),
                _buildValidationRow(
                  icon: Icons.fingerprint_rounded,
                  label: 'Biometric & Anti-Spoof',
                  status: checks['biometrics']?['status'] ?? 'Ready for face verification',
                  isValid: checks['biometrics']?['valid'] ?? true,
                  isDark: isDark,
                ),
                const Divider(height: 14, thickness: 0.5),
                _buildValidationRow(
                  icon: Icons.verified_user_rounded,
                  label: 'Duplicate Check',
                  status: checks['duplicate']?['status'] ?? 'No duplicate attendance record',
                  isValid: checks['duplicate']?['valid'] ?? true,
                  isDark: isDark,
                ),
              ],
            ),
          ),

          if (widget.errorMessage != null && widget.errorMessage!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: roseError.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: roseError.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded, color: roseError, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.errorMessage!,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        color: roseError,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (widget.onScanPressed != null) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: widget.isScanning ? null : widget.onScanPressed,
                style: ElevatedButton.styleFrom(
                  backgroundColor: widget.isSuccess ? emeraldGreen : primaryBlue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                icon: widget.isScanning
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Icon(widget.isSuccess ? Icons.check_rounded : Icons.camera_alt_rounded, size: 18),
                label: Text(
                  widget.isScanning
                      ? 'Verifying...'
                      : (widget.isSuccess ? 'Attendance Verified' : 'Mark Attendance'),
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildValidationRow({
    required IconData icon,
    required String label,
    required String status,
    required bool isValid,
    required bool isDark,
  }) {
    final statusColor = isValid ? emeraldGreen : roseError;
    return Row(
      children: [
        Icon(icon, size: 16, color: statusColor),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'Inter',
              fontWeight: FontWeight.w600,
              fontSize: 12,
              color: isDark ? Colors.white70 : const Color(0xFF334155),
            ),
          ),
        ),
        Text(
          status,
          style: TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w600,
            fontSize: 11,
            color: statusColor,
          ),
        ),
      ],
    );
  }
}

/// Custom radar sweep painter with pulsating concentric waves and rotating scanning beam
class RadarScanPainter extends CustomPainter {
  final double progress;
  final bool isScanning;
  final bool isSuccess;
  final bool hasError;
  final Color primaryColor;
  final Color successColor;
  final Color errorColor;

  RadarScanPainter({
    required this.progress,
    required this.isScanning,
    required this.isSuccess,
    required this.hasError,
    required this.primaryColor,
    required this.successColor,
    required this.errorColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;
    final activeColor = isSuccess
        ? successColor
        : (hasError ? errorColor : primaryColor);

    // 1. Concentric circles
    final circlePaint = Paint()
      ..color = activeColor.withValues(alpha: 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    for (int i = 1; i <= 3; i++) {
      canvas.drawCircle(center, maxRadius * (i / 3), circlePaint);
    }

    // 2. Crosshair grid
    final gridPaint = Paint()
      ..color = activeColor.withValues(alpha: 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    canvas.drawLine(Offset(center.dx, 0), Offset(center.dx, size.height), gridPaint);
    canvas.drawLine(Offset(0, center.dy), Offset(size.width, center.dy), gridPaint);

    // 3. Pulsating wave ring
    if (isScanning || !isSuccess) {
      final pulseRadius = maxRadius * progress;
      final pulsePaint = Paint()
        ..color = activeColor.withValues(alpha: (1.0 - progress) * 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawCircle(center, pulseRadius, pulsePaint);
    }

    // 4. Rotating sweep sector
    if (isScanning) {
      final sweepAngle = math.pi / 3;
      final startAngle = progress * 2 * math.pi;
      final sweepPaint = Paint()
        ..shader = SweepGradient(
          startAngle: 0.0,
          endAngle: sweepAngle,
          colors: [
            activeColor.withValues(alpha: 0.0),
            activeColor.withValues(alpha: 0.4),
          ],
          transform: GradientRotation(startAngle),
        ).createShader(Rect.fromCircle(center: center, radius: maxRadius))
        ..style = PaintingStyle.fill;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: maxRadius),
        startAngle,
        sweepAngle,
        true,
        sweepPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant RadarScanPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.isScanning != isScanning ||
        oldDelegate.isSuccess != isSuccess ||
        oldDelegate.hasError != hasError;
  }
}
