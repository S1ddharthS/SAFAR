import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// State of an active voice recording session.
enum RecordingStatus { idle, recording, paused, stopped }

/// Status of the audio preview playback.
enum AudioPlaybackStatus { stopped, playing, paused }

/// Manages on-device voice memory recording and preview playback.
class VoiceRecorderService {
  VoiceRecorderService({AudioRecorder? recorder, AudioPlayer? player})
      : _recorder = recorder ?? AudioRecorder(),
        _player = player ?? AudioPlayer();

  final AudioRecorder _recorder;
  final AudioPlayer _player;

  RecordingStatus _status = RecordingStatus.idle;
  RecordingStatus get status => _status;

  String? _recordedFilePath;
  String? get recordedFilePath => _recordedFilePath;

  Duration _recordingDuration = Duration.zero;
  Duration get recordingDuration => _recordingDuration;

  Timer? _timer;

  /// Checks if microphone permission is granted.
  Future<bool> hasPermission() async {
    try {
      return await _recorder.hasPermission();
    } catch (e) {
      debugPrint('VoiceRecorderService permission error: $e');
      return false;
    }
  }

  /// Starts a new voice recording in WAV format into the cache directory.
  Future<String?> startRecording() async {
    final permitted = await hasPermission();
    if (!permitted) return null;

    final cacheDir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final path = '${cacheDir.path}/safar_voice_$timestamp.wav';

    try {
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 44100,
          numChannels: 1,
        ),
        path: path,
      );

      _status = RecordingStatus.recording;
      _recordedFilePath = path;
      _recordingDuration = Duration.zero;

      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        _recordingDuration += const Duration(seconds: 1);
      });

      return path;
    } catch (e) {
      debugPrint('VoiceRecorderService startRecording error: $e');
      _status = RecordingStatus.idle;
      return null;
    }
  }

  /// Pauses the current recording.
  Future<void> pauseRecording() async {
    if (_status != RecordingStatus.recording) return;
    try {
      await _recorder.pause();
      _status = RecordingStatus.paused;
      _timer?.cancel();
    } catch (e) {
      debugPrint('VoiceRecorderService pauseRecording error: $e');
    }
  }

  /// Resumes a paused recording.
  Future<void> resumeRecording() async {
    if (_status != RecordingStatus.paused) return;
    try {
      await _recorder.resume();
      _status = RecordingStatus.recording;
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        _recordingDuration += const Duration(seconds: 1);
      });
    } catch (e) {
      debugPrint('VoiceRecorderService resumeRecording error: $e');
    }
  }

  /// Stops recording and returns the path to the recorded file.
  Future<String?> stopRecording() async {
    _timer?.cancel();
    if (_status == RecordingStatus.idle) return null;

    try {
      final path = await _recorder.stop();
      _status = RecordingStatus.stopped;
      _recordedFilePath = path ?? _recordedFilePath;
      return _recordedFilePath;
    } catch (e) {
      debugPrint('VoiceRecorderService stopRecording error: $e');
      _status = RecordingStatus.idle;
      return null;
    }
  }

  /// Discards the recorded audio file and resets state.
  Future<void> cancelRecording() async {
    _timer?.cancel();
    try {
      if (_status == RecordingStatus.recording || _status == RecordingStatus.paused) {
        await _recorder.stop();
      }
      if (_recordedFilePath != null) {
        final file = File(_recordedFilePath!);
        if (await file.exists()) {
          await file.delete();
        }
      }
    } catch (e) {
      debugPrint('VoiceRecorderService cancelRecording error: $e');
    } finally {
      _recordedFilePath = null;
      _recordingDuration = Duration.zero;
      _status = RecordingStatus.idle;
    }
  }

  // --- Audio Playback Preview ---

  Future<void> playPreview({required VoidCallback onComplete}) async {
    if (_recordedFilePath == null) return;
    final file = File(_recordedFilePath!);
    if (!await file.exists()) return;

    try {
      _player.onPlayerComplete.listen((_) => onComplete());
      await _player.play(DeviceFileSource(_recordedFilePath!));
    } catch (e) {
      debugPrint('VoiceRecorderService playPreview error: $e');
    }
  }

  Future<void> stopPreview() async {
    try {
      await _player.stop();
    } catch (e) {
      debugPrint('VoiceRecorderService stopPreview error: $e');
    }
  }

  void dispose() {
    _timer?.cancel();
    _recorder.dispose();
    _player.dispose();
  }
}
