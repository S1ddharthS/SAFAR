import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/itinerary.dart';
import '../../core/models/trip.dart';
import '../../core/providers.dart';
import '../../core/realtime/live_status_chip.dart';
import '../../core/theme/safar_theme.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/safar_widgets.dart';

class ItineraryScreen extends ConsumerStatefulWidget {
  const ItineraryScreen({super.key, required this.tripId});

  final String tripId;

  @override
  ConsumerState<ItineraryScreen> createState() => _ItineraryScreenState();
}

class _ItineraryScreenState extends ConsumerState<ItineraryScreen> {
  String? _day;
  bool _busy = false;

  Future<void> _refresh() async {
    ref.invalidate(itineraryProvider(widget.tripId));
    ref.invalidate(tripProvider(widget.tripId));
    try {
      await ref.read(itineraryProvider(widget.tripId).future);
    } on Object {
      // AsyncView renders failures.
    }
  }

  Future<void> _addItem(Trip trip, String day) async {
    final formKey = GlobalKey<FormState>();
    final title = TextEditingController();
    final start = TextEditingController(text: '09:00');
    final end = TextEditingController();
    final cost = TextEditingController();
    final notes = TextEditingController();
    var isProtected = false;
    final days = tripDays(trip.startDate, trip.endDate);
    var selectedDay = DateTime.tryParse(day) ?? (days.isEmpty ? DateTime.now() : days.first);

    final submitted = await showSafarSheet<bool>(
      context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SafarSheetHeader(
                  title: 'Add an item',
                  subtitle:
                      'New items are visible to the group and recorded in the change log.',
                ),
                Text('Day', style: context.texts.labelMedium),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final option in days)
                      ChoiceChip(
                        label: Text(formatDateShort(isoDate(option))),
                        selected: isoDate(selectedDay) == isoDate(option),
                        onSelected: (_) =>
                            setSheetState(() => selectedDay = option),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: title,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Title'),
                  validator: (value) =>
                      (value == null || value.trim().length < 2)
                      ? 'Give the item a title'
                      : null,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: start,
                        keyboardType: TextInputType.datetime,
                        decoration: const InputDecoration(
                          labelText: 'Start',
                          hintText: '09:00',
                        ),
                        validator: (value) =>
                            RegExp(r'^\d{2}:\d{2}$').hasMatch(value ?? '')
                            ? null
                            : 'Use HH:MM',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: end,
                        keyboardType: TextInputType.datetime,
                        decoration: const InputDecoration(
                          labelText: 'End (optional)',
                          hintText: '11:00',
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) return null;
                          return RegExp(r'^\d{2}:\d{2}$').hasMatch(value)
                              ? null
                              : 'Use HH:MM';
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: cost,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Estimated cost (optional)',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: notes,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Protected time'),
                  subtitle: const Text(
                    'The engine will not suggest changes to this item.',
                  ),
                  value: isProtected,
                  onChanged: (value) => setSheetState(() => isProtected = value),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(sheetContext).pop(false),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          if (formKey.currentState!.validate()) {
                            Navigator.of(sheetContext).pop(true);
                          }
                        },
                        child: const Text('Add item'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final values = (
      title: title.text.trim(),
      start: start.text.trim(),
      end: end.text.trim(),
      cost: double.tryParse(cost.text.replaceAll(',', '.')),
      notes: notes.text.trim(),
      day: selectedDay,
      protected: isProtected,
    );
    title.dispose();
    start.dispose();
    end.dispose();
    cost.dispose();
    notes.dispose();
    if (submitted != true) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(itineraryRepositoryProvider)
          .addItem(
            widget.tripId,
            day: isoDate(values.day),
            title: values.title,
            startTime: values.start,
            endTime: values.end.isEmpty ? null : values.end,
            notes: values.notes.isEmpty ? null : values.notes,
            costEstimate: values.cost,
            isProtected: values.protected,
          );
      await _refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Item added to the itinerary.')),
      );
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setAttendance(ItineraryItem item, String status) async {
    setState(() => _busy = true);
    try {
      await ref
          .read(itineraryRepositoryProvider)
          .setAttendance(widget.tripId, item.id, status);
      await _refresh();
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editItem(ItineraryItem item, Trip trip) async {
    final title = TextEditingController(text: item.title);
    final start = TextEditingController(text: item.startTime);
    final end = TextEditingController(text: item.endTime ?? '');
    final cost = TextEditingController(
      text: item.costEstimate == 0 ? '' : item.costEstimate.toStringAsFixed(2),
    );
    final notes = TextEditingController(text: item.notes ?? '');
    var isProtected = item.isProtected;
    var selectedDay = item.day;
    final days = tripDays(trip.startDate, trip.endDate);

    final submitted = await showSafarSheet<bool>(
      context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SafarSheetHeader(title: 'Edit item'),
              Text('Day', style: context.texts.labelMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final option in days)
                    ChoiceChip(
                      label: Text(formatDateShort(isoDate(option))),
                      selected: selectedDay == isoDate(option),
                      onSelected: (_) =>
                          setSheetState(() => selectedDay = isoDate(option)),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: title,
                decoration: const InputDecoration(labelText: 'Title'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: start,
                      decoration: const InputDecoration(labelText: 'Start'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: end,
                      decoration: const InputDecoration(labelText: 'End'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: cost,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Estimated cost'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notes,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Notes'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Protected time'),
                value: isProtected,
                onChanged: (value) =>
                    setSheetState(() => isProtected = value),
              ),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(sheetContext).pop(false),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(sheetContext).pop(true),
                      child: const Text('Save'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    final changes = <String, dynamic>{
      'day': selectedDay,
      'start_time': start.text.trim(),
      'title': title.text.trim(),
      'is_protected': isProtected,
      'end_time': end.text.trim().isEmpty ? null : end.text.trim(),
      'notes': notes.text.trim(),
      'cost_estimate':
          double.tryParse(cost.text.replaceAll(',', '.')) ?? 0,
    };
    title.dispose();
    start.dispose();
    end.dispose();
    cost.dispose();
    notes.dispose();
    if (submitted != true) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(itineraryRepositoryProvider)
          .updateItem(widget.tripId, item.id, changes);
      await _refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Item updated.')),
      );
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteItem(ItineraryItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove this item?'),
        content: Text(
          '“${item.title}” will be removed from the confirmed itinerary. '
          'The change is recorded in the trip history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: context.safar.rose,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(itineraryRepositoryProvider)
          .deleteItem(widget.tripId, item.id);
      await _refresh();
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.safar;
    final itinerary = ref.watch(itineraryProvider(widget.tripId));
    final trip = ref.watch(tripProvider(widget.tripId)).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back),
        ),
        title: const Text('Itinerary'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Center(
              child: TripLiveChip(tripId: widget.tripId, compact: true),
            ),
          ),
          IconButton(
            tooltip: 'Group proposals',
            onPressed: () => context.push('/trips/${widget.tripId}/proposals'),
            icon: const Icon(Icons.how_to_vote_outlined),
          ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: itinerary.valueOrNull == null || trip == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _busy
                  ? null
                  : () => _addItem(
                      trip,
                      _day ?? isoDate(DateTime.now()),
                    ),
              icon: const Icon(Icons.add),
              label: const Text('Add item'),
            ),
      body: SafeArea(
        child: AsyncView(
          value: itinerary,
          onRetry: () => ref.invalidate(itineraryProvider(widget.tripId)),
          builder: (data) {
            final days = trip == null
                ? (data.items.map((item) => item.day).toSet().toList()..sort())
                : tripDays(trip.startDate, trip.endDate)
                      .map(isoDate)
                      .toList();
            if (days.isEmpty) {
              return const SafarEmpty(
                title: 'No days to plan',
                message: 'The trip dates are missing.',
                icon: Icons.event_busy_outlined,
              );
            }
            final today = isoDate(DateTime.now());
            final selected = _day ?? (days.contains(today) ? today : days.first);
            final items = data.forDay(selected)
              ..sort((a, b) => a.startTime.compareTo(b.startTime));
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 110),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Eyebrow('Timeline'),
                            const SizedBox(height: 6),
                            Text(
                              '${data.totals.items} items · v${data.confirmedVersion}',
                              style: context.texts.headlineSmall,
                            ),
                          ],
                        ),
                      ),
                      StatusChip(
                        data.myRole,
                        tone: data.myRole == 'owner'
                            ? ChipTone.ember
                            : ChipTone.neutral,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${formatMoney(data.totals.cost, data.totals.currency)} planned · '
                    '${formatMoney(data.totals.perPerson, data.totals.currency)} per person',
                    style: context.texts.bodySmall,
                  ),
                  if (data.openProposals > 0) ...[
                    const SizedBox(height: 12),
                    InfoBanner(
                      text:
                          '${data.openProposals} group ${data.openProposals == 1 ? 'proposal is' : 'proposals are'} waiting for votes. '
                          'The confirmed plan does not change until approval.',
                      icon: Icons.how_to_vote_outlined,
                      tone: ChipTone.ember,
                    ),
                  ],
                  const SizedBox(height: 16),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (var i = 0; i < days.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(
                                'Day ${i + 1} · ${formatDateShort(days[i])}',
                              ),
                              selected: days[i] == selected,
                              onSelected: (_) => setState(() => _day = days[i]),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (items.isEmpty)
                    SafarEmpty(
                      title: 'A clear day',
                      message:
                          'Nothing planned yet. Add an item or use the engine to find group options.',
                      icon: Icons.wb_sunny_outlined,
                      action: trip == null
                          ? null
                          : FilledButton(
                              onPressed: _busy ? null : () => _addItem(trip, selected),
                              child: const Text('Add first item'),
                            ),
                    )
                  else ...[
                    Text(
                      '${formatWeekday(selected)} · ${formatDate(selected)}',
                      style: context.texts.labelMedium,
                    ),
                    const SizedBox(height: 10),
                    for (var index = 0; index < items.length; index++)
                      _TimelineItem(
                        item: items[index],
                        currency: data.totals.currency,
                        isLast: index == items.length - 1,
                        busy: _busy,
                        onAttendance: (status) =>
                            _setAttendance(items[index], status),
                        onEdit: trip == null
                            ? null
                            : () => _editItem(items[index], trip),
                        onDelete: () => _deleteItem(items[index]),
                      ),
                  ],
                  if (data.versions.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    SafarCard(
                      child: Row(
                        children: [
                          Icon(
                            Icons.history,
                            size: 18,
                            color: palette.faint,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '${data.versions.length} recorded version${data.versions.length == 1 ? '' : 's'} · '
                              'latest ${timeAgo(data.versions.first.createdAt)}',
                              style: context.texts.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _TimelineItem extends StatelessWidget {
  const _TimelineItem({
    required this.item,
    required this.currency,
    required this.isLast,
    required this.busy,
    required this.onAttendance,
    required this.onDelete,
    this.onEdit,
  });

  final ItineraryItem item;
  final String currency;
  final bool isLast;
  final bool busy;
  final ValueChanged<String> onAttendance;
  final VoidCallback onDelete;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final palette = context.safar;
    final attendance = item.attendance;
    final mine = attendance?.myStatus ?? 'in';
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 58,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatTime(item.startTime),
                  style: context.texts.labelMedium?.copyWith(color: palette.ink),
                ),
                if (item.endTime != null)
                  Text(
                    formatTime(item.endTime),
                    style: context.texts.labelSmall,
                  ),
              ],
            ),
          ),
          SizedBox(
            width: 22,
            child: Column(
              children: [
                Container(
                  width: 9,
                  height: 9,
                  margin: const EdgeInsets.only(top: 5),
                  decoration: BoxDecoration(
                    color: item.isProtected ? palette.ember : palette.jade,
                    shape: BoxShape.circle,
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(width: 1, color: palette.line),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 6, bottom: 12),
              child: SafarCard(
                padding: const EdgeInsets.all(14),
                radius: 18,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(item.title, style: context.texts.titleSmall),
                        ),
                        if (item.isProtected)
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Icon(
                              Icons.lock_outline,
                              size: 15,
                              color: palette.ember,
                            ),
                          ),
                        PopupMenuButton<String>(
                          tooltip: 'Item options',
                          padding: EdgeInsets.zero,
                          icon: Icon(
                            Icons.more_horiz,
                            size: 18,
                            color: palette.faint,
                          ),
                          onSelected: (value) {
                            if (value == 'edit') onEdit?.call();
                            if (value == 'delete') onDelete();
                          },
                          itemBuilder: (context) => [
                            if (onEdit != null)
                              const PopupMenuItem(
                                value: 'edit',
                                child: Text('Edit'),
                              ),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Text('Remove'),
                            ),
                          ],
                        ),
                      ],
                    ),
                    if (item.notes != null && item.notes!.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(item.notes!, style: context.texts.bodySmall),
                    ],
                    if (item.costEstimate > 0) ...[
                      const SizedBox(height: 6),
                      Text(
                        '${formatMoney(item.costEstimate, currency)} estimated',
                        style: context.texts.labelSmall,
                      ),
                    ],
                    if (attendance != null) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _AttendanceChip(
                            label: 'In ${attendance.inCount}',
                            value: 'in',
                            selected: mine == 'in',
                            busy: busy,
                            onTap: onAttendance,
                          ),
                          const SizedBox(width: 6),
                          _AttendanceChip(
                            label: 'Later ${attendance.joinLaterCount}',
                            value: 'join_later',
                            selected: mine == 'join_later',
                            busy: busy,
                            onTap: onAttendance,
                          ),
                          const SizedBox(width: 6),
                          _AttendanceChip(
                            label: 'Out ${attendance.outCount}',
                            value: 'out',
                            selected: mine == 'out',
                            busy: busy,
                            onTap: onAttendance,
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AttendanceChip extends StatelessWidget {
  const _AttendanceChip({
    required this.label,
    required this.value,
    required this.selected,
    required this.busy,
    required this.onTap,
  });

  final String label;
  final String value;
  final bool selected;
  final bool busy;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.safar;
    return InkWell(
      onTap: busy ? null : () => onTap(value),
      borderRadius: BorderRadius.circular(99),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? palette.emberSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
            color: selected ? palette.ember : palette.line,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? palette.ember : palette.muted,
          ),
        ),
      ),
    );
  }
}
