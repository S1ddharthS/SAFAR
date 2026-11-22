import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/ai/image_feature_extractor.dart';
import '../../core/models/memories.dart';
import '../../core/network/api_exception.dart';
import '../../core/providers.dart';
import '../../core/theme/safar_theme.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/safar_widgets.dart';

class StudioScreen extends ConsumerStatefulWidget {
  const StudioScreen({super.key, required this.tripId});

  final String tripId;

  @override
  ConsumerState<StudioScreen> createState() => _StudioScreenState();
}

class _StudioScreenState extends ConsumerState<StudioScreen> {
  bool _busy = false;

  Future<void> _suggest() async {
    setState(() => _busy = true);
    try {
      final created = await ref
          .read(memoryRepositoryProvider)
          .suggestEvents(widget.tripId);
      ref.invalidate(studioProvider(widget.tripId));
      ref.invalidate(replayProvider(widget.tripId));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            created.isEmpty
                ? 'No new memory groups found yet.'
                : '${created.length} suggestion${created.length == 1 ? '' : 's'} awaiting approval.',
          ),
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _approve(StudioEvent event) async {
    setState(() => _busy = true);
    try {
      await ref
          .read(memoryRepositoryProvider)
          .approveEvent(widget.tripId, event.id);
      ref.invalidate(studioProvider(widget.tripId));
      ref.invalidate(replayProvider(widget.tripId));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Memory group approved for the travel book.')),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openVisualSimilaritySheet(List<Memory> memories) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.safar.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => _VisualSimilaritySheet(
        tripId: widget.tripId,
        tripMemories: memories,
      ),
    );
  }

  void _openVoiceDictationSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.safar.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => const _VoiceDictationSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final studio = ref.watch(studioProvider(widget.tripId));
    final palette = context.safar;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Memory Studio'),
        actions: [
          IconButton(
            tooltip: 'Memories',
            onPressed: () => context.push('/trips/${widget.tripId}/memories'),
            icon: const Icon(Icons.photo_library_outlined),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(studioProvider(widget.tripId));
            try {
              await ref.read(studioProvider(widget.tripId).future);
            } on Object {
              // Rendered by AsyncView.
            }
          },
          child: AsyncView(
            value: studio,
            onRetry: () => ref.invalidate(studioProvider(widget.tripId)),
            builder: (data) => ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                const Eyebrow('Quiet intelligence'),
                const SizedBox(height: 8),
                Text('Memory Studio', style: context.texts.headlineLarge),
                const SizedBox(height: 8),
                Text(
                  'Group moments from the memories you already chose to share. Suggested groups '
                  'stay unapproved until a contributor or trip admin confirms them.',
                  style: context.texts.bodySmall?.copyWith(height: 1.5),
                ),
                const SizedBox(height: 16),
                InfoBanner(
                  text: data.disclosure,
                  icon: Icons.info_outline,
                ),
                const SizedBox(height: 16),
                SafarCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Eyebrow('This trip'),
                      const SizedBox(height: 8),
                      Text(
                        '${data.memories.length} memories · ${data.events.length} groups',
                        style: context.texts.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton(
                              onPressed: _busy ? null : _suggest,
                              child: const Text('Suggest groups'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => context.push(
                                '/trips/${widget.tripId}/memories',
                              ),
                              child: const Text('Add memories'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const SectionHeader(
                  eyebrow: 'On-device AI studio',
                  title: 'Visual & voice intelligence',
                ),
                SafarCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.compare_outlined, size: 20, color: palette.ember),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Visual Similarity Matcher',
                              style: context.texts.titleMedium,
                            ),
                          ),
                          StatusChip('128-d Vector', tone: ChipTone.jade),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Extract 128-dimensional perceptual embeddings directly on-device to match '
                        'photos by color temperature, contrast, and spatial gradient distributions '
                        'without sending images to third-party vision APIs.',
                        style: context.texts.bodySmall?.copyWith(height: 1.4),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _openVisualSimilaritySheet(data.memories),
                              icon: const Icon(Icons.photo_filter, size: 18),
                              label: const Text('Match photos'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _openVoiceDictationSheet,
                              icon: const Icon(Icons.mic_none, size: 18),
                              label: const Text('Voice dictation'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const SectionHeader(
                  eyebrow: 'Groups',
                  title: 'Memory events',
                ),
                if (data.events.isEmpty)
                  const SafarEmpty(
                    icon: Icons.auto_awesome_outlined,
                    title: 'No groups yet',
                    message:
                        'Add a few memories, then ask SAFAR to group them by time and place.',
                  )
                else
                  for (final event in data.events)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _EventCard(
                        event: event,
                        busy: _busy,
                        onApprove: () => _approve(event),
                      ),
                    ),
                const SizedBox(height: 20),
                const SectionHeader(
                  eyebrow: 'Active intelligence',
                  title: 'System capabilities',
                ),
                SafarCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'On-Device Android Capabilities',
                        style: context.texts.titleSmall?.copyWith(
                          color: palette.ember,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _CapabilityRow(
                        title: 'Perceptual Image Embeddings',
                        subtitle: '128-d unit feature vectors & cosine distance on-device',
                        active: true,
                        palette: palette,
                      ),
                      _CapabilityRow(
                        title: 'Optical Character Recognition (OCR)',
                        subtitle: 'Google ML Kit Latin text recognition on-device (F17)',
                        active: true,
                        palette: palette,
                      ),
                      _CapabilityRow(
                        title: 'Speech Recognition & Dictation',
                        subtitle: 'On-device Android speech-to-text service (F11/F12)',
                        active: true,
                        palette: palette,
                      ),
                      const Divider(height: 24),
                      Text(
                        'Backend Service Capabilities',
                        style: context.texts.titleSmall?.copyWith(
                          color: palette.ink,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _CapabilityRow(
                        title: 'Event Grouping',
                        subtitle: 'Temporal and spatial proximity clustering',
                        active: true,
                        palette: palette,
                      ),
                      _CapabilityRow(
                        title: 'Caption Grounding',
                        subtitle: 'Recorded metadata & confirmed itinerary cross-referencing',
                        active: true,
                        palette: palette,
                      ),
                      _CapabilityRow(
                        title: 'Cloud Neural Embeddings',
                        subtitle: 'Disabled for privacy (processed locally on-device)',
                        active: false,
                        palette: palette,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CapabilityRow extends StatelessWidget {
  const _CapabilityRow({
    required this.title,
    required this.subtitle,
    required this.active,
    required this.palette,
  });

  final String title;
  final String subtitle;
  final bool active;
  final SafarPalette palette;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            active ? Icons.check_circle_outline : Icons.remove_circle_outline,
            size: 16,
            color: active ? palette.jade : palette.faint,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.texts.titleSmall),
                Text(subtitle, style: context.texts.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({
    required this.event,
    required this.busy,
    required this.onApprove,
  });

  final StudioEvent event;
  final bool busy;
  final VoidCallback onApprove;

  @override
  Widget build(BuildContext context) {
    final approved = event.status == 'approved';
    return SafarCard(
      padding: const EdgeInsets.all(15),
      radius: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(event.title, style: context.texts.titleMedium),
              ),
              StatusChip(
                event.status,
                tone: approved ? ChipTone.jade : ChipTone.ember,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${formatDate(event.startAt)} · ${formatClock(event.startAt)}'
            '${event.memoryIds.isEmpty ? '' : ' · ${event.memoryIds.length} memories'}',
            style: context.texts.bodySmall,
          ),
          if (event.summary != null && event.summary!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(event.summary!, style: context.texts.bodySmall),
          ],
          if (!approved) ...[
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: busy ? null : onApprove,
              child: const Text('Approve group'),
            ),
          ],
        ],
      ),
    );
  }
}

// ==============================================================================
// VISUAL SIMILARITY MODAL SHEET
// ==============================================================================

class _VisualSimilaritySheet extends ConsumerStatefulWidget {
  const _VisualSimilaritySheet({
    required this.tripId,
    required this.tripMemories,
  });

  final String tripId;
  final List<Memory> tripMemories;

  @override
  ConsumerState<_VisualSimilaritySheet> createState() => _VisualSimilaritySheetState();
}

class _VisualSimilaritySheetState extends ConsumerState<_VisualSimilaritySheet> {
  Uint8List? _imageBytesA;
  String? _imageNameA;
  ImageEmbedding? _embeddingA;

  Uint8List? _imageBytesB;
  String? _imageNameB;
  ImageEmbedding? _embeddingB;

  double? _similarityScore;
  bool _calculating = false;

  final ImagePicker _picker = ImagePicker();

  Future<void> _pickImage(bool isSlotA) async {
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 88,
      );
      if (picked == null) return;

      setState(() => _calculating = true);
      final bytes = await picked.readAsBytes();
      final extractor = ref.read(imageFeatureExtractorProvider);
      final embedding = extractor.extract(bytes);

      setState(() {
        if (isSlotA) {
          _imageBytesA = bytes;
          _imageNameA = picked.name;
          _embeddingA = embedding;
        } else {
          _imageBytesB = bytes;
          _imageNameB = picked.name;
          _embeddingB = embedding;
        }

        if (_embeddingA != null && _embeddingB != null) {
          _similarityScore = _embeddingA!.cosineSimilarity(_embeddingB!);
        } else {
          _similarityScore = null;
        }
        _calculating = false;
      });
    } catch (e) {
      if (mounted) setState(() => _calculating = false);
    }
  }

  void _clear() {
    setState(() {
      _imageBytesA = null;
      _imageNameA = null;
      _embeddingA = null;
      _imageBytesB = null;
      _imageNameB = null;
      _embeddingB = null;
      _similarityScore = null;
    });
  }

  String _scoreLabel(double score) {
    if (score >= 0.92) return 'Near Duplicate / Same Framing';
    if (score >= 0.82) return 'Strong Visual & Color Match';
    if (score >= 0.70) return 'Moderate Palette & Scene Match';
    if (score >= 0.55) return 'Subtle Atmosphere Similarity';
    return 'Distinct Visual Scenes';
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.safar;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 28,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Eyebrow('On-device perception'),
                    const SizedBox(height: 4),
                    Text('Visual Similarity Studio', style: context.texts.headlineMedium),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Select two photographs to compute cosine similarity across their 128-dimensional '
            'perceptual feature vectors. Embeddings are calculated locally in pure Dart.',
            style: context.texts.bodySmall?.copyWith(height: 1.4),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _ImageSlot(
                  title: 'Photo A',
                  imageBytes: _imageBytesA,
                  fileName: _imageNameA,
                  embedding: _embeddingA,
                  onPick: () => _pickImage(true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ImageSlot(
                  title: 'Photo B',
                  imageBytes: _imageBytesB,
                  fileName: _imageNameB,
                  embedding: _embeddingB,
                  onPick: () => _pickImage(false),
                ),
              ),
            ],
          ),
          if (_calculating) ...[
            const SizedBox(height: 20),
            const Center(child: CircularProgressIndicator()),
          ] else if (_similarityScore != null) ...[
            const SizedBox(height: 20),
            SafarCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.auto_awesome, color: palette.ember, size: 20),
                      const SizedBox(width: 8),
                      Text('Cosine Similarity Score', style: context.texts.titleMedium),
                      const Spacer(),
                      Text(
                        '${(_similarityScore! * 100).toStringAsFixed(1)}%',
                        style: context.texts.headlineMedium?.copyWith(
                          color: palette.ink,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: _similarityScore!.clamp(0.0, 1.0),
                      minHeight: 8,
                      backgroundColor: palette.faint.withValues(alpha: 0.2),
                      valueColor: AlwaysStoppedAnimation(
                        _similarityScore! >= 0.8
                            ? palette.jade
                            : (_similarityScore! >= 0.65 ? palette.emberSoft : palette.ember),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _scoreLabel(_similarityScore!),
                    style: context.texts.titleSmall?.copyWith(
                      color: palette.ink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Evaluated over 128 normalized feature dimensions covering luminance contrast, '
                    'color temperature, and directional spatial gradients.',
                    style: context.texts.bodySmall,
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              if (_imageBytesA != null || _imageBytesB != null)
                OutlinedButton(
                  onPressed: _clear,
                  child: const Text('Reset'),
                ),
              const Spacer(),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Done'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ImageSlot extends StatelessWidget {
  const _ImageSlot({
    required this.title,
    required this.imageBytes,
    required this.fileName,
    required this.embedding,
    required this.onPick,
  });

  final String title;
  final Uint8List? imageBytes;
  final String? fileName;
  final ImageEmbedding? embedding;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final palette = context.safar;

    return SafarCard(
      padding: const EdgeInsets.all(12),
      radius: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(title, style: context.texts.titleSmall),
              const Spacer(),
              if (embedding != null)
                Icon(Icons.check_circle, size: 14, color: palette.jade),
            ],
          ),
          const SizedBox(height: 8),
          if (imageBytes != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.memory(
                imageBytes!,
                height: 110,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              fileName ?? 'Selected image',
              style: context.texts.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            InkWell(
              onTap: onPick,
              child: Text(
                'Replace',
                style: context.texts.bodySmall?.copyWith(
                  color: palette.ember,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ] else ...[
            InkWell(
              onTap: onPick,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                height: 110,
                width: double.infinity,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: palette.faint.withValues(alpha: 0.4),
                    style: BorderStyle.solid,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_photo_alternate_outlined, color: palette.muted, size: 28),
                    const SizedBox(height: 6),
                    Text(
                      'Select image',
                      style: context.texts.bodySmall?.copyWith(color: palette.muted),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ==============================================================================
// VOICE DICTATION MODAL SHEET
// ==============================================================================

class _VoiceDictationSheet extends ConsumerStatefulWidget {
  const _VoiceDictationSheet();

  @override
  ConsumerState<_VoiceDictationSheet> createState() => _VoiceDictationSheetState();
}

class _VoiceDictationSheetState extends ConsumerState<_VoiceDictationSheet> {
  bool _isListening = false;
  String _recognizedText = '';
  String? _statusMessage;

  Future<void> _toggleListen() async {
    final transcriber = ref.read(speechTranscriberProvider);
    if (_isListening) {
      await transcriber.stopListening();
      setState(() {
        _isListening = false;
        _statusMessage = 'Dictation completed.';
      });
      return;
    }

    final available = await transcriber.initialize();
    if (!available) {
      setState(() {
        _statusMessage = 'Speech recognition unavailable or microphone denied.';
      });
      return;
    }

    setState(() {
      _isListening = true;
      _statusMessage = 'Listening... Speak clearly into your device.';
    });

    await transcriber.startListening(
      onText: (text) {
        if (mounted) {
          setState(() {
            _recognizedText = text;
          });
        }
      },
    );
  }

  @override
  void dispose() {
    ref.read(speechTranscriberProvider).stopListening();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.safar;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 28,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Eyebrow('On-device speech'),
                    const SizedBox(height: 4),
                    Text('Voice Dictation Studio', style: context.texts.headlineMedium),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Dictate journey thoughts or test on-device speech-to-text recognition directly. '
            'Transcription is performed locally on Android.',
            style: context.texts.bodySmall?.copyWith(height: 1.4),
          ),
          const SizedBox(height: 16),
          Center(
            child: GestureDetector(
              onTap: _toggleListen,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isListening ? palette.ember : palette.ink,
                  boxShadow: _isListening
                      ? [
                          BoxShadow(
                            color: palette.ember.withValues(alpha: 0.4),
                            blurRadius: 18,
                            spreadRadius: 4,
                          ),
                        ]
                      : null,
                ),
                child: Icon(
                  _isListening ? Icons.stop : Icons.mic,
                  color: Colors.white,
                  size: 32,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_statusMessage != null)
            Center(
              child: Text(
                _statusMessage!,
                style: context.texts.bodySmall?.copyWith(
                  color: _isListening ? palette.ember : palette.muted,
                  fontWeight: _isListening ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 80),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: palette.faint.withValues(alpha: 0.3)),
            ),
            child: Text(
              _recognizedText.isEmpty ? 'Transcribed speech will appear here...' : _recognizedText,
              style: context.texts.bodyMedium?.copyWith(
                color: _recognizedText.isEmpty ? palette.faint : palette.ink,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ),
        ],
      ),
    );
  }
}
