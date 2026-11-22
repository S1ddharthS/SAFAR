import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/models/inspirations.dart';
import '../../core/network/api_exception.dart';
import '../../core/providers.dart';
import '../../core/theme/safar_theme.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/safar_widgets.dart';

class ImportScreen extends ConsumerStatefulWidget {
  const ImportScreen({super.key, required this.tripId});

  final String tripId;

  @override
  ConsumerState<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends ConsumerState<ImportScreen> {
  bool _busy = false;

  Future<void> _add() async {
    final created = await showSafarSheet<bool>(
      context,
      builder: (_) => _ImportSheet(tripId: widget.tripId),
    );
    if (created == true) ref.invalidate(inspirationsProvider(widget.tripId));
  }

  Future<void> _review(
    InspirationItem item,
    InspirationCandidate candidate,
    String decision,
  ) async {
    final candidateId = candidate.candidateId ?? candidate.id;
    if (candidateId == null || candidateId.isEmpty) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(inspirationRepositoryProvider)
          .review(
            widget.tripId,
            item.id,
            candidateId: candidateId,
            decision: decision,
          );
      ref.invalidate(inspirationsProvider(widget.tripId));
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
    final inspirations = ref.watch(inspirationsProvider(widget.tripId));
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text('Import'),
      ),
      appBar: AppBar(
        title: const Text('Dream Import'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(inspirationsProvider(widget.tripId)),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(inspirationsProvider(widget.tripId));
            try {
              await ref.read(inspirationsProvider(widget.tripId).future);
            } on Object {
              // Rendered by AsyncView.
            }
          },
          child: AsyncView(
            value: inspirations,
            onRetry: () => ref.invalidate(inspirationsProvider(widget.tripId)),
            builder: (items) {
              if (items.isEmpty) {
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    const SizedBox(height: 40),
                    SafarEmpty(
                      icon: Icons.auto_awesome_outlined,
                      title: 'Turn inspiration into a plan',
                      message:
                          'Paste a note, article or link. SAFAR extracts candidate places and '
                          'activities with confidence and evidence for you to review.',
                      action: FilledButton(
                        onPressed: _add,
                        child: const Text('Import something'),
                      ),
                    ),
                  ],
                );
              }
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
                children: [
                  const Eyebrow('Dream Import'),
                  const SizedBox(height: 8),
                  Text('Ideas, with evidence.', style: context.texts.headlineLarge),
                  const SizedBox(height: 8),
                  Text(
                    'Extraction is grounded in the SAFAR catalog. Candidates are suggestions only; '
                    'review each one before it reaches a proposal.',
                    style: context.texts.bodySmall?.copyWith(height: 1.5),
                  ),
                  const SizedBox(height: 18),
                  for (final item in items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: _InspirationCard(
                        item: item,
                        busy: _busy,
                        onReview: (candidate, decision) =>
                            _review(item, candidate, decision),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _InspirationCard extends StatelessWidget {
  const _InspirationCard({
    required this.item,
    required this.busy,
    required this.onReview,
  });

  final InspirationItem item;
  final bool busy;
  final void Function(InspirationCandidate, String) onReview;

  @override
  Widget build(BuildContext context) {
    final palette = context.safar;
    final extraction = item.extracted;
    final link = extraction.link;
    return SafarCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StatusChip(item.sourceType, tone: ChipTone.neutral),
              const SizedBox(width: 8),
              StatusChip(
                item.status,
                tone: item.status == 'reviewed'
                    ? ChipTone.jade
                    : item.status == 'rejected'
                    ? ChipTone.rose
                    : ChipTone.ember,
              ),
              const Spacer(),
              Text(timeAgo(item.createdAt), style: context.texts.labelSmall),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            link?.title ?? item.content,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: context.texts.titleMedium,
          ),
          if (link?.description != null) ...[
            const SizedBox(height: 6),
            Text(
              link!.description!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.texts.bodySmall,
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (extraction.matches.isNotEmpty)
                StatusChip(
                  '${extraction.matches.length} candidates',
                  tone: ChipTone.ember,
                ),
              if (extraction.pending > 0)
                StatusChip('${extraction.pending} pending', tone: ChipTone.ember),
              if (extraction.accepted > 0)
                StatusChip('${extraction.accepted} accepted', tone: ChipTone.jade),
              if (extraction.rejected > 0)
                StatusChip('${extraction.rejected} rejected', tone: ChipTone.rose),
              for (final host in extraction.sourceHosts.take(3))
                StatusChip(host, tone: ChipTone.neutral, icon: Icons.link),
              for (final tag in extraction.hashtags.take(4))
                StatusChip('#$tag', tone: ChipTone.neutral),
            ],
          ),
          if (extraction.providers.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final provider in extraction.providers)
                  Tooltip(
                    message: [
                      provider.provenance,
                      if (provider.message != null) provider.message!,
                      if (provider.error != null) provider.error!,
                    ].join(' · '),
                    child: StatusChip(
                      '${provider.provider} ${provider.ok ? '· ok' : '· unavailable'}',
                      tone: provider.ok ? ChipTone.jade : ChipTone.neutral,
                    ),
                  ),
              ],
            ),
          ],
          if (extraction.ocr != null) ...[
            const SizedBox(height: 10),
            Text(
              extraction.ocr!.available
                  ? 'Text read from image · ${extraction.ocr!.characters} characters'
                  : 'Image text recognition is not configured on this deployment.',
              style: context.texts.labelSmall,
            ),
          ],
          const SizedBox(height: 14),
          for (final candidate in extraction.matches)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: palette.raised,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: palette.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          candidate.name,
                          style: context.texts.titleSmall,
                        ),
                      ),
                      StatusChip(
                        '${(candidate.confidence * 100).round()}% match',
                        tone: candidate.confidence >= 0.7
                            ? ChipTone.jade
                            : ChipTone.ember,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      candidate.kind ?? candidate.type,
                      if (candidate.provenance != null) candidate.provenance!,
                      if (candidate.verified) 'verified',
                      if (candidate.decision != 'pending') candidate.decision,
                    ].join(' · '),
                    style: context.texts.labelSmall,
                  ),
                  if (candidate.evidence.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(candidate.evidence, style: context.texts.bodySmall),
                  ],
                  if (candidate.sourceSpan != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '“${candidate.sourceSpan}”',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.texts.labelSmall?.copyWith(
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                  if (candidate.decision == 'pending') ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: busy
                                ? null
                                : () => onReview(candidate, 'reject'),
                            child: const Text('Reject'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton(
                            onPressed: busy
                                ? null
                                : () => onReview(candidate, 'accept'),
                            child: const Text('Accept'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          if (extraction.notes.isNotEmpty) ...[
            const SizedBox(height: 4),
            for (final note in extraction.notes)
              Text('· $note', style: context.texts.labelSmall),
          ],
          if (extraction.limitations.isNotEmpty) ...[
            const SizedBox(height: 10),
            InfoBanner(
              text: extraction.limitations.join(' '),
              icon: Icons.info_outline,
            ),
          ],
        ],
      ),
    );
  }
}

class _ImportSheet extends ConsumerStatefulWidget {
  const _ImportSheet({required this.tripId});

  final String tripId;

  @override
  ConsumerState<_ImportSheet> createState() => _ImportSheetState();
}

class _ImportSheetState extends ConsumerState<_ImportSheet> {
  final _content = TextEditingController();
  final _picker = ImagePicker();
  String _sourceType = 'text';
  bool _busy = false;
  String? _error;

  XFile? _imageFile;
  Uint8List? _imageBytes;
  bool _ocrScanning = false;
  String? _ocrStatus;

  @override
  void dispose() {
    _content.dispose();
    super.dispose();
  }

  Future<void> _chooseImage(ImageSource source) async {
    try {
      final file = await _picker.pickImage(
        source: source,
        maxWidth: 2048,
        imageQuality: 85,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (bytes.lengthInBytes > 25 * 1024 * 1024) {
        if (!mounted) return;
        setState(() => _error = 'Images are limited to 25 MB.');
        return;
      }

      setState(() {
        _imageFile = file;
        _imageBytes = bytes;
        _ocrScanning = true;
        _ocrStatus = 'Scanning image with on-device OCR...';
        _error = null;
      });

      // Run on-device OCR
      final ocrService = ref.read(ocrServiceProvider);
      final result = await ocrService.extractText(File(file.path));

      if (!mounted) return;
      setState(() {
        _ocrScanning = false;
        if (result.hasText) {
          final prefix = _content.text.trim().isEmpty ? '' : '${_content.text.trim()}\n\n';
          _content.text = '$prefix${result.text}';
          _ocrStatus = 'Read ${result.linesCount} lines (${result.text.length} characters) via on-device OCR.';
        } else {
          _ocrStatus = result.error ?? 'No readable text detected in this image. You can type notes manually below.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _ocrScanning = false;
        _error = 'Could not access or process the selected image: $e';
      });
    }
  }

  void _clearImage() {
    setState(() {
      _imageFile = null;
      _imageBytes = null;
      _ocrScanning = false;
      _ocrStatus = null;
    });
  }

  Future<void> _submit() async {
    final content = _content.text.trim();
    if (_sourceType != 'image' && content.length < 2) {
      setState(() => _error = 'Add at least a couple of words to import.');
      return;
    }
    if (_sourceType == 'image' && _imageFile == null && content.length < 2) {
      setState(() => _error = 'Select an image or write notes to import.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      String? mediaUrl;
      if (_sourceType == 'image' && _imageFile != null && _imageBytes != null) {
        // Upload the image so it's safely attached to the trip
        mediaUrl = await ref.read(memoryRepositoryProvider).uploadMedia(
          widget.tripId,
          bytes: _imageBytes!,
          filename: _imageFile!.name,
          contentType: _imageFile!.mimeType ?? 'image/jpeg',
        );
      }

      await ref.read(inspirationRepositoryProvider).create(
        widget.tripId,
        content: content.isEmpty ? 'Uploaded itinerary image' : content,
        sourceType: _sourceType == 'image' ? 'image_url' : _sourceType,
        mediaUrl: mediaUrl,
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Failed to import inspiration: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
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
            title: 'Import inspiration',
            subtitle:
                'Paste a note, link, or scan an image with on-device OCR. SAFAR extracts '
                'catalog candidates — nothing is added until you review it.',
          ),
          Wrap(
            spacing: 8,
            children: [
              for (final (type, label) in const [
                ('text', 'Note'),
                ('link', 'Link'),
                ('image', 'Image & OCR'),
              ])
                ChoiceChip(
                  label: Text(label),
                  selected: _sourceType == type,
                  onSelected: (_) => setState(() {
                    _sourceType = type;
                    _error = null;
                  }),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // Image & OCR Section
          if (_sourceType == 'image') ...[
            if (_imageBytes != null) ...[
              Stack(
                alignment: Alignment.topRight,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      height: 160,
                      width: double.infinity,
                      color: palette.surface,
                      child: Image.memory(
                        _imageBytes!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => const Center(
                          child: Icon(Icons.broken_image_outlined, size: 40),
                        ),
                      ),
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
                        tooltip: 'Remove image',
                        onPressed: _busy ? null : _clearImage,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _imageFile?.name ?? 'Selected image',
                      style: context.texts.labelSmall?.copyWith(color: palette.muted),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _chooseImage(ImageSource.gallery),
                    icon: const Icon(Icons.autorenew_rounded, size: 16),
                    label: const Text('Replace'),
                  ),
                ],
              ),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : () => _chooseImage(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library_outlined, size: 18),
                      label: const Text('Choose photo'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : () => _chooseImage(ImageSource.camera),
                      icon: const Icon(Icons.camera_alt_outlined, size: 18),
                      label: const Text('Take photo'),
                    ),
                  ),
                ],
              ),
            ],

            if (_ocrScanning) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text('Reading text with on-device OCR...', style: context.texts.labelSmall),
                ],
              ),
            ] else if (_ocrStatus != null) ...[
              const SizedBox(height: 8),
              InfoBanner(
                text: _ocrStatus!,
                icon: Icons.document_scanner_outlined,
                tone: ChipTone.jade,
              ),
            ],
            const SizedBox(height: 12),
          ],

          TextField(
            controller: _content,
            minLines: 4,
            maxLines: 8,
            maxLength: 4000,
            decoration: InputDecoration(
              hintText: _sourceType == 'link'
                  ? 'https://…'
                  : _sourceType == 'image'
                      ? 'Extracted text appears here. You can review, edit, or add instructions...'
                      : 'e.g. A quiet ceramics workshop near the river, open Thursdays',
            ),
          ),
          if (_sourceType == 'link') ...[
            const SizedBox(height: 2),
            Text(
              'Only public page metadata and text are used. No paid providers are enabled on this deployment.',
              style: context.texts.labelSmall,
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 10),
            InfoBanner(text: _error!, tone: ChipTone.rose),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: (_busy || _ocrScanning) ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Extract candidates'),
            ),
          ),
        ],
      ),
    );
  }
}
