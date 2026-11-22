import 'dart:typed_data';

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
  XFile? _photo;
  Uint8List? _photoBytes;
  String? _photoType;

  static const _maxPhotoBytes = 25 * 1024 * 1024;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

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
        maxWidth: 1600,
        imageQuality: 82,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (bytes.lengthInBytes > _maxPhotoBytes) {
        if (!mounted) return;
        setState(() => _error = 'Photos are limited to 25 MB.');
        return;
      }
      if (!mounted) return;
      setState(() {
        _photo = file;
        _photoBytes = bytes;
        _photoType = _mimeFor(file);
        _error = null;
      });
    } on Object {
      if (!mounted) return;
      setState(
        () => _error = 'The photo picker is not available on this device.',
      );
    }
  }

  static String _mimeFor(XFile file) {
    final declared = file.mimeType;
    if (declared != null && declared.startsWith('image/')) return declared;
    final name = file.name.toLowerCase();
    if (name.endsWith('.png')) return 'image/png';
    if (name.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  Future<void> _submit() async {
    final text = _text.text.trim();
    final photo = _photo;
    if (photo == null && text.length < 2) {
      setState(() => _error = 'Write a little more so the memory means something.');
      return;
    }
    if (photo != null && text.length > 1000) {
      setState(() => _error = 'Photo captions are limited to 1000 characters.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repository = ref.read(memoryRepositoryProvider);
      String? mediaUrl;
      String? mediaType;
      if (photo != null) {
        mediaUrl = await repository.uploadMedia(
          widget.tripId,
          bytes: _photoBytes!,
          filename: photo.name,
          contentType: _photoType ?? 'image/jpeg',
        );
        mediaType = _photoType ?? 'image/jpeg';
      }
      await repository.create(
        widget.tripId,
        text: text,
        visibility: _visibility,
        kind: photo == null ? 'text' : 'photo',
        caption: photo == null ? null : text,
        mediaUrl: mediaUrl,
        mediaType: mediaType,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SafarSheetHeader(
            title: 'Add a memory',
            subtitle: 'Captured now, kept for the trip or just for you.',
          ),
          TextField(
            controller: _text,
            minLines: 4,
            maxLines: 8,
            maxLength: 4000,
            autofocus: _photo == null,
            decoration: InputDecoration(
              hintText: _photo == null
                  ? 'The light on the water, the wrong turn that became the day…'
                  : 'Add a caption (optional)',
            ),
          ),
          const SizedBox(height: 6),
          if (_photoBytes != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.memory(
                _photoBytes!,
                height: 168,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 8),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: _busy ? null : _choosePhoto,
                icon: Icon(
                  _photo == null
                      ? Icons.add_a_photo_outlined
                      : Icons.autorenew_rounded,
                  size: 17,
                ),
                label: Text(_photo == null ? 'Add photo' : 'Replace photo'),
              ),
              if (_photo != null)
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                          _photo = null;
                          _photoBytes = null;
                          _photoType = null;
                        }),
                  child: const Text('Remove'),
                ),
            ],
          ),
          const SizedBox(height: 6),
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
              onPressed: _busy ? null : _submit,
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
