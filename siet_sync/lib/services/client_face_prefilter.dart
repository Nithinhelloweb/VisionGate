import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../utils/platform_utils.dart';

/// Target pose requested during face capture or registration
enum FaceTargetPose {
  front, // Looking straight at camera (yaw: [-18, +18], roll: [-18, +18])
  left,  // Turned towards user's left (yaw <= -15 or |yaw| >= 15)
  right, // Turned towards user's right (yaw >= +15 or |yaw| >= 15)
  any,   // Any valid centered face for attendance (yaw: [-30, +30], roll: [-25, +25])
}

/// Result from on-device client face pre-filtering
class FacePreFilterResult {
  final bool isValid;
  final String? message;
  final int faceCount;
  final double? headEulerY; // Yaw angle (left/right)
  final double? headEulerZ; // Tilt/roll angle
  final FaceTargetPose? detectedPose;

  const FacePreFilterResult({
    required this.isValid,
    this.message,
    this.faceCount = 0,
    this.headEulerY,
    this.headEulerZ,
    this.detectedPose,
  });
}

/// Client-Side Edge Face Pre-Filter Service
/// Uses Google ML Kit on mobile devices (Android / iOS) to reject empty/blurry/misaligned frames
/// locally before transmitting over the network, saving backend bandwidth & inference compute.
class ClientFacePreFilterService {
  static FaceDetector? _detector;

  static FaceDetector _getDetector({FaceDetectorMode mode = FaceDetectorMode.fast}) {
    return _detector ??= FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: mode,
        enableLandmarks: false,
        enableContours: false,
        enableClassification: true,
        minFaceSize: 0.12,
      ),
    );
  }

  /// Evaluates an image file path on device before uploading.
  /// On Desktop/Web, passes through immediately with isValid = true.
  static Future<FacePreFilterResult> evaluateImagePath(
    String imagePath, {
    FaceTargetPose targetPose = FaceTargetPose.any,
    bool allowMultipleFaces = false,
  }) async {
    if (!AppPlatform.isMobile) {
      // Desktop / Web: Pass through to server InsightFace engine
      return const FacePreFilterResult(isValid: true);
    }

    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final detector = _getDetector();
      final List<Face> faces = await detector.processImage(inputImage);

      if (faces.isEmpty) {
        return const FacePreFilterResult(
          isValid: false,
          faceCount: 0,
          message: 'No face detected. Please position your face inside the frame.',
        );
      }

      // Enforce single-face rule for attendance integrity to prevent proxy marking
      if (faces.length > 1 && !allowMultipleFaces) {
        return FacePreFilterResult(
          isValid: false,
          faceCount: faces.length,
          message: 'Multiple faces detected (${faces.length}). Only one person must be visible.',
        );
      }

      // Check primary face alignment (first face)
      final primary = faces.first;
      final yaw = primary.headEulerAngleY; // Head turned left/right (-left, +right or vice versa)
      final roll = primary.headEulerAngleZ; // Head tilted sideways

      // Evaluate Roll (sideways head tilt)
      if (roll != null && (roll < -25 || roll > 25)) {
        return FacePreFilterResult(
          isValid: false,
          faceCount: faces.length,
          headEulerZ: roll,
          headEulerY: yaw,
          message: 'Head is tilted. Please hold device straight and upright.',
        );
      }

      // Evaluate Eye Open Probability (ensure subject is alert with open eyes)
      final leftEye = primary.leftEyeOpenProbability;
      final rightEye = primary.rightEyeOpenProbability;
      if (leftEye != null && rightEye != null && leftEye < 0.15 && rightEye < 0.15) {
        return FacePreFilterResult(
          isValid: false,
          faceCount: faces.length,
          headEulerZ: roll,
          headEulerY: yaw,
          message: 'Eyes appear closed. Please look directly at the camera with eyes open.',
        );
      }

      // Evaluate Yaw & Target Pose
      switch (targetPose) {
        case FaceTargetPose.front:
          if (yaw != null && (yaw < -18 || yaw > 18)) {
            return FacePreFilterResult(
              isValid: false,
              faceCount: faces.length,
              headEulerY: yaw,
              headEulerZ: roll,
              message: 'Please look directly into the camera.',
            );
          }
          break;

        case FaceTargetPose.left:
          // User asked to turn left: yaw should exhibit significant turn (|yaw| >= 14)
          if (yaw != null && yaw.abs() < 14) {
            return FacePreFilterResult(
              isValid: false,
              faceCount: faces.length,
              headEulerY: yaw,
              headEulerZ: roll,
              message: 'Please turn your head slightly to the left.',
            );
          }
          break;

        case FaceTargetPose.right:
          // User asked to turn right: yaw should exhibit significant turn (|yaw| >= 14)
          if (yaw != null && yaw.abs() < 14) {
            return FacePreFilterResult(
              isValid: false,
              faceCount: faces.length,
              headEulerY: yaw,
              headEulerZ: roll,
              message: 'Please turn your head slightly to the right.',
            );
          }
          break;

        case FaceTargetPose.any:
          if (yaw != null && (yaw < -30 || yaw > 30)) {
            return FacePreFilterResult(
              isValid: false,
              faceCount: faces.length,
              headEulerY: yaw,
              headEulerZ: roll,
              message: 'Face is angled away. Please look directly at the camera.',
            );
          }
          break;
      }

      return FacePreFilterResult(
        isValid: true,
        faceCount: faces.length,
        headEulerY: yaw,
        headEulerZ: roll,
        detectedPose: targetPose,
      );
    } catch (e) {
      // If on-device ML Kit encounters an internal platform error, fall back gracefully to server
      debugPrint('[ClientFacePreFilterService] Pre-filter error, falling back to server: $e');
      return const FacePreFilterResult(isValid: true);
    }
  }

  /// Disposes the ML Kit face detector instance when not in use.
  static Future<void> dispose() async {
    if (_detector != null) {
      await _detector!.close();
      _detector = null;
    }
  }
}
