import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Result of an on-device OCR extraction.
class OcrResult {
  const OcrResult({
    required this.text,
    required this.blocksCount,
    required this.linesCount,
    this.error,
  });

  final String text;
  final int blocksCount;
  final int linesCount;
  final String? error;

  bool get hasText => text.trim().isNotEmpty;
}

/// Service providing on-device optical character recognition via Google ML Kit.
class OcrService {
  const OcrService();

  /// Extracts text from a local image file on-device without remote network calls.
  Future<OcrResult> extractText(File imageFile) async {
    if (!await imageFile.exists()) {
      return const OcrResult(
        text: '',
        blocksCount: 0,
        linesCount: 0,
        error: 'Image file does not exist on disk.',
      );
    }

    try {
      final inputImage = InputImage.fromFile(imageFile);
      final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final recognizedText = await textRecognizer.processImage(inputImage);
      await textRecognizer.close();

      return OcrResult(
        text: recognizedText.text,
        blocksCount: recognizedText.blocks.length,
        linesCount: recognizedText.blocks.fold(
          0,
          (sum, block) => sum + block.lines.length,
        ),
      );
    } catch (e, stack) {
      debugPrint('OcrService error: $e\n$stack');
      return OcrResult(
        text: '',
        blocksCount: 0,
        linesCount: 0,
        error: 'On-device text recognition failed: $e',
      );
    }
  }
}
