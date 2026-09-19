import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;

/// Enhanced face recognition helper with improved image preprocessing
/// Web-compatible: uses XFile and Uint8List instead of dart:io File
class FaceRecognitionHelper {
  static const double _maxBlurThreshold = 80.0;
  static const double _minBrightness = 20.0;
  static const double _maxBrightness = 220.0;

  static final Map<String, double> _qualityCache = {};
  static const int _maxCacheSize = 50;

  static const List<num> _laplacianKernel = [0, -1, 0, -1, 4, -1, 0, -1, 0];

  /// Capture the frame directly to avoid slow client-side CPU processing (web-compatible)
  static Future<XFile?> captureBestFrame(
    CameraController controller, {
    int maxFrames = 3,
  }) async {
    try {
      return await controller.takePicture();
    } catch (e) {
      return null;
    }
  }


  /// Calculate image quality score from bytes (web-compatible)
  static Future<double> calculateImageQualityScoreFromBytes(
    Uint8List bytes,
  ) async {
    try {
      final cacheKey = bytes.hashCode.toString();
      if (_qualityCache.containsKey(cacheKey)) {
        return _qualityCache[cacheKey]!;
      }

      final image = img.decodeImage(bytes);
      if (image == null) {
        _cacheResult(cacheKey, 0.0);
        return 0.0;
      }

      double score = 0.0;

      final blurScore = _calculateBlurScore(image);
      if (blurScore < 0.05) {
        _cacheResult(cacheKey, 0.3);
        return 0.3;
      }
      score += blurScore * 0.4;

      final brightnessScore = _calculateBrightnessScore(image);
      if (brightnessScore < 0.1) {
        _cacheResult(cacheKey, score * 0.5);
        return score * 0.5;
      }
      score += brightnessScore * 0.3;

      final contrastScore = _calculateContrastScore(image);
      score += contrastScore * 0.15;

      final sharpnessScore = _calculateSharpnessScore(image);
      score += sharpnessScore * 0.15;

      final finalScore = score.clamp(0.0, 1.0);
      _cacheResult(cacheKey, finalScore);
      return finalScore;
    } catch (e) {
      return 0.5;
    }
  }

  /// Preprocess image bytes for better face detection (minimal processing)
  static Future<Uint8List?> preprocessImageBytes(Uint8List bytes) async {
    try {
      final originalImage = img.decodeImage(bytes);
      if (originalImage == null) return null;

      final processed = _resizeIfNeeded(originalImage);
      return Uint8List.fromList(img.encodeJpg(processed, quality: 95));
    } catch (e) {
      return bytes;
    }
  }

  static void _cacheResult(String key, double score) {
    if (_qualityCache.length >= _maxCacheSize) {
      _qualityCache.remove(_qualityCache.keys.first);
    }
    _qualityCache[key] = score;
  }

  static double _calculateBlurScore(img.Image image) {
    try {
      final grayscale = image.numChannels == 3 ? img.grayscale(image) : image;
      final laplacian = _laplacian(grayscale);
      final variance = _calculateVariance(laplacian);
      return (variance / _maxBlurThreshold).clamp(0.0, 1.0);
    } catch (e) {
      return 0.0;
    }
  }

  static double _calculateBrightnessScore(img.Image image) {
    try {
      final grayscale = image.numChannels == 3 ? img.grayscale(image) : image;
      int totalBrightness = 0;
      int pixelCount = 0;

      final step = (grayscale.width * grayscale.height > 10000) ? 10 : 1;

      for (int y = 0; y < grayscale.height; y += step) {
        for (int x = 0; x < grayscale.width; x += step) {
          final pixel = grayscale.getPixel(x, y);
          totalBrightness += pixel.r.toInt();
          pixelCount++;
        }
      }

      final avgBrightness = totalBrightness / pixelCount;

      if (avgBrightness < _minBrightness || avgBrightness > _maxBrightness) {
        return 0.0;
      }

      final optimalRange = _maxBrightness - _minBrightness;
      final distanceFromOptimal = (avgBrightness - 120).abs();
      return 1.0 - (distanceFromOptimal / optimalRange).clamp(0.0, 1.0);
    } catch (e) {
      return 0.0;
    }
  }

  static double _calculateContrastScore(img.Image image) {
    try {
      final grayscale = image.numChannels == 3 ? img.grayscale(image) : image;
      final histogram = <int>[for (int i = 0; i < 256; i++) 0];

      final step = (grayscale.width * grayscale.height > 50000) ? 20 : 5;

      for (int y = 0; y < grayscale.height; y += step) {
        for (int x = 0; x < grayscale.width; x += step) {
          final pixel = grayscale.getPixel(x, y);
          histogram[pixel.r.toInt()]++;
        }
      }

      final mean = histogram.reduce((a, b) => a + b) / 256;
      double variance = 0;
      for (int i = 0; i < 256; i++) {
        variance += (histogram[i] - mean) * (histogram[i] - mean);
      }
      variance /= 256;
      final stdDev = variance > 0 ? _sqrt(variance) : 0;

      return (stdDev / 50).clamp(0.0, 1.0);
    } catch (e) {
      return 0.0;
    }
  }

  static double _calculateSharpnessScore(img.Image image) {
    try {
      final grayscale = image.numChannels == 3 ? img.grayscale(image) : image;

      int edgeCount = 0;
      int totalPixels = 0;

      final step = (grayscale.width * grayscale.height > 10000) ? 3 : 1;

      for (int y = step; y < grayscale.height - step; y += step) {
        for (int x = step; x < grayscale.width - step; x += step) {
          final center = grayscale.getPixel(x, y).r;
          final left = grayscale.getPixel(x - step, y).r;
          final top = grayscale.getPixel(x, y - step).r;

          final gradientX = (center - left).abs();
          final gradientY = (center - top).abs();
          final gradient = (gradientX + gradientY) / 2;

          if (gradient > 30) edgeCount++;
          totalPixels++;
        }
      }

      final edgeRatio = edgeCount / totalPixels;
      return (edgeRatio * 10).clamp(0.0, 1.0);
    } catch (e) {
      return 0.0;
    }
  }

  static img.Image _laplacian(img.Image image) {
    return img.convolution(image, filter: _laplacianKernel);
  }

  static double _calculateVariance(img.Image image) {
    double sum = 0;
    double sumSquared = 0;
    int count = 0;

    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y).r.toDouble();
        sum += pixel;
        sumSquared += pixel * pixel;
        count++;
      }
    }

    final mean = sum / count;
    final meanSquared = sumSquared / count;
    return meanSquared - (mean * mean);
  }

  static img.Image _resizeIfNeeded(img.Image image) {
    const maxSize = 800;

    if (image.width <= maxSize && image.height <= maxSize) {
      return image;
    }

    final aspectRatio = image.width / image.height;
    int newWidth, newHeight;

    if (image.width > image.height) {
      newWidth = maxSize;
      newHeight = (maxSize / aspectRatio).round();
    } else {
      newHeight = maxSize;
      newWidth = (maxSize * aspectRatio).round();
    }

    return img.copyResize(
      image,
      width: newWidth,
      height: newHeight,
      interpolation: img.Interpolation.linear,
    );
  }

  static double _sqrt(double x) {
    if (x < 0) return 0;
    if (x == 0) return 0;

    double guess = x / 2;
    double prev = 0;

    while ((guess - prev).abs() > 0.0001) {
      prev = guess;
      guess = (guess + x / guess) / 2;
    }

    return guess;
  }
}
