import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/json.dart';
import '../../core/models/planning.dart';
import '../../core/models/trip.dart';
import '../../core/providers.dart';
import '../../core/theme/safar_theme.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/safar_widgets.dart';

class OpportunityScreen extends ConsumerStatefulWidget {
  const OpportunityScreen({super.key, required this.tripId});

  final String tripId;

  @override
  ConsumerState<OpportunityScreen> createState() => _OpportunityScreenState();
}

class _OpportunityScreenState extends ConsumerState<OpportunityScreen> {
  String? _day;
  bool _busy = false;

  String _dayFor(Trip trip) {
    final days = tripDays(trip.startDate, trip.endDate);
    if (days.isEmpty) return isoDate(DateTime.now());
    final explicit = shortDate(_day);
    if (explicit != null) {
      final match = days.where((d) => isoDate(d) == isoDate(explicit));
      if (match.isNotEmpty) return isoDate(match.first);
    }
    final today = DateTime.now();
    final inRange = days.where(
      (d) => d.year == today.year && d.month == today.month && d.day == today.day,
    );
    return isoDate(inRange.isNotEmpty ? inRange.first : days.first);
  }

  Future<void> _propose(OpportunityItem item, String day) async {
    setState(() => _busy = true);
    try {
      await ref
          .read(itineraryRepositoryProvider)
          .createProposal(
            widget.tripId,
            title: 'Add ${item.name}',
            summary: 'Found through the Opportunity Clock for ${formatDate(day)}. '
                '${item.explanation}',
            activityId: item.activityId,
            day: day,
          );
      ref.invalidate(proposalsProvider(widget.tripId));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Proposal created. The confirmed plan is unchanged until approval.',
          ),
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
    return Scaffold(
      appBar: AppBar(title: const Text('Opportunity clock')),
      body: AsyncView<Trip>(
        value: trip,
        onRetry: () => ref.invalidate(tripProvider(widget.tripId)),
        skeleton: const SkeletonList(count: 3, itemHeight: 76),
        builder: (data) {
          final days = tripDays(data.startDate, data.endDate);
          final day = _dayFor(data);
          final key = (tripId: widget.tripId, day: day);
          final clock = ref.watch(opportunityProvider(key));
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 36),
            children: [
              if (days.isNotEmpty) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final option in days)
                      ChoiceChip(
                        label: Text(formatDateShort(isoDate(option))),
                        selected: isoDate(option) == day,
                        onSelected: (_) => setState(() => _day = isoDate(option)),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
              AsyncView<OpportunityClock>(
                value: clock,
                onRetry: () => ref.invalidate(opportunityProvider(key)),
                skeleton: const SkeletonList(count: 3, itemHeight: 84),
                builder: (result) {
                  if (!result.available) {
                    return SafarEmpty(
                      icon: Icons.upcoming_outlined,
                      title: 'Not available yet',
                      message: result.reason ??
                          'Choose a day inside this trip to see open options.',
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _ClockSummary(clock: result),
                      const SizedBox(height: 14),
                      if (result.planUnchanged)
                        const InfoBanner(
                          text:
                              'Read-only: the confirmed plan is not touched. '
                              'Openings come from the catalog, not live status.',
                          icon: Icons.lock_clock,
                        ),
                      if (result.planUnchanged) const SizedBox(height: 14),
                      if (result.plannedTitles.isNotEmpty) ...[
                        const Eyebrow('Already planned'),
                        const SizedBox(height: 4),
                        Text(
                          result.plannedTitles.join(' · '),
                          style: context.texts.bodySmall,
                        ),
                        const SizedBox(height: 14),
                      ],
                      if (result.items.isEmpty)
                        SafarEmpty(
                          icon: Icons.event_available_outlined,
                          title: 'No open options',
                          message:
                              'Nothing in the catalog fits this day with the '
                              'planned stops. Try another day.',
                        )
                      else
                        for (final item in result.items)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _OpportunityCard(
                              item: item,
                              busy: _busy,
                              onPropose: () => _propose(item, day),
                              onOpen: () => context.push(
                                '/trips/${widget.tripId}/places/${item.activityId}',
                              ),
                            ),
                          ),
                      if (result.explanation != null &&
                          result.explanation!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(result.explanation!, style: context.texts.bodySmall),
                        const SizedBox(height: 8),
                      ],
                      if (result.disclosure != null &&
                          result.disclosure!.isNotEmpty)
                        SourceLabel(source: result.disclosure!),
                    ],
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ClockSummary extends StatelessWidget {
  const _ClockSummary({required this.clock});

  final OpportunityClock clock;

  @override
  Widget build(BuildContext context) {
    final palette = context.safar;
    final summary = clock.summary;
    return SafarCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Eyebrow(
                  [
                    if (clock.weekday != null) clock.weekday!,
                    formatDate(clock.date),
                  ].join(' · '),
                  color: palette.ember,
                ),
              ),
              if (clock.now != null)
                StatusChip('Now ${formatTime(clock.now)}', tone: ChipTone.neutral),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              StatusChip('${summary.openNow} open now', tone: ChipTone.jade),
              StatusChip('${summary.laterToday} later', tone: ChipTone.ember),
              StatusChip('${summary.closedToday} closed', tone: ChipTone.rose),
              StatusChip('${summary.unknownHours} unknown'),
            ],
          ),
          if (clock.freeWindows.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Eyebrow('Free windows'),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final window in clock.freeWindows)
                  StatusChip(
                    '${formatTime(window.start)}–${formatTime(window.end)}',
                  ),
              ],
            ),
          ],
          if (clock.plannedCount > 0) ...[
            const SizedBox(height: 10),
            Text(
              clock.plannedCount == 1
                  ? '1 confirmed stop this day.'
                  : '${clock.plannedCount} confirmed stops this day.',
              style: context.texts.labelSmall,
            ),
          ],
        ],
      ),
    );
  }
}

class _OpportunityCard extends StatelessWidget {
  const _OpportunityCard({
    required this.item,
    required this.busy,
    required this.onPropose,
    required this.onOpen,
  });

  final OpportunityItem item;
  final bool busy;
  final VoidCallback onPropose;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final palette = context.safar;
    final (label, tone) = switch (item.status) {
      'open_now' => ('Open now', ChipTone.jade),
      'later_today' => ('Later today', ChipTone.ember),
      'closed_today' => ('Closed today', ChipTone.rose),
      'no_window' => ('No fit window', ChipTone.neutral),
      _ => ('Hours unknown', ChipTone.neutral),
    };
    final hours = item.openingHoursToday == null
        ? null
        : 'Hours ${item.openingHoursToday}'
              '${item.openingSource == null ? '' : ' (${item.openingSource})'}';
    return SafarCard(
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(item.name, style: context.texts.titleSmall),
              ),
              StatusChip(label, tone: tone),
            ],
          ),
          if (item.placeName != null && item.placeName!.isNotEmpty)
            Text(item.placeName!, style: context.texts.labelSmall),
          const SizedBox(height: 4),
          Text(
            [
              '${item.durationMinutes} min',
              formatMoney(item.priceEstimate, item.currency),
              '~${item.travelMinutesEstimate} min travel',
              if (item.nextStart != null) 'next ${formatTime(item.nextStart)}',
            ].join(' · '),
            style: context.texts.labelSmall,
          ),
          if (hours != null) ...[
            const SizedBox(height: 4),
            Text(hours, style: context.texts.labelSmall),
          ],
          const SizedBox(height: 6),
          Text(item.explanation, style: context.texts.bodySmall),
          const SizedBox(height: 6),
          Row(
            children: [
              SourceLabel(source: titleCase(item.provenance)),
              const Spacer(),
              IconButton(
                tooltip: 'Open place',
                visualDensity: VisualDensity.compact,
                onPressed: onOpen,
                icon: Icon(
                  Icons.open_in_new,
                  size: 17,
                  color: palette.muted,
                ),
              ),
              TextButton(
                onPressed: busy ? null : onPropose,
                child: const Text('Propose'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
