import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/discovery.dart';
import '../../core/models/planning.dart';
import '../../core/models/trip.dart';
import '../../core/providers.dart';
import '../../core/theme/safar_theme.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/safar_widgets.dart';
import 'widgets/activity_search.dart';

class NegotiateScreen extends ConsumerStatefulWidget {
  const NegotiateScreen({super.key, required this.tripId});

  final String tripId;

  @override
  ConsumerState<NegotiateScreen> createState() => _NegotiateScreenState();
}

class _NegotiateScreenState extends ConsumerState<NegotiateScreen> {
  static const _maxPerSide = 8;

  final List<Activity> _optionA = [];
  final List<Activity> _optionB = [];
  String _side = 'a';
  String? _day;
  NegotiationResult? _result;
  bool _busy = false;

  List<Activity> get _active => _side == 'a' ? _optionA : _optionB;

  void _add(Activity activity) {
    final other = _side == 'a' ? _optionB : _optionA;
    if (other.any((item) => item.id == activity.id)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '“${activity.name}” is already in option '
            '${_side == 'a' ? 'B' : 'A'}.',
          ),
        ),
      );
      return;
    }
    if (_active.any((item) => item.id == activity.id)) {
      setState(() => _active.removeWhere((item) => item.id == activity.id));
      return;
    }
    if (_active.length >= _maxPerSide) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Keep each option to $_maxPerSide activities or fewer.'),
        ),
      );
      return;
    }
    setState(() => _active.add(activity));
  }

  Future<void> _negotiate(Trip trip) async {
    if (_optionA.isEmpty || _optionB.isEmpty) return;
    setState(() {
      _busy = true;
      _result = null;
    });
    try {
      final result = await ref
          .read(engineRepositoryProvider)
          .negotiate(
            widget.tripId,
            optionA: [for (final a in _optionA) a.id],
            optionB: [for (final a in _optionB) a.id],
            forDate: _day,
          );
      if (!mounted) return;
      setState(() => _result = result);
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _proposeCompromise(NegotiationOption option) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Propose the compromise?'),
        content: Text(
          '“${option.name}” becomes a group proposal. The confirmed itinerary '
          'stays unchanged until the group votes and an owner or admin '
          'approves.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
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
          .read(itineraryRepositoryProvider)
          .createProposal(
            widget.tripId,
            title: 'Try ${option.name} as a compromise',
            summary: _result?.whoBenefits == null
                ? 'Suggested by the negotiator.'
                : 'Suggested by the negotiator. Benefits: ${_result!.whoBenefits}',
            activityId: option.activityId,
            day: _day,
          );
      ref.invalidate(proposalsProvider(widget.tripId));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Compromise proposed. The group can vote on it now.'),
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
      appBar: AppBar(title: const Text('Negotiator')),
      body: AsyncView<Trip>(
        value: trip,
        onRetry: () => ref.invalidate(tripProvider(widget.tripId)),
        skeleton: const SkeletonList(count: 3, itemHeight: 72),
        builder: (data) {
          final days = tripDays(data.startDate, data.endDate);
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 36),
            children: [
              const InfoBanner(
                text:
                    'Compare two shortlists and let SAFAR find a middle option '
                    'that protects the least-served traveller. Nothing is '
                    'added to the plan here.',
                icon: Icons.handshake_outlined,
              ),
              const SizedBox(height: 18),
              if (days.isNotEmpty) ...[
                const SectionHeader(eyebrow: 'Context', title: 'Day (optional)'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('Any day'),
                      selected: _day == null,
                      onSelected: (_) => setState(() => _day = null),
                    ),
                    for (final option in days)
                      ChoiceChip(
                        label: Text(formatDateShort(isoDate(option))),
                        selected: _day == isoDate(option),
                        onSelected: (_) =>
                            setState(() => _day = isoDate(option)),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
              ],
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'a', label: Text('Option A')),
                  ButtonSegment(value: 'b', label: Text('Option B')),
                ],
                selected: {_side},
                onSelectionChanged: (selection) =>
                    setState(() => _side = selection.first),
              ),
              const SizedBox(height: 14),
              _SideSummary(
                label: 'Option A',
                color: context.safar.jade,
                activities: _optionA,
                active: _side == 'a',
                onRemove: (activity) =>
                    setState(() => _optionA.remove(activity)),
              ),
              const SizedBox(height: 8),
              _SideSummary(
                label: 'Option B',
                color: context.safar.ember,
                activities: _optionB,
                active: _side == 'b',
                onRemove: (activity) =>
                    setState(() => _optionB.remove(activity)),
              ),
              const SizedBox(height: 16),
              SectionHeader(
                eyebrow: 'Building option ${_side.toUpperCase()}',
                title: 'Add to option ${_side.toUpperCase()}',
              ),
              ActivitySearchList(
                destinationId: data.destinationId,
                trailing: (activity) {
                  final inActive = _active.any((a) => a.id == activity.id);
                  return Icon(
                    inActive ? Icons.check_circle : Icons.add_circle_outline,
                    size: 20,
                    color: inActive
                        ? (_side == 'a' ? context.safar.jade : context.safar.ember)
                        : context.safar.faint,
                  );
                },
                onTap: _add,
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _optionA.isEmpty || _optionB.isEmpty || _busy
                    ? null
                    : () => _negotiate(data),
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.balance_outlined, size: 18),
                label: const Text('Find a compromise'),
              ),
              if (_result != null) ...[
                const SizedBox(height: 22),
                _NegotiationCard(
                  result: _result!,
                  busy: _busy,
                  onPropose: _proposeCompromise,
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _SideSummary extends StatelessWidget {
  const _SideSummary({
    required this.label,
    required this.color,
    required this.activities,
    required this.active,
    required this.onRemove,
  });

  final String label;
  final Color color;
  final List<Activity> activities;
  final bool active;
  final ValueChanged<Activity> onRemove;

  @override
  Widget build(BuildContext context) {
    final palette = context.safar;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: active ? color.withValues(alpha: 0.55) : palette.line,
        ),
        color: active ? color.withValues(alpha: 0.06) : palette.surface,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label · ${activities.length}/8',
            style: context.texts.labelMedium?.copyWith(
              color: active ? color : palette.muted,
            ),
          ),
          const SizedBox(height: 6),
          if (activities.isEmpty)
            Text('Empty — add activities below.', style: context.texts.labelSmall)
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final activity in activities)
                  InputChip(
                    label: Text(activity.name),
                    onDeleted: () => onRemove(activity),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _NegotiationCard extends StatelessWidget {
  const _NegotiationCard({
    required this.result,
    required this.busy,
    required this.onPropose,
  });

  final NegotiationResult result;
  final bool busy;
  final ValueChanged<NegotiationOption> onPropose;

  @override
  Widget build(BuildContext context) {
    final palette = context.safar;
    if (!result.ready) {
      return SafarCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: const Eyebrow('Negotiation'),
                ),
                StatusChip(
                  result.status == 'no_feasible_option'
                      ? 'No option yet'
                      : 'Needs input',
                  tone: ChipTone.rose,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              result.message ??
                  'Both shortlists break a hard constraint. Adjust an option '
                      'and try again.',
              style: context.texts.bodySmall,
            ),
            if (result.tradeOffs.isNotEmpty) ...[
              const SizedBox(height: 10),
              for (final item in result.tradeOffs)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('• $item', style: context.texts.labelSmall),
                ),
            ],
            if (result.disclosure != null && result.disclosure!.isNotEmpty) ...[
              const SizedBox(height: 8),
              SourceLabel(source: result.disclosure!),
            ],
          ],
        ),
      );
    }
    final compromise = result.compromise!;
    final alternative = result.alternative;
    return SafarCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: Eyebrow('Compromise ready')),
              StatusChip(
                'Lowest fit ${compromise.minimumFit.round()}%',
                tone: ChipTone.jade,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(compromise.name, style: context.texts.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Average fit ${compromise.averageFit.round()}% · '
            'lowest member ${compromise.minimumFit.round()}%',
            style: context.texts.labelSmall,
          ),
          if (alternative != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: palette.raised,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                'Closest other option: ${alternative.name} '
                '(avg ${alternative.averageFit.round()}%, '
                'lowest ${alternative.minimumFit.round()}%)',
                style: context.texts.bodySmall,
              ),
            ),
          ],
          if (result.whoBenefits != null) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.favorite_outline, size: 15, color: palette.jade),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Benefits: ${result.whoBenefits}',
                    style: context.texts.bodySmall,
                  ),
                ),
              ],
            ),
          ],
          if (result.whoCompromises != null) ...[
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.balance, size: 15, color: palette.ember),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Compromises: ${result.whoCompromises}',
                    style: context.texts.bodySmall,
                  ),
                ),
              ],
            ),
          ],
          if (result.tradeOffs.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Eyebrow('Trade-offs'),
            const SizedBox(height: 6),
            for (final item in result.tradeOffs)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text('• $item', style: context.texts.labelSmall),
              ),
          ],
          const SizedBox(height: 14),
          FilledButton.tonalIcon(
            onPressed: busy ? null : () => onPropose(compromise),
            icon: const Icon(Icons.how_to_vote_outlined, size: 18),
            label: const Text('Propose to the group'),
          ),
          if (result.disclosure != null && result.disclosure!.isNotEmpty) ...[
            const SizedBox(height: 10),
            SourceLabel(source: result.disclosure!),
          ],
        ],
      ),
    );
  }
}
