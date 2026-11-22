import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/discovery.dart';
import '../../core/models/json.dart';
import '../../core/models/planning.dart';
import '../../core/models/trip.dart';
import '../../core/providers.dart';
import '../../core/theme/safar_theme.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/safar_widgets.dart';
import 'widgets/activity_search.dart';

class TwinScreen extends ConsumerStatefulWidget {
  const TwinScreen({super.key, required this.tripId});

  final String tripId;

  @override
  ConsumerState<TwinScreen> createState() => _TwinScreenState();
}

class _TwinScreenState extends ConsumerState<TwinScreen> {
  static const _maxActivities = 16;

  final List<Activity> _selected = [];
  TwinComparison? _comparison;
  String? _day;
  bool _busy = false;

  String _dayFor(Trip trip) {
    final days = tripDays(trip.startDate, trip.endDate);
    if (days.isEmpty) return isoDate(DateTime.now());
    final preferred = shortDate(_day) ?? shortDate(trip.startDate);
    if (preferred == null) return isoDate(days.first);
    final match = days.where((d) => isoDate(d) == isoDate(preferred));
    return isoDate(match.isNotEmpty ? match.first : days.first);
  }

  void _toggle(Activity activity) {
    final existing = _selected.indexWhere((item) => item.id == activity.id);
    setState(() {
      if (existing >= 0) {
        _selected.removeAt(existing);
        return;
      }
      if (_selected.length >= _maxActivities) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Compare up to $_maxActivities activities at once.'),
          ),
        );
        return;
      }
      _selected.add(activity);
    });
  }

  Future<void> _compare(Trip trip) async {
    if (_selected.isEmpty) return;
    final day = _dayFor(trip);
    setState(() {
      _busy = true;
      _day = day;
    });
    try {
      final result = await ref
          .read(engineRepositoryProvider)
          .twinCompare(
            widget.tripId,
            activityIds: [for (final a in _selected) a.id],
            day: day,
          );
      if (!mounted) return;
      setState(() => _comparison = result);
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _propose(Trip trip) async {
    final day = _dayFor(trip);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Propose this alternative?'),
        content: const Text(
          'The group will vote on the alternative plan. Your confirmed '
          'itinerary stays unchanged until an owner or admin approves it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep comparing'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Create proposal'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(engineRepositoryProvider)
          .twinPropose(
            widget.tripId,
            activityIds: [for (final a in _selected) a.id],
            day: day,
          );
      ref.invalidate(proposalsProvider(widget.tripId));
      ref.invalidate(itineraryProvider(widget.tripId));
      ref.invalidate(engineProvider(widget.tripId));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Alternative proposed. The confirmed plan is unchanged until approval.',
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
      appBar: AppBar(title: const Text('Trip twin')),
      body: AsyncView<Trip>(
        value: trip,
        onRetry: () => ref.invalidate(tripProvider(widget.tripId)),
        skeleton: const SkeletonList(count: 3, itemHeight: 72),
        builder: (data) {
          final days = tripDays(data.startDate, data.endDate);
          final day = _dayFor(data);
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 36),
            children: [
              const InfoBanner(
                text:
                    'A twin compares the confirmed plan with an alternative '
                    'built from catalog activities. Nothing changes until the '
                    'group votes and an owner or admin approves.',
                icon: Icons.call_split,
              ),
              const SizedBox(height: 18),
              if (days.isNotEmpty) ...[
                const SectionHeader(eyebrow: 'Comparing', title: 'Pick a day'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final option in days)
                      ChoiceChip(
                        label: Text(formatDateShort(isoDate(option))),
                        selected: isoDate(option) == day,
                        onSelected: (_) => setState(
                          () => _day = isoDate(option),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
              ],
              SectionHeader(
                eyebrow: 'Alternative',
                title: 'Choose activities (${_selected.length}/$_maxActivities)',
              ),
              if (_selected.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final activity in _selected)
                        InputChip(
                          label: Text(activity.name),
                          onDeleted: () => _toggle(activity),
                        ),
                    ],
                  ),
                ),
              ActivitySearchList(
                destinationId: data.destinationId,
                trailing: (activity) {
                  final selected = _selected.any((a) => a.id == activity.id);
                  return Icon(
                    selected
                        ? Icons.check_circle
                        : Icons.add_circle_outline,
                    size: 20,
                    color: selected
                        ? context.safar.jade
                        : context.safar.faint,
                  );
                },
                onTap: _toggle,
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _selected.isEmpty || _busy
                    ? null
                    : () => _compare(data),
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.compare_arrows, size: 18),
                label: const Text('Compare plans'),
              ),
              if (_comparison != null) ...[
                const SizedBox(height: 24),
                _ComparisonCard(comparison: _comparison!),
                const SizedBox(height: 14),
                FilledButton.tonalIcon(
                  onPressed: _busy ? null : () => _propose(data),
                  icon: const Icon(Icons.how_to_vote_outlined, size: 18),
                  label: const Text('Propose this alternative'),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _ComparisonCard extends StatelessWidget {
  const _ComparisonCard({required this.comparison});

  final TwinComparison comparison;

  @override
  Widget build(BuildContext context) {
    final palette = context.safar;
    return SafarCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Eyebrow(
                  'Twin · ${formatDate(comparison.day)}',
                  color: palette.ember,
                ),
              ),
              if (comparison.requiresApproval)
                const StatusChip('Needs approval', tone: ChipTone.ember),
            ],
          ),
          const SizedBox(height: 14),
          _PlanSummary(
            label: 'Confirmed',
            plan: comparison.confirmedPlan,
            color: palette.jade,
          ),
          const SizedBox(height: 10),
          _PlanSummary(
            label: 'Alternative',
            plan: comparison.alternativePlan,
            color: palette.ember,
          ),
          const SizedBox(height: 14),
          Divider(color: palette.line, height: 1),
          const SizedBox(height: 12),
          if (!comparison.diff.isEmpty) ...[
            _DiffRow(label: 'Added', items: comparison.diff.added, sign: '+'),
            _DiffRow(
              label: 'Removed',
              items: comparison.diff.removed,
              sign: '−',
            ),
            _DiffRow(label: 'Kept', items: comparison.diff.kept, sign: '='),
            const SizedBox(height: 8),
          ],
          if (comparison.tradeOffs.isNotEmpty) ...[
            const Eyebrow('Trade-offs'),
            const SizedBox(height: 6),
            for (final item in comparison.tradeOffs)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.swap_horiz,
                      size: 15,
                      color: palette.muted,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(item, style: context.texts.bodySmall),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
          ],
          if (comparison.disclosure.isNotEmpty)
            SourceLabel(source: comparison.disclosure),
        ],
      ),
    );
  }
}

class _PlanSummary extends StatelessWidget {
  const _PlanSummary({
    required this.label,
    required this.plan,
    required this.color,
  });

  final String label;
  final PlanMetrics plan;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final parts = [
      formatMoney(plan.totalCost),
      '${plan.totalDurationMinutes} min planned',
      '${plan.totalTravelMinutes} min travel',
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.35)),
        color: color.withValues(alpha: 0.06),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: context.texts.labelMedium?.copyWith(color: color),
                ),
              ),
              if (plan.averageGroupFit != null)
                Text(
                  'Avg fit ${plan.averageGroupFit!.round()}% · '
                  'lowest ${plan.minimumMemberFit?.round() ?? 0}%',
                  style: context.texts.labelSmall,
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(plan.name, style: context.texts.titleSmall),
          const SizedBox(height: 2),
          Text(parts.join(' · '), style: context.texts.labelSmall),
          if (plan.items.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              plan.items.map((item) => item.name).join(' → '),
              style: context.texts.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

class _DiffRow extends StatelessWidget {
  const _DiffRow({required this.label, required this.items, required this.sign});

  final String label;
  final List<PlanActivityRef> items;
  final String sign;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 66,
            child: Text(label, style: context.texts.labelMedium),
          ),
          Expanded(
            child: Text(
              items.map((item) => '$sign ${item.name}').join(', '),
              style: context.texts.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
