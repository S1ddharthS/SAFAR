import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/models/memories.dart';
import '../../core/network/api_exception.dart';
import '../../core/providers.dart';
import '../../core/theme/safar_theme.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/safar_widgets.dart';
import '../auth/auth_controller.dart';

class MemoriesScreen extends ConsumerStatefulWidget {
  const MemoriesScreen({super.key, required this.tripId});

  final String tripId;

  @override
  ConsumerState<MemoriesScreen> createState() => _MemoriesScreenState();
}

class _MemoriesScreenState extends ConsumerState<MemoriesScreen> {
  bool _busy = false;

  Future<void> _refresh() async {
    ref.invalidate(memoriesProvider(widget.tripId));
    ref.invalidate(studioProvider(widget.tripId));
    ref.invalidate(replayProvider(widget.tripId));
    try {
      await ref.read(memoriesProvider(widget.tripId).future);
    } on Object {
      // Rendered by AsyncView.
    }
  }

  Future<void> _add() async {
    final created = await showSafarSheet<bool>(
      context,
      builder: (_) => _MemorySheet(tripId: widget.tripId),
    );
    if (created == true) {
      ref.invalidate(memoriesProvider(widget.tripId));
      ref.invalidate(replayProvider(widget.tripId));
    }
  }

  Future<void> _update(
    Memory memory,
    Map<String, dynamic> changes,
    String success,
  ) async {
    setState(() => _busy = true);
    try {
      await ref
          .read(memoryRepositoryProvider)
          .update(widget.tripId, memory.id, changes);
      ref.invalidate(memoriesProvider(widget.tripId));
      ref.invalidate(studioProvider(widget.tripId));
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(success)));
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(Memory memory) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this memory?'),
        content: const Text(
          'This removes the memory for everyone who could see it. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: context.colors.error,
              foregroundColor: context.colors.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(memoryRepositoryProvider)
          .delete(widget.tripId, memory.id);
      ref.invalidate(memoriesProvider(widget.tripId));
      ref.invalidate(studioProvider(widget.tripId));
      ref.invalidate(replayProvider(widget.tripId));
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final memories = ref.watch(memoriesProvider(widget.tripId));
    final myId = ref.watch(authControllerProvider).user?.id;
    final baseUrl = ref.watch(apiClientProvider).baseUrl;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text('Memory'),
      ),
      appBar: AppBar(
        title: const Text('Memories'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: AsyncView(
            value: memories,
            onRetry: () => ref.invalidate(memoriesProvider(widget.tripId)),
            builder: (data) {
              if (data.total == 0) {
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    const SizedBox(height: 40),
                    SafarEmpty(
                      icon: Icons.photo_library_outlined,
                      title: 'Nothing captured yet',
                      message:
                          'Keep small moments: a view, a meal, a joke that landed. '
                          'Share with the trip or keep it private.',
                      action: FilledButton(
                        onPressed: _add,
                        child: const Text('Add a memory'),
                      ),
                    ),
                  ],
                );
              }
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Eyebrow('The trip, kept'),
                            const SizedBox(height: 6),
                            Text(
                              '${data.total} ${data.total == 1 ? 'memory' : 'memories'}',
                              style: context.texts.headlineLarge,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  InfoBanner(
                    text: data.permissions,
                    icon: Icons.lock_outline,
                  ),
                  const SizedBox(height: 18),
                  for (final day in data.days) ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 2,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            formatDate(day.date),
                            style: context.texts.titleMedium,
                          ),
                          Text(
                            formatWeekday(day.date),
                            style: context.texts.labelSmall,
                          ),
                          Text(
                            day.memories.length == 1
                                ? '1 memory'
                                : '${day.memories.length} memories',
                            style: context.texts.labelSmall,
                          ),
                        ],
                      ),
                    ),
                    for (final memory in day.memories)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _MemoryCard(
                          memory: memory,
                          baseUrl: baseUrl,
                          isMine: memory.userId == myId,
                          busy: _busy,
                          onVisibility: (visibility) => _update(
                            memory,
                            {'visibility': visibility},
                            visibility == 'private'
                                ? 'Memory is now private.'
                                : 'Memory shared with the trip.',
                          ),
                          onApprove: memory.aiGenerated && !memory.approved
                              ? () => _update(
                                  memory,
                                  {'approved': true},
                                  'AI-assisted memory approved.',
                                )
                              : null,
                          onDelete: () => _delete(memory),
                        ),
                      ),
                    const SizedBox(height: 10),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _MemoryCard extends StatelessWidget {
  const _MemoryCard({
    required this.memory,
    required this.baseUrl,
    required this.isMine,
    required this.busy,
    required this.onVisibility,
    required this.onApprove,
    required this.onDelete,
  });

  final Memory memory;
  final String baseUrl;
  final bool isMine;
  final bool busy;
  final ValueChanged<String> onVisibility;
  final VoidCallback? onApprove;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final palette = context.safar;
    final mediaUrl = memory.mediaUrl == null
        ? null
        : (memory.mediaUrl!.startsWith('/')
              ? '$baseUrl${memory.mediaUrl}'
              : memory.mediaUrl);
    final author = memory.author?.displayName ?? (isMine ? 'You' : 'Traveller');
    return SafarCard(
      padding: const EdgeInsets.all(14),
      radius: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SafarAvatar(name: author, size: 30, highlight: isMine),
              const SizedBox(width: 9),
              Expanded(child: Text(author, style: context.texts.titleSmall)),
              StatusChip(
                memory.visibility,
                tone: memory.isPrivate ? ChipTone.rose : ChipTone.jade,
                icon: memory.isPrivate ? Icons.lock_outline : Icons.groups_outlined,
              ),
              if (isMine) ...[
                const SizedBox(width: 2),
                PopupMenuButton<String>(
                  enabled: !busy,
                  icon: Icon(Icons.more_horiz, size: 19, color: palette.muted),
                  onSelected: (value) {
                    if (value == 'private' || value == 'trip') {
                      onVisibility(value);
                    } else if (value == 'delete') {
                      onDelete();
                    }
                  },
                  itemBuilder: (context) => [
                    if (!memory.isPrivate)
                      const PopupMenuItem(
                        value: 'private',
                        child: Text('Make private'),
                      )
                    else
                      const PopupMenuItem(
                        value: 'trip',
                        child: Text('Share with trip'),
                      ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('Delete memory'),
                    ),
                  ],
                ),
              ],
            ],
          ),
          if (mediaUrl != null) ...[
            const SizedBox(height: 10),
            if (memory.kind == 'voice')
              _VoicePlayer(url: mediaUrl)
            else if (memory.kind == 'video')
              _VideoCard(url: mediaUrl, memory: memory)
            else
              SafarImage(url: mediaUrl, height: 190, radius: 16),
          ],
          if (memory.textContent != null && memory.textContent!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              memory.textContent!,
              style: context.texts.bodyMedium?.copyWith(height: 1.5),
            ),
          ],
          if (memory.caption != null && memory.caption!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              memory.caption!,
              style: context.texts.bodySmall?.copyWith(
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '${formatClock(memory.capturedAt)} · ${timeAgo(memory.capturedAt)}',
                style: context.texts.labelSmall,
              ),
              if (memory.aiGenerated)
                StatusChip(
                  memory.approved ? 'AI-assisted · approved' : 'AI draft',
                  tone: memory.approved ? ChipTone.neutral : ChipTone.ember,
                ),
              if (memory.lat != null && memory.lon != null)
                Tooltip(
                  message:
                      'Location is only shared with members who can see this memory.',
                  child: Icon(
                    Icons.place_outlined,
                    size: 15,
                    color: palette.faint,
                  ),
                ),
            ],
          ),
          if (onApprove != null) ...[
            const SizedBox(height: 10),
            InfoBanner(
              tone: ChipTone.ember,
              icon: Icons.auto_awesome,
              text:
                  'This memory was drafted with AI assistance. Review it before it counts as yours.',
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: busy ? null : onApprove,
              child: const Text('Approve memory'),
            ),
          ],
        ],
      ),
    );
  }
}

class _MemorySheet extends ConsumerStatefulWidget {
  const _MemorySheet({required this.tripId});

  final String tripId;

  @override
  ConsumerState<_MemorySheet> createState() => _MemorySheetState();
}

class _MemorySheetState extends ConsumerState<_MemorySheet> {
  final _text = TextEditingController();
  final _picker = ImagePicker();
  String _visibility = 'trip';
  bool _busy = false;
  String? _error;

  // Media selection
  String _mediaMode = 'text'; // 'text', 'photo', 'video', 'voice'

  // Photo state
  XFile? _photo;
  Uint8List? _photoBytes;
  String? _photoType;

  // Video state
  XFile? _video;
  Uint8List? _videoBytes;
  String? _videoName;

  // Voice recording state
  String? _voiceFilePath;
  Uint8List? _voiceBytes;
  bool _isRecording = false;
  bool _isPaused = false;
  bool _isPlayingPreview = false;
  Duration _voiceDuration = Duration.zero;

  // Speech to text state
  bool _isTranscribing = false;

  // Upload progress & cancellation
  bool _isUploading = false;
  double _uploadProgress = 0.0;
  CancelToken? _cancelToken;

  static const _maxMediaBytes = 25 * 1024 * 1024;

  @override
  void dispose() {
    _text.dispose();
    _cancelToken?.cancel('Sheet closed');
    super.dispose();
  }

  // --- Photo Picking ---
  Future<void> _choosePhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from library'),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    try {
      final file = await _picker.pickImage(
        source: source,
        maxWidth: 1920,
        imageQuality: 85,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (bytes.lengthInBytes > _maxMediaBytes) {
        if (!mounted) return;
        setState(() => _error = 'Photos are limited to 25 MB.');
        return;
      }
      if (!mounted) return;
      setState(() {
        _photo = file;
        _photoBytes = bytes;
        _photoType = _mimeForPhoto(file);
        _mediaMode = 'photo';
        _video = null;
        _videoBytes = null;
        _voiceFilePath = null;
        _voiceBytes = null;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not access photo library: $e');
    }
  }

  // --- Video Picking ---
  Future<void> _chooseVideo() async {
    try {
      final file = await _picker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(minutes: 5),
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (bytes.lengthInBytes > _maxMediaBytes) {
        if (!mounted) return;
        setState(() => _error = 'Videos are limited to 25 MB.');
        return;
      }
      if (!mounted) return;
      setState(() {
        _video = file;
        _videoBytes = bytes;
        _videoName = file.name;
        _mediaMode = 'video';
        _photo = null;
        _photoBytes = null;
        _voiceFilePath = null;
        _voiceBytes = null;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not select video: $e');
    }
  }

  // --- Voice Recording ---
  Future<void> _startRecording() async {
    final recorder = ref.read(voiceRecorderServiceProvider);
    final permitted = await recorder.hasPermission();
    if (!permitted) {
      setState(() => _error = 'Microphone permission is required to record voice memories.');
      return;
    }
    final path = await recorder.startRecording();
    if (path == null) {
      setState(() => _error = 'Could not start voice recording.');
      return;
    }
    setState(() {
      _isRecording = true;
      _isPaused = false;
      _voiceFilePath = path;
      _mediaMode = 'voice';
      _photo = null;
      _photoBytes = null;
      _video = null;
      _videoBytes = null;
      _error = null;
    });
  }

  Future<void> _pauseResumeRecording() async {
    final recorder = ref.read(voiceRecorderServiceProvider);
    if (_isPaused) {
      await recorder.resumeRecording();
      setState(() => _isPaused = false);
    } else {
      await recorder.pauseRecording();
      setState(() => _isPaused = true);
    }
  }

  Future<void> _stopRecording() async {
    final recorder = ref.read(voiceRecorderServiceProvider);
    final path = await recorder.stopRecording();
    if (path != null) {
      final file = File(path);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        setState(() {
          _isRecording = false;
          _isPaused = false;
          _voiceFilePath = path;
          _voiceBytes = bytes;
          _voiceDuration = recorder.recordingDuration;
        });
        return;
      }
    }
    setState(() {
      _isRecording = false;
      _isPaused = false;
    });
  }

  Future<void> _cancelRecording() async {
    final recorder = ref.read(voiceRecorderServiceProvider);
    await recorder.cancelRecording();
    setState(() {
      _isRecording = false;
      _isPaused = false;
      _isPlayingPreview = false;
      _voiceFilePath = null;
      _voiceBytes = null;
      _voiceDuration = Duration.zero;
      _mediaMode = 'text';
    });
  }

  Future<void> _toggleAudioPreview() async {
    final recorder = ref.read(voiceRecorderServiceProvider);
    if (_isPlayingPreview) {
      await recorder.stopPreview();
      setState(() => _isPlayingPreview = false);
    } else {
      setState(() => _isPlayingPreview = true);
      await recorder.playPreview(onComplete: () {
        if (mounted) setState(() => _isPlayingPreview = false);
      });
    }
  }

  // --- On-Device Speech Recognition ---
  Future<void> _toggleSpeechRecognition() async {
    final transcriber = ref.read(speechTranscriberProvider);
    if (_isTranscribing) {
      await transcriber.stopListening();
      setState(() => _isTranscribing = false);
      return;
    }

    final available = await transcriber.initialize();
    if (!available) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Speech recognition is not available or microphone permission was denied.',
          ),
        ),
      );
      return;
    }

    setState(() => _isTranscribing = true);
    final initialText = _text.text.trim();

    await transcriber.startListening(
      onText: (transcription) {
        if (!mounted) return;
        setState(() {
          _text.text = initialText.isEmpty ? transcription : '$initialText $transcription';
        });
      },
    );
  }

  void _cancelUpload() {
    _cancelToken?.cancel('Upload cancelled by user');
    setState(() {
      _isUploading = false;
      _busy = false;
      _uploadProgress = 0.0;
      _error = 'Upload cancelled.';
    });
  }

  static String _mimeForPhoto(XFile file) {
    final declared = file.mimeType;
    if (declared != null && declared.startsWith('image/')) return declared;
    final name = file.name.toLowerCase();
    if (name.endsWith('.png')) return 'image/png';
    if (name.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  Future<void> _submit() async {
    final text = _text.text.trim();
    final hasMedia = _photo != null || _video != null || _voiceBytes != null;

    if (!hasMedia && text.length < 2) {
      setState(() => _error = 'Write a little more so the memory means something.');
      return;
    }
    if (hasMedia && text.length > 1000) {
      setState(() => _error = 'Captions are limited to 1000 characters.');
      return;
    }

    setState(() {
      _busy = true;
      _isUploading = hasMedia;
      _uploadProgress = 0.0;
      _error = null;
    });

    _cancelToken = CancelToken();

    try {
      final repository = ref.read(memoryRepositoryProvider);
      String? mediaUrl;
      String? mediaType;
      String kind = 'text';

      if (_photo != null && _photoBytes != null) {
        kind = 'photo';
        mediaType = _photoType ?? 'image/jpeg';
        mediaUrl = await repository.uploadMedia(
          widget.tripId,
          bytes: _photoBytes!,
          filename: _photo!.name,
          contentType: mediaType,
          onSendProgress: (sent, total) {
            if (total > 0 && mounted) {
              setState(() => _uploadProgress = sent / total);
            }
          },
          cancelToken: _cancelToken,
        );
      } else if (_video != null && _videoBytes != null) {
        kind = 'video';
        mediaType = 'video/mp4';
        mediaUrl = await repository.uploadMedia(
          widget.tripId,
          bytes: _videoBytes!,
          filename: _videoName ?? 'video.mp4',
          contentType: mediaType,
          onSendProgress: (sent, total) {
            if (total > 0 && mounted) {
              setState(() => _uploadProgress = sent / total);
            }
          },
          cancelToken: _cancelToken,
        );
      } else if (_voiceBytes != null) {
        kind = 'voice';
        mediaType = 'audio/wav';
        final voiceName = _voiceFilePath != null
            ? _voiceFilePath!.split(RegExp(r'[\\/]')).last
            : 'voice_note.wav';
        mediaUrl = await repository.uploadMedia(
          widget.tripId,
          bytes: _voiceBytes!,
          filename: voiceName,
          contentType: mediaType,
          onSendProgress: (sent, total) {
            if (total > 0 && mounted) {
              setState(() => _uploadProgress = sent / total);
            }
          },
          cancelToken: _cancelToken,
        );
      }

      await repository.create(
        widget.tripId,
        text: text,
        visibility: _visibility,
        kind: kind,
        caption: hasMedia ? text : null,
        mediaUrl: mediaUrl,
        mediaType: mediaType,
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on DioException catch (dioError) {
      if (!mounted) return;
      if (CancelToken.isCancel(dioError)) {
        setState(() => _error = 'Upload was cancelled.');
      } else {
        setState(() => _error = dioError.message ?? 'Upload network error.');
      }
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Failed to save memory: $error');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _isUploading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.safar;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SafarSheetHeader(
            title: 'Add a memory',
            subtitle: 'Captured now, kept for the trip or just for you.',
          ),

          // Caption / Text field
          TextField(
            controller: _text,
            minLines: 3,
            maxLines: 6,
            maxLength: 4000,
            decoration: InputDecoration(
              hintText: _mediaMode == 'text'
                  ? 'The light on the water, the wrong turn that became the day…'
                  : 'Add a caption or notes (optional)',
              suffixIcon: IconButton(
                tooltip: _isTranscribing ? 'Stop dictation' : 'Dictate with on-device speech recognition',
                icon: Icon(
                  _isTranscribing ? Icons.mic : Icons.mic_none,
                  color: _isTranscribing ? palette.ember : palette.muted,
                ),
                onPressed: _busy ? null : _toggleSpeechRecognition,
              ),
            ),
          ),
          if (_isTranscribing) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.record_voice_over, size: 14, color: palette.ember),
                const SizedBox(width: 6),
                Text('Listening with on-device speech recognition...', style: context.texts.labelSmall?.copyWith(color: palette.ember)),
              ],
            ),
          ],
          const SizedBox(height: 10),

          // Photo Preview
          if (_photoBytes != null) ...[
            Stack(
              alignment: Alignment.topRight,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.memory(
                    _photoBytes!,
                    height: 168,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: CircleAvatar(
                    backgroundColor: Colors.black54,
                    radius: 16,
                    child: IconButton(
                      iconSize: 16,
                      color: Colors.white,
                      icon: const Icon(Icons.close),
                      tooltip: 'Remove photo',
                      onPressed: _busy ? null : () => setState(() {
                        _photo = null;
                        _photoBytes = null;
                        _photoType = null;
                        _mediaMode = 'text';
                      }),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],

          // Video Preview
          if (_videoBytes != null) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: palette.raised,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: palette.line),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: palette.surface,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.videocam_outlined, color: palette.ember, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_videoName ?? 'Selected video', style: context.texts.titleSmall, overflow: TextOverflow.ellipsis),
                        Text('${(_videoBytes!.lengthInBytes / (1024 * 1024)).toStringAsFixed(1)} MB · MP4 Video', style: context.texts.labelSmall?.copyWith(color: palette.muted)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: _busy ? null : () => setState(() {
                      _video = null;
                      _videoBytes = null;
                      _videoName = null;
                      _mediaMode = 'text';
                    }),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],

          // Voice Recording Active or Completed View
          if (_isRecording || _voiceBytes != null) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: palette.raised,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _isRecording ? palette.ember : palette.line),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: _isRecording ? palette.ember.withValues(alpha: 0.15) : palette.surface,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          _isRecording ? Icons.mic : Icons.audiotrack,
                          color: _isRecording ? palette.ember : palette.jade,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _isRecording ? (_isPaused ? 'Recording paused' : 'Recording voice memory...') : 'Voice memory ready',
                              style: context.texts.titleSmall,
                            ),
                            Text(
                              _isRecording
                                  ? '${ref.read(voiceRecorderServiceProvider).recordingDuration.inSeconds}s'
                                  : '${_voiceDuration.inSeconds}s · WAV Audio',
                              style: context.texts.labelSmall?.copyWith(color: palette.muted),
                            ),
                          ],
                        ),
                      ),
                      if (_voiceBytes != null && !_isRecording)
                        IconButton(
                          tooltip: _isPlayingPreview ? 'Stop preview' : 'Play preview',
                          icon: Icon(_isPlayingPreview ? Icons.stop_circle_outlined : Icons.play_circle_outline, size: 28, color: palette.ember),
                          onPressed: _busy ? null : _toggleAudioPreview,
                        ),
                    ],
                  ),
                  if (_isRecording) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _pauseResumeRecording,
                            icon: Icon(_isPaused ? Icons.play_arrow : Icons.pause, size: 18),
                            label: Text(_isPaused ? 'Resume' : 'Pause'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _stopRecording,
                            icon: const Icon(Icons.check, size: 18),
                            label: const Text('Keep audio'),
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton.icon(
                          onPressed: _busy ? null : _cancelRecording,
                          icon: const Icon(Icons.delete_outline, size: 16),
                          label: const Text('Delete and re-record'),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],

          // Media Selection Toolbar
          if (!_isRecording && _photoBytes == null && _videoBytes == null && _voiceBytes == null) ...[
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                OutlinedButton.icon(
                  onPressed: _busy ? null : _choosePhoto,
                  icon: const Icon(Icons.photo_camera_outlined, size: 17),
                  label: const Text('Add photo'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _chooseVideo,
                  icon: const Icon(Icons.videocam_outlined, size: 17),
                  label: const Text('Add video'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _startRecording,
                  icon: const Icon(Icons.mic_none_outlined, size: 17),
                  label: const Text('Record voice'),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],

          // Upload Progress Bar
          if (_isUploading) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _uploadProgress > 0 ? _uploadProgress : null,
                minHeight: 6,
                backgroundColor: palette.raised,
                color: palette.ember,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Uploading media (${(_uploadProgress * 100).toInt()}%)...',
                  style: context.texts.labelSmall?.copyWith(color: palette.muted),
                ),
                TextButton(
                  onPressed: _cancelUpload,
                  child: const Text('Cancel upload'),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],

          // Visibility selector
          const Eyebrow('Who can see it'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('This trip'),
                selected: _visibility == 'trip',
                onSelected: (_) => setState(() => _visibility = 'trip'),
              ),
              ChoiceChip(
                label: const Text('Only me'),
                selected: _visibility == 'private',
                onSelected: (_) => setState(() => _visibility = 'private'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _visibility == 'private'
                ? 'Private memories are visible only to you. They never enter the group travel book.'
                : 'Trip memories can appear in the shared timeline and travel book.',
            style: context.texts.labelSmall,
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            InfoBanner(text: _error!, tone: ChipTone.rose),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: (_busy || _isRecording) ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Keep memory'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Plays voice memory audio in the timeline using audioplayers.
class _VoicePlayer extends StatefulWidget {
  const _VoicePlayer({required this.url});

  final String url;

  @override
  State<_VoicePlayer> createState() => _VoicePlayerState();
}

class _VoicePlayerState extends State<_VoicePlayer> {
  final _player = AudioPlayer();
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  @override
  void initState() {
    super.initState();
    _player.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _isPlaying = state == PlayerState.playing);
    });
    _player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    });
    _player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_isPlaying) {
      await _player.pause();
    } else {
      await _player.play(UrlSource(widget.url));
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.safar;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: palette.raised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.line),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: palette.ember.withValues(alpha: 0.15),
            radius: 20,
            child: IconButton(
              icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow, color: palette.ember),
              onPressed: _toggle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Voice memory', style: context.texts.titleSmall),
                const SizedBox(height: 2),
                Text(
                  '${_position.inSeconds}s / ${_duration.inSeconds > 0 ? '${_duration.inSeconds}s' : 'Audio'}',
                  style: context.texts.labelSmall?.copyWith(color: palette.muted),
                ),
              ],
            ),
          ),
          Icon(Icons.graphic_eq, color: palette.muted, size: 20),
        ],
      ),
    );
  }
}

/// Displays a video memory card in the timeline.
class _VideoCard extends StatelessWidget {
  const _VideoCard({required this.url, required this.memory});

  final String url;
  final Memory memory;

  @override
  Widget build(BuildContext context) {
    final palette = context.safar;

    return Container(
      height: 180,
      width: double.infinity,
      decoration: BoxDecoration(
        color: palette.raised,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.line),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.video_collection_outlined, size: 48, color: palette.ember),
              const SizedBox(height: 8),
              Text(
                memory.caption ?? 'Video Memory',
                style: context.texts.titleSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text('MP4 Video', style: context.texts.labelSmall?.copyWith(color: palette.muted)),
            ],
          ),
          Positioned(
            bottom: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.play_circle_fill, size: 14, color: Colors.white),
                  const SizedBox(width: 4),
                  Text('Video', style: context.texts.labelSmall?.copyWith(color: Colors.white)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
