import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/discovery.dart';
import '../../core/models/itinerary.dart';
import '../../core/models/planning.dart';
import '../../core/models/trip.dart';
import '../../core/providers.dart';
import '../../core/theme/safar_theme.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/safar_widgets.dart';
import 'pulse_screen.dart' show formatDayLabel;
import 'widgets/activity_search.dart';

class PlanIntelligenceScreen extends StatelessWidget {
  const PlanIntelligenceScreen({super.key, required this.tripId});

  final String tripId;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Plan intelligence'),
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Effort'),
              Tab(text: 'Fragility'),
              Tab(text: 'Domino'),
              Tab(text: 'Backups'),
              Tab(text: 'Capsules'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _EffortTab(tripId: tripId),
            _FragilityTab(tripId: tripId),
            _DominoTab(tripId: tripId),
            _BackupsTab(tripId: tripId),
            _CapsulesTab(tripId: tripId),
          ],
        ),
      ),
    );
  }
}

const _pad = EdgeInsets.fromLTRB(20, 14, 20, 34);

class _EffortTab extends ConsumerWidget {
  const _EffortTab({required this.tripId});

  final String tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncView<EffortBudget>(
      value: ref.watch(effortProvider(tripId)),
      onRetry: () => ref.invalidate(effortProvider(tripId)),
      padding: _pad,
      skeleton: const SkeletonList(count: 4, itemHeight: 76),
      builder: (effort) => ListView(
        padding: _pad,
        children: [
          const InfoBanner(
            text:
                'Estimates computed from the confirmed plan. Exhaustion is a '
                'budget, not a rule — nothing here changes the itinerary.',
            icon: Icons.battery_charging_full,
          ),
          const SizedBox(height: 16),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.7,
            children: [
              StatTile(
                label: 'Effort',
                value: titleCase(effort.effortLevel),
                hint: '${effort.effortPoints} points',
                icon: Icons.local_fire_department_outlined,
              ),
              StatTile(
                label: 'Walking',
                value: '${effort.walkingKmEstimate.toStringAsFixed(1)} km',
                hint: '${effort.walkingMinutesEstimate} min on foot',
                icon: Icons.directions_walk,
              ),
              StatTile(
                label: 'Transitions',
                value: '${effort.transitions}',
                hint: 'Between confirmed stops',
                icon: Icons.alt_route,
              ),
              StatTile(
                label: 'Protected rest',
                value: '${effort.protectedRestMinutes} min',
                hint: 'Kept aside for recovery',
                icon: Icons.self_improvement,
              ),
            ],
          ),
          const SizedBox(height: 18),
          const SectionHeader(eyebrow: 'Conditions', title: 'Heat & access'),
          SafarCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _LabeledLine(
                  label: 'Heat exposure',
                  value: titleCase(effort.heatExposure),
                ),
                const SizedBox(height: 8),
                _LabeledLine(
                  label: 'Accessibility',
                  value: effort.accessibilityNote.isEmpty
                      ? 'No accessibility note recorded.'
                      : effort.accessibilityNote,
                ),
              ],
            ),
          ),
          if (effort.disclosure.isNotEmpty) ...[
            const SizedBox(height: 12),
            SourceLabel(source: effort.disclosure),
          ],
        ],
      ),
    );
  }
}

class _FragilityTab extends ConsumerWidget {
  const _FragilityTab({required this.tripId});

  final String tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.safar;
    return AsyncView<FragilityReport>(
      value: ref.watch(fragilityProvider(tripId)),
      onRetry: () => ref.invalidate(fragilityProvider(tripId)),
      padding: _pad,
      skeleton: const SkeletonList(count: 3, itemHeight: 92),
      builder: (report) {
        if (report.days.isEmpty) {
          return const Padding(
            padding: _pad,
            child: SafarEmpty(
              icon: Icons.hourglass_empty,
              title: 'Nothing to test yet',
              message:
                  'Fragility looks at confirmed stops and their buffers. Add '
                  'items to the plan first.',
            ),
          );
        }
        return ListView(
          padding: _pad,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(report.label, style: context.texts.titleMedium),
                ),
                if (report.resilienceScore != null)
                  StatusChip(
                    'Resilience ${report.resilienceScore}%',
                    tone: report.resilienceScore! >= 70
                        ? ChipTone.jade
                        : report.resilienceScore! >= 40
                        ? ChipTone.ember
                        : ChipTone.rose,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                StatusChip('${report.comfortable} comfortable',
                    tone: ChipTone.jade),
                StatusChip('${report.tight} tight', tone: ChipTone.ember),
                StatusChip('${report.risky} risky', tone: ChipTone.rose),
              ],
            ),
            const SizedBox(height: 16),
            for (final day in report.days) ...[
              SafarCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Eyebrow(formatDayLabel(day.day), color: palette.ember),
                    const SizedBox(height: 10),
                    for (final leg in day.legs)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    leg.title,
                                    style: context.texts.titleSmall,
                                  ),
                                ),
                                StatusChip(
                                  leg.bufferStatus,
                                  tone: switch (leg.bufferStatus) {
                                    'risky' => ChipTone.rose,
                                    'tight' => ChipTone.ember,
                                    _ => ChipTone.jade,
                                  },
                                ),
                                if (leg.protected) ...[
                                  const SizedBox(width: 6),
                                  const StatusChip(
                                    'Protected',
                                    tone: ChipTone.neutral,
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${formatTime(leg.startTime)}–${formatTime(leg.endTime)}'
                              ' · ${leg.travelMinutes} min travel'
                              ' · ${leg.travelKm.toStringAsFixed(1)} km'
                              '${leg.bufferMinutes == null ? '' : ' · ${leg.bufferMinutes} min buffer'}',
                              style: context.texts.labelSmall,
                            ),
                          ],
                        ),
                      ),
                    if (day.alternativeTimings.isNotEmpty) ...[
                      Divider(color: palette.line, height: 1),
                      const SizedBox(height: 8),
                      const Eyebrow('Safer timings'),
                      const SizedBox(height: 6),
                      for (final timing in day.alternativeTimings)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            '• ${timing.suggestion} (+${timing.minutes} min)',
                            style: context.texts.bodySmall,
                          ),
                        ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (report.disclosure != null && report.disclosure!.isNotEmpty)
              SourceLabel(source: report.disclosure!),
          ],
        );
      },
    );
  }
}

class _DominoTab extends ConsumerStatefulWidget {
  const _DominoTab({required this.tripId});

  final String tripId;

  @override
  ConsumerState<_DominoTab> createState() => _DominoTabState();
}

class _DominoTabState extends ConsumerState<_DominoTab> {
  static const _delays = [15, 30, 45, 60, 90];

  String? _itemId;
  int _delay = 45;
  DominoMap? _map;
  bool _busy = false;

  Future<void> _simulate() async {
    final itemId = _itemId;
    if (itemId == null) return;
    setState(() => _busy = true);
    try {
      final map = await ref
          .read(itineraryRepositoryProvider)
          .domino(widget.tripId, itemId: itemId, delayMinutes: _delay);
      if (!mounted) return;
      setState(() => _map = map);
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
    final itinerary = ref.watch(itineraryProvider(widget.tripId)).valueOrNull;
    final items = itinerary?.items.where((item) => !item.cancelled).toList() ??
        const <ItineraryItem>[];
    if (items.isEmpty) {
      return const SafarEmpty(
        icon: Icons.dynamic_feed_outlined,
        title: 'No confirmed items',
        message:
            'Domino simulates knock-on delays on the confirmed plan. Add items '
            'first.',
      );
    }
    final selected = items.any((item) => item.id == _itemId)
        ? _itemId
        : items.first.id;
    final map = _map;
    return ListView(
      padding: _pad,
      children: [
        const InfoBanner(
          text:
              'Hypothetical only: simulate a delay to see which later stops '
              'slip and what a minimal repair would be.',
          icon: Icons.schedule,
        ),
        const SizedBox(height: 16),
        Text('If this item runs late', style: context.texts.labelMedium),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: selected,
          isExpanded: true,
          items: [
            for (final item in items)
              DropdownMenuItem(
                value: item.id,
                child: Text(
                  '${formatDateShort(item.day)} · ${item.title}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (value) => setState(() {
            _itemId = value;
            _map = null;
          }),
        ),
        const SizedBox(height: 14),
        Text('Delay', style: context.texts.labelMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final delay in _delays)
              ChoiceChip(
                label: Text('$delay min'),
                selected: _delay == delay,
                onSelected: (_) => setState(() {
                  _delay = delay;
                  _map = null;
                }),
              ),
          ],
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _busy ? null : _simulate,
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.dynamic_feed, size: 18),
          label: const Text('Simulate delay'),
        ),
        if (map != null) ...[
          const SizedBox(height: 22),
          SafarCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Eyebrow(
                  'Domino · ${formatDate(map.day)}',
                  color: palette.ember,
                ),
                const SizedBox(height: 8),
                Text(
                  '${map.disruptionTitle} delayed ${map.delayMinutes} min',
                  style: context.texts.titleSmall,
                ),
                const SizedBox(height: 12),
                if (map.affected.isEmpty)
                  Text(
                    'Nothing else slips — this day has enough buffer.',
                    style: context.texts.bodySmall,
                  )
                else
                  for (final item in map.affected)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Icon(
                            item.isSource
                                ? Icons.warning_amber_rounded
                                : Icons.arrow_downward,
                            size: 15,
                            color: item.isSource ? palette.ember : palette.muted,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '${item.title} · new start ${formatTime(item.newStart)}'
                              ' (+${item.slipMinutes} min)',
                              style: context.texts.bodySmall,
                            ),
                          ),
                          if (item.protected)
                            const StatusChip('Protected', tone: ChipTone.rose),
                        ],
                      ),
                    ),
                if (map.unaffected.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Divider(color: palette.line, height: 1),
                  const SizedBox(height: 8),
                  const Eyebrow('Unaffected'),
                  const SizedBox(height: 6),
                  for (final item in map.unaffected)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '• ${item.title} — ${item.reason}',
                        style: context.texts.labelSmall,
                      ),
                    ),
                ],
                const SizedBox(height: 12),
                Text(
                  map.minimumRepairsNeeded == 1
                      ? 'One repair keeps every protected stop intact.'
                      : '${map.minimumRepairsNeeded} repairs keep every '
                            'protected stop intact.',
                  style: context.texts.labelMedium,
                ),
                const SizedBox(height: 8),
                for (final repair in map.repairOptions)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(repair.title, style: context.texts.titleSmall),
                        for (final option in repair.options)
                          Padding(
                            padding: const EdgeInsets.only(left: 12, top: 2),
                            child: Text(
                              '– $option',
                              style: context.texts.labelSmall,
                            ),
                          ),
                      ],
                    ),
                  ),
                if (map.disclosure.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  SourceLabel(source: map.disclosure),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _BackupsTab extends ConsumerStatefulWidget {
  const _BackupsTab({required this.tripId});

  final String tripId;

  @override
  ConsumerState<_BackupsTab> createState() => _BackupsTabState();
}

class _BackupsTabState extends ConsumerState<_BackupsTab> {
  bool _busy = false;

  Future<void> _addBackup(List<ItineraryItem> items) async {
    String? itemId = items.first.id;
    Activity? backup;
    final notes = TextEditingController();
    final submitted = await showSafarSheet<bool>(
      context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final trip = ref.read(tripProvider(widget.tripId)).valueOrNull;
          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SafarSheetHeader(
                  title: 'Add a backup',
                  subtitle:
                      'If the chosen plan item fails, this backup stands ready. '
                      'Nothing is added to the confirmed plan.',
                ),
                DropdownButtonFormField<String>(
                  initialValue: itemId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'If this fails'),
                  items: [
                    for (final item in items)
                      DropdownMenuItem(
                        value: item.id,
                        child: Text(
                          '${formatDateShort(item.day)} · ${item.title}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) => setSheetState(() => itemId = value),
                ),
                const SizedBox(height: 14),
                Text('Use this backup', style: context.texts.labelMedium),
                const SizedBox(height: 8),
                ActivitySearchList(
                  destinationId: trip?.destinationId,
                  trailing: (activity) => Icon(
                    backup?.id == activity.id
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    size: 20,
                    color: backup?.id == activity.id
                        ? context.safar.jade
                        : context.safar.faint,
                  ),
                  onTap: (activity) => setSheetState(() => backup = activity),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notes,
                  maxLines: 2,
                  maxLength: 500,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () =>
                            Navigator.of(sheetContext).pop(false),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: () =>
                            Navigator.of(sheetContext).pop(true),
                        child: const Text('Save backup'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
    final note = notes.text.trim();
    notes.dispose();
    if (submitted != true) return;
    if (itemId == null || backup == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Choose both the plan item and a backup activity.'),
        ),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(itineraryRepositoryProvider)
          .createShadowplan(
            widget.tripId,
            itemId: itemId!,
            backupActivityId: backup!.id,
            notes: note.isEmpty ? null : note,
          );
      ref.invalidate(shadowplansProvider(widget.tripId));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Backup saved. The confirmed plan is unchanged.'),
        ),
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

  @override
  Widget build(BuildContext context) {
    final trip = ref.watch(tripProvider(widget.tripId));
    final itinerary = ref.watch(itineraryProvider(widget.tripId));
    final shadowplans = ref.watch(shadowplansProvider(widget.tripId));
    final catalog = trip.valueOrNull?.destinationId == null
        ? null
        : ref.watch(
            activitySearchProvider(
              ActivitySearchQuery(
                destinationId: trip.valueOrNull!.destinationId!,
                limit: 60,
              ),
            ),
          );
    final backupNames = <String, String>{
      for (final entry in catalog?.valueOrNull?.items ?? const <SearchItem>[])
        entry.activity.id: entry.activity.name,
    };
    return AsyncView<List<ShadowplanItem>>(
      value: shadowplans,
      onRetry: () => ref.invalidate(shadowplansProvider(widget.tripId)),
      padding: _pad,
      skeleton: const SkeletonList(count: 2, itemHeight: 64),
      builder: (plans) {
        final items = itinerary.valueOrNull?.items
                .where((item) => !item.cancelled)
                .toList() ??
            const <ItineraryItem>[];
        final titles = {
          for (final item in items) item.id: item.title,
        };
        return ListView(
          padding: _pad,
          children: [
            const InfoBanner(
              text:
                  'Shadowplans keep a fallback ready for each confirmed stop. '
                  'They never replace the confirmed plan automatically.',
              icon: Icons.safety_check_outlined,
            ),
            const SizedBox(height: 16),
            const SectionHeader(eyebrow: 'Ready', title: 'Backups'),
            if (plans.isEmpty)
              SafarEmpty(
                icon: Icons.inventory_2_outlined,
                title: 'No backups yet',
                message: items.isEmpty
                    ? 'Add items to the confirmed plan before keeping backups.'
                    : 'Choose a stop and a catalog activity to stand by.',
                action: items.isEmpty
                    ? null
                    : FilledButton(
                        onPressed: () => _addBackup(items),
                        child: const Text('Add a backup'),
                      ),
              )
            else ...[
              for (final plan in plans)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SafarCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'If ${titles[plan.itemId] ?? 'a plan item'} fails',
                                style: context.texts.titleSmall,
                              ),
                            ),
                            StatusChip(
                              plan.readinessStatus,
                              tone: plan.readinessStatus == 'ready'
                                  ? ChipTone.jade
                                  : ChipTone.ember,
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '→ ${backupNames[plan.backupActivityId] ?? 'Catalog backup'}',
                          style: context.texts.bodySmall,
                        ),
                        if (plan.notes != null && plan.notes!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(plan.notes!, style: context.texts.labelSmall),
                        ],
                        if (plan.createdAt != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'Saved ${timeAgo(plan.createdAt)}',
                              style: context.texts.labelSmall,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              if (items.isNotEmpty) ...[
                const SizedBox(height: 6),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _addBackup(items),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add a backup'),
                ),
              ],
            ],
          ],
        );
      },
    );
  }
}

class _CapsulesTab extends ConsumerStatefulWidget {
  const _CapsulesTab({required this.tripId});

  final String tripId;

  @override
  ConsumerState<_CapsulesTab> createState() => _CapsulesTabState();
}

class _CapsulesTabState extends ConsumerState<_CapsulesTab> {
  static const _ttls = [(24, '1 day'), (72, '3 days'), (168, '1 week'), (720, '30 days')];

  bool _busy = false;

  Future<void> _create() async {
    var ttl = 72;
    final confirmed = await showSafarSheet<bool>(
      context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SafarSheetHeader(
              title: 'Capture a journey capsule',
              subtitle:
                  'A private snapshot of the current plan and group for '
                  'offline reading. It expires automatically.',
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (hours, label) in _ttls)
                  ChoiceChip(
                    label: Text(label),
                    selected: ttl == hours,
                    onSelected: (_) => setSheetState(() => ttl = hours),
                  ),
              ],
            ),
            const SizedBox(height: 18),
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
                    child: const Text('Capture'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(tripRepositoryProvider)
          .createCapsule(widget.tripId, ttlHours: ttl);
      ref.invalidate(capsulesProvider(widget.tripId));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Capsule captured.')),
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

  @override
  Widget build(BuildContext context) {
    final palette = context.safar;
    return AsyncView<List<Capsule>>(
      value: ref.watch(capsulesProvider(widget.tripId)),
      onRetry: () => ref.invalidate(capsulesProvider(widget.tripId)),
      padding: _pad,
      skeleton: const SkeletonList(count: 2, itemHeight: 64),
      builder: (capsules) => ListView(
        padding: _pad,
        children: [
          const InfoBanner(
            text:
                'Journey capsules are readable snapshots for low-signal travel. '
                'They expire on their own; nothing is shared outside the trip.',
            icon: Icons.inventory_2_outlined,
          ),
          const SizedBox(height: 16),
          if (capsules.isEmpty)
            SafarEmpty(
              icon: Icons.photo_camera_back_outlined,
              title: 'No capsules yet',
              message: 'Capture the plan before a day with patchy signal.',
              action: FilledButton(
                onPressed: _busy ? null : _create,
                child: const Text('Capture capsule'),
              ),
            )
          else ...[
            for (final capsule in capsules)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SafarCard(
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: palette.jadeSoft,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.inventory_2_outlined,
                          size: 18,
                          color: palette.jade,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Captured ${timeAgo(capsule.createdAt)}',
                              style: context.texts.titleSmall,
                            ),
                            Text(
                              '${_snapshotCount(capsule)} items · '
                              'expires ${formatDate(capsule.staleAfter)}',
                              style: context.texts.labelSmall,
                            ),
                          ],
                        ),
                      ),
                      if (capsule.stale)
                        const StatusChip('Expired', tone: ChipTone.rose)
                      else
                        const StatusChip('Current', tone: ChipTone.jade),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              onPressed: _busy ? null : _create,
              icon: const Icon(Icons.add_a_photo_outlined, size: 18),
              label: const Text('Capture another'),
            ),
          ],
        ],
      ),
    );
  }

  int _snapshotCount(Capsule capsule) {
    final items = capsule.snapshot['items'];
    return items is List ? items.length : 0;
  }
}

class _LabeledLine extends StatelessWidget {
  const _LabeledLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(label, style: context.texts.labelMedium),
        ),
        Expanded(child: Text(value, style: context.texts.bodySmall)),
      ],
    );
  }
}
