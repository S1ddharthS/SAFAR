import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Service managing on-device speech-to-text recognition.
class SpeechTranscriber {
  SpeechTranscriber({SpeechToText? speech})
      : _speech = speech ?? SpeechToText();

  final SpeechToText _speech;
  bool _isInitialized = false;
  bool _isAvailable = false;

  bool get isAvailable => _isAvailable;
  bool get isListening => _speech.isListening;

  /// Initializes the speech recognizer and checks device availability.
  Future<bool> initialize() async {
    if (_isInitialized) return _isAvailable;
    try {
      _isAvailable = await _speech.initialize(
        onError: (val) => debugPrint('SpeechTranscriber error: ${val.errorMsg}'),
        onStatus: (val) => debugPrint('SpeechTranscriber status: $val'),
      );
      _isInitialized = true;
      return _isAvailable;
    } catch (e) {
      debugPrint('SpeechTranscriber init error: $e');
      _isAvailable = false;
      _isInitialized = true;
      return false;
    }
  }

  /// Starts listening to the microphone and transcribes speech.
  Future<bool> startListening({
    required ValueChanged<String> onText,
    String? localeId,
  }) async {
    final available = await initialize();
    if (!available) return false;

    try {
      await _speech.listen(
        onResult: (SpeechRecognitionResult result) {
          onText(result.recognizedWords);
        },
        listenOptions: SpeechListenOptions(
          localeId: localeId,
          listenFor: const Duration(minutes: 2),
          pauseFor: const Duration(seconds: 4),
          partialResults: true,
          cancelOnError: false,
        ),
      );
      return true;
    } catch (e) {
      debugPrint('SpeechTranscriber startListening error: $e');
      return false;
    }
  }

  /// Stops active listening.
  Future<void> stopListening() async {
    try {
      await _speech.stop();
    } catch (e) {
      debugPrint('SpeechTranscriber stopListening error: $e');
    }
  }

  /// Cancels listening.
  Future<void> cancelListening() async {
    try {
      await _speech.cancel();
    } catch (e) {
      debugPrint('SpeechTranscriber cancelListening error: $e');
    }
  }
}
