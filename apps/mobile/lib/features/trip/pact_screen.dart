import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/trip.dart';
import '../../core/providers.dart';
import '../../core/theme/safar_theme.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/safar_widgets.dart';

class PactScreen extends ConsumerWidget {
  const PactScreen({super.key, required this.tripId});

  final String tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pact = ref.watch(pactProvider(tripId));
    final itinerary = ref.watch(itineraryProvider(tripId)).valueOrNull;
    final me = ref.watch(meProvider).valueOrNull;
    final canEdit =
        itinerary?.myRole == 'owner' || itinerary?.myRole == 'admin';

    return Scaffold(
      appBar: AppBar(title: const Text('Journey Pact')),
      body: AsyncView<Pact?>(
        value: pact,
        onRetry: () => ref.invalidate(pactProvider(tripId)),
        skeleton: const SkeletonList(count: 3),
        builder: (data) => _PactEditor(
          key: ValueKey(data?.updatedAt ?? 'new'),
          tripId: tripId,
          pact: data,
          canEdit: canEdit,
          myUserId: me?.user.id,
        ),
      ),
    );
  }
}

class _PactEditor extends ConsumerStatefulWidget {
  const _PactEditor({
    super.key,
    required this.tripId,
    required this.pact,
    required this.canEdit,
    required this.myUserId,
  });

  final String tripId;
  final Pact? pact;
  final bool canEdit;
  final String? myUserId;

  @override
  ConsumerState<_PactEditor> createState() => _PactEditorState();
}

class _PactEditorState extends ConsumerState<_PactEditor> {
  late List<String> _mustDo;
  late List<String> _flexible;
  late List<String> _exceptions;
  late Map<String, String> _times;
  late final TextEditingController _limit;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final pact = widget.pact;
    _mustDo = [...?pact?.mustDo];
    _flexible = [...?pact?.flexible];
    _exceptions = [...?pact?.exceptions];
    _times = {...?pact?.confirmedTimes};
    final own = widget.myUserId == null
        ? null
        : pact?.individualLimits[widget.myUserId];
    _limit = TextEditingController(
      text: own == null ? '' : own.toString(),
    );
  }

  @override
  void dispose() {
    _limit.dispose();
    super.dispose();
  }

  Future<void> _addToList(
    String title,
    String hint,
    List<String> target,
  ) async {
    final controller = TextEditingController();
    final value = await showSafarSheet<String>(
      context,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SafarSheetHeader(title: title, subtitle: hint),
          TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Item'),
            onSubmitted: (text) =>
                Navigator.of(sheetContext).pop(text.trim()),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: () =>
                      Navigator.of(sheetContext).pop(controller.text.trim()),
                  child: const Text('Add'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value.isEmpty) return;
    setState(() => target.add(value));
  }

  Future<void> _addTime() async {
    final label = TextEditingController();
    final time = TextEditingController(text: '09:00');
    final result = await showSafarSheet<(String, String)>(
      context,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SafarSheetHeader(
            title: 'Confirmed time',
            subtitle:
                'Meeting arrangements are shared with the whole trip. '
                'Use a clear label and 24-hour HH:MM.',
          ),
          TextField(
            controller: label,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'What happens',
              hintText: 'Lunch at the market',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: time,
            keyboardType: TextInputType.datetime,
            decoration: const InputDecoration(
              labelText: 'Time (HH:MM)',
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.of(sheetContext).pop(
                    (label.text.trim(), time.text.trim()),
                  ),
                  child: const Text('Add'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    label.dispose();
    time.dispose();
    if (result == null) return;
    final (key, value) = result;
    if (key.isEmpty || !_validTime(value)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Add a label and a valid HH:MM time.')),
        );
      }
      return;
    }
    setState(() => _times[key] = value);
  }

  bool _validTime(String value) =>
      RegExp(r'^[0-2][0-9]:[0-5][0-9]$').hasMatch(value);

  Future<void> _save() async {
    final limitText = _limit.text.trim().replaceAll(',', '.');
    final limit = limitText.isEmpty ? null : double.tryParse(limitText);
    if (limitText.isNotEmpty && (limit == null || limit < 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your limit must be a positive number.')),
      );
      return;
    }
    final invalidTime = _times.entries
        .where((entry) => !_validTime(entry.value))
        .toList();
    if (invalidTime.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Time “${invalidTime.first.key}” must use 24-hour HH:MM.',
          ),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(tripRepositoryProvider)
          .savePact(
            widget.tripId,
            mustDo: _mustDo,
            flexible: _flexible,
            exceptions: _exceptions,
            confirmedTimes: _times,
            individualLimits: limit == null || widget.myUserId == null
                ? const {}
                : {widget.myUserId!: limit},
          );
      ref.invalidate(pactProvider(widget.tripId));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Journey Pact saved.')),
      );
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.safar;
    final pact = widget.pact;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      children: [
        InfoBanner(
          text: pact == null
              ? 'No pact yet. Agree what must happen, what is flexible and '
                    'keep each person’s budget limit private.'
              : 'The pact is the group’s agreement. Editing must-dos or times '
                    'requires an owner or admin; every member can keep a private '
                    'budget limit.',
          icon: Icons.handshake_outlined,
          tone: ChipTone.ember,
        ),
        if (!widget.canEdit) ...[
          const SizedBox(height: 12),
          const InfoBanner(
            text: 'Only owners and admins can change must-dos, flexible items, '
                'times and exceptions. You can still read the pact.',
            icon: Icons.visibility_outlined,
          ),
        ],
        if (pact?.updatedAt != null) ...[
          const SizedBox(height: 10),
          Text(
            'Last updated ${timeAgo(pact!.updatedAt)}',
            style: context.texts.labelSmall,
          ),
        ],
        const SizedBox(height: 20),
        _ListSection(
          title: 'Must-do',
          caption: 'Protected agreements. Removing one needs an exception.',
          items: _mustDo,
          editable: widget.canEdit,
          emptyLabel: 'Nothing is locked in yet.',
          onAdd: () => _addToList(
            'Add a must-do',
            'Something the group agreed must happen.',
            _mustDo,
          ),
          onRemove: (item) => setState(() => _mustDo.remove(item)),
        ),
        const SizedBox(height: 22),
        _ListSection(
          title: 'Flexible',
          caption: 'Nice to have, easy to move or skip.',
          items: _flexible,
          editable: widget.canEdit,
          emptyLabel: 'No flexible items recorded.',
          onAdd: () => _addToList(
            'Add a flexible item',
            'Something the group would enjoy but can change.',
            _flexible,
          ),
          onRemove: (item) => setState(() => _flexible.remove(item)),
        ),
        const SizedBox(height: 22),
        _ListSection(
          title: 'Exceptions',
          caption: 'A must-do may be changed when an exception applies.',
          items: _exceptions,
          editable: widget.canEdit,
          emptyLabel: 'No exceptions.',
          onAdd: () => _addToList(
            'Add an exception',
            'Describe when a must-do may change.',
            _exceptions,
          ),
          onRemove: (item) => setState(() => _exceptions.remove(item)),
        ),
        const SizedBox(height: 22),
        SectionHeader(
          title: 'Confirmed times',
          action: widget.canEdit && _times.isNotEmpty ? 'Add' : null,
          onAction: widget.canEdit ? _addTime : null,
        ),
        const SizedBox(height: 6),
        if (_times.isEmpty)
          Text(
            'No shared timings yet. Meeting points and times appear in the '
            'offline snapshot.',
            style: context.texts.bodySmall,
          )
        else
          for (final entry in _times.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SafarCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                radius: 16,
                child: Row(
                  children: [
                    Icon(
                      Icons.schedule_outlined,
                      size: 18,
                      color: palette.ember,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(entry.key, style: context.texts.titleSmall),
                          Text(
                            formatTime(entry.value),
                            style: context.texts.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    if (widget.canEdit)
                      IconButton(
                        tooltip: 'Remove time',
                        onPressed: () =>
                            setState(() => _times.remove(entry.key)),
                        icon: Icon(
                          Icons.close,
                          size: 18,
                          color: palette.faint,
                        ),
                      ),
                  ],
                ),
              ),
            ),
        if (widget.canEdit) ...[
          const SizedBox(height: 6),
          OutlinedButton.icon(
            onPressed: _addTime,
            icon: const Icon(Icons.add_alarm_outlined, size: 18),
            label: const Text('Add a confirmed time'),
          ),
        ],
        const SizedBox(height: 26),
        SectionHeader(title: 'Your private limit'),
        const SizedBox(height: 6),
        Text(
          'Only you can see this number. It is merged with the pact, never '
          'replaced, and it is never shown to other members.',
          style: context.texts.bodySmall,
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _limit,
          enabled: widget.canEdit && widget.myUserId != null,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Budget limit for this trip',
            prefixIcon: Icon(Icons.lock_outline),
            hintText: 'Leave empty to keep your current limit',
          ),
        ),
        const SizedBox(height: 28),
        if (widget.canEdit)
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined, size: 18),
            label: Text(_saving ? 'Saving…' : 'Save pact'),
          ),
      ],
    );
  }
}

class _ListSection extends StatelessWidget {
  const _ListSection({
    required this.title,
    required this.caption,
    required this.items,
    required this.editable,
    required this.emptyLabel,
    required this.onAdd,
    required this.onRemove,
  });

  final String title;
  final String caption;
  final List<String> items;
  final bool editable;
  final String emptyLabel;
  final VoidCallback onAdd;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    final palette = context.safar;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: title,
          action: editable ? 'Add' : null,
          onAction: editable ? onAdd : null,
        ),
        const SizedBox(height: 4),
        Text(caption, style: context.texts.bodySmall),
        const SizedBox(height: 10),
        if (items.isEmpty)
          Text(emptyLabel, style: context.texts.labelSmall)
        else
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SafarCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                radius: 16,
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 18,
                      color: palette.jade,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(item, style: context.texts.bodyMedium),
                    ),
                    if (editable)
                      IconButton(
                        tooltip: 'Remove',
                        onPressed: () => onRemove(item),
                        icon: Icon(
                          Icons.close,
                          size: 18,
                          color: palette.faint,
                        ),
                      ),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}
