import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Dense image feature vector used for on-device visual similarity comparison.
class ImageEmbedding {
  const ImageEmbedding({
    required this.vector,
    required this.dimension,
  });

  final List<double> vector;
  final int dimension;

  /// Computes cosine similarity between this embedding and another: (A · B) / (|A| * |B|)
  double cosineSimilarity(ImageEmbedding other) {
    if (vector.length != other.vector.length || vector.isEmpty) return 0.0;
    double dot = 0.0;
    double normA = 0.0;
    double normB = 0.0;
    for (int i = 0; i < vector.length; i++) {
      final a = vector[i];
      final b = other.vector[i];
      dot += a * b;
      normA += a * a;
      normB += b * b;
    }
    if (normA <= 0.0 || normB <= 0.0) return 0.0;
    final similarity = dot / (math.sqrt(normA) * math.sqrt(normB));
    return similarity.clamp(0.0, 1.0);
  }
}

/// On-device perceptual image feature extractor.
///
/// Computes grounded, normalized 128-dimensional dense feature vectors
/// capturing spatial luminance, color distribution, and quadrant gradient histograms.
/// Runs completely locally on Android without external network calls or cloud models.
class ImageFeatureExtractor {
  const ImageFeatureExtractor();

  static const int vectorDimension = 128;

  /// Extracts an [ImageEmbedding] from raw image bytes (JPEG, PNG, WebP).
  ImageEmbedding? extract(Uint8List imageBytes) {
    try {
      final image = img.decodeImage(imageBytes);
      if (image == null) return null;

      // Resize to standardized 16x16 perceptual grid (256 pixels)
      final resized = img.copyResize(image, width: 16, height: 16);

      final List<double> raw = [];

      // 1. 64-d: Normalized grayscale luminance across 16x16 grid downsampled to 8x8
      for (int y = 0; y < 8; y++) {
        for (int x = 0; x < 8; x++) {
          final p0 = resized.getPixel(x * 2, y * 2);
          final p1 = resized.getPixel(x * 2 + 1, y * 2);
          final p2 = resized.getPixel(x * 2, y * 2 + 1);
          final p3 = resized.getPixel(x * 2 + 1, y * 2 + 1);
          final lum = (p0.luminance + p1.luminance + p2.luminance + p3.luminance) / 4.0;
          raw.add(lum / 255.0);
        }
      }

      // 2. 32-d: Color chromaticity distribution across 4 quadrants (8 values per quadrant: R, G, B, H, S, V, Contrast, Warmth)
      for (int qy = 0; qy < 2; qy++) {
        for (int qx = 0; qx < 2; qx++) {
          double totalR = 0, totalG = 0, totalB = 0;
          double maxLum = 0, minLum = 255;
          int count = 0;

          for (int y = qy * 8; y < (qy + 1) * 8; y++) {
            for (int x = qx * 8; x < (qx + 1) * 8; x++) {
              final p = resized.getPixel(x, y);
              totalR += p.r.toDouble();
              totalG += p.g.toDouble();
              totalB += p.b.toDouble();
              final lum = p.luminance.toDouble();
              if (lum > maxLum) maxLum = lum;
              if (lum < minLum) minLum = lum;
              count++;
            }
          }

          final avgR = (totalR / count) / 255.0;
          final avgG = (totalG / count) / 255.0;
          final avgB = (totalB / count) / 255.0;
          final contrast = (maxLum - minLum) / 255.0;
          final warmth = (avgR - avgB).clamp(-1.0, 1.0) * 0.5 + 0.5;

          // Simple HSV estimates
          final maxC = math.max(avgR, math.max(avgG, avgB));
          final minC = math.min(avgR, math.min(avgG, avgB));
          final delta = maxC - minC;
          final sat = maxC == 0 ? 0.0 : delta / maxC;
          final val = maxC;

          raw.addAll([avgR, avgG, avgB, maxC, sat, val, contrast, warmth]);
        }
      }

      // 3. 32-d: Spatial horizontal and vertical gradient energy (edge transitions)
      for (int y = 0; y < 16; y += 4) {
        for (int x = 0; x < 16; x += 4) {
          double hGrad = 0;
          double vGrad = 0;
          for (int dy = 0; dy < 3; dy++) {
            for (int dx = 0; dx < 3; dx++) {
              final p00 = resized.getPixel(x + dx, y + dy).luminance.toDouble();
              final p01 = resized.getPixel(x + dx + 1, y + dy).luminance.toDouble();
              final p10 = resized.getPixel(x + dx, y + dy + 1).luminance.toDouble();
              hGrad += (p01 - p00).abs();
              vGrad += (p10 - p00).abs();
            }
          }
          raw.add((hGrad / 9.0) / 255.0);
          raw.add((vGrad / 9.0) / 255.0);
        }
      }

      // Ensure exact 128 dimensions
      final truncated = raw.take(vectorDimension).toList();
      while (truncated.length < vectorDimension) {
        truncated.add(0.0);
      }

      // L2 Normalize the vector to unit length
      double sumSq = 0.0;
      for (final v in truncated) {
        sumSq += v * v;
      }
      final norm = math.sqrt(sumSq);
      final normalized = norm > 0 ? truncated.map((v) => v / norm).toList() : truncated;

      return ImageEmbedding(vector: normalized, dimension: vectorDimension);
    } catch (e) {
      debugPrint('ImageFeatureExtractor error: $e');
      return null;
    }
  }
}
