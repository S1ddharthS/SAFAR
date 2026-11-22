import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/engine.dart';
import '../../core/models/trip.dart';
import '../../core/providers.dart';
import '../../core/theme/safar_theme.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/safar_widgets.dart';

class EngineScreen extends ConsumerStatefulWidget {
  const EngineScreen({super.key, required this.tripId});

  final String tripId;

  @override
  ConsumerState<EngineScreen> createState() => _EngineScreenState();
}

class _EngineScreenState extends ConsumerState<EngineScreen> {
  static const _modes = [
    ('everyone_wins', 'Everyone wins', 'Protects the least-served traveller'),
    ('your_turn', 'Your turn', 'Lifts members least represented'),
    ('surprise_us', 'Surprise us', 'Familiar enough, still new'),
  ];

  String _mode = 'everyone_wins';
  EngineBatch? _batch;
  bool _busy = false;

  Future<void> _run() async {
    setState(() => _busy = true);
    try {
      final batch = await ref
          .read(engineRepositoryProvider)
          .recommend(widget.tripId, mode: _mode, limit: 6);
      setState(() => _batch = batch);
      ref.invalidate(engineProvider(widget.tripId));
      if (!mounted) return;
      if (batch.items.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No options fit every hard constraint. Loosen a filter or add ideas.',
            ),
          ),
        );
      }
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _propose(RecommendationItem item, Trip trip) async {
    final days = tripDays(trip.startDate, trip.endDate);
    if (days.isEmpty) return;
    var day = days.first;
    final time = TextEditingController(text: '09:00');
    final submitted = await showSafarSheet<bool>(
      context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SafarSheetHeader(
              title: 'Propose to the group',
              subtitle:
                  '“${item.activity?.name ?? 'This option'}” becomes a vote. '
                  'The confirmed itinerary stays unchanged until approval.',
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
                    selected: isoDate(day) == isoDate(option),
                    onSelected: (_) => setSheetState(() => day = option),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: time,
              keyboardType: TextInputType.datetime,
              decoration: const InputDecoration(
                labelText: 'Start time',
                hintText: '09:00',
              ),
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
                    child: const Text('Create proposal'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    final startTime = time.text.trim();
    time.dispose();
    if (submitted != true) return;
    if (!RegExp(r'^\d{2}:\d{2}$').hasMatch(startTime)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Use a 24-hour time such as 09:30.')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(engineRepositoryProvider)
          .propose(
            widget.tripId,
            item.id,
            day: isoDate(day),
            startTime: startTime,
          );
      ref.invalidate(proposalsProvider(widget.tripId));
      ref.invalidate(itineraryProvider(widget.tripId));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Proposal created for ${formatDateShort(isoDate(day))}. The group can now vote.',
          ),
          action: SnackBarAction(
            label: 'View',
            onPressed: () =>
                context.push('/trips/${widget.tripId}/proposals'),
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

  Future<void> _feedback(RecommendationItem item, String sentiment) async {
    try {
      await ref
          .read(engineRepositoryProvider)
          .feedback(widget.tripId, item.id, sentiment);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Feedback recorded with consent. It never changes confirmed items.',
          ),
        ),
      );
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.safar;
    final providerBatch = ref.watch(engineProvider(widget.tripId));
    final batch = _batch ?? providerBatch.valueOrNull;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back),
        ),
        title: const Text('Group engine'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 34),
          children: [
            const Eyebrow('Group experience engine'),
            const SizedBox(height: 8),
            Text(
              'One plan that\ndoes not flatten anyone.',
              style: context.texts.displaySmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Every option is checked against hard constraints first, then ranked for fairness, '
              'fit and variety. Scores are estimates, not promises.',
              style: context.texts.bodySmall?.copyWith(height: 1.5),
            ),
            const SizedBox(height: 18),
            for (final mode in _modes)
              Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: SafarCard(
                  onTap: () => setState(() => _mode = mode.$1),
                  padding: const EdgeInsets.all(14),
                  color: _mode == mode.$1 ? palette.emberSoft : null,
                  borderColor: _mode == mode.$1 ? palette.ember : null,
                  child: Row(
                    children: [
                      Icon(
                        _mode == mode.$1
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        size: 18,
                        color: _mode == mode.$1 ? palette.ember : palette.faint,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(mode.$2, style: context.texts.titleSmall),
                            Text(mode.$3, style: context.texts.bodySmall),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _busy ? null : _run,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome, size: 18),
              label: Text(batch == null ? 'Find group options' : 'Refresh options'),
            ),
            const SizedBox(height: 14),
            if (batch != null) _MetaCard(batch: batch, mode: _mode),
            const SizedBox(height: 10),
            providerBatch.when(
              data: (_) {
                if (batch == null) {
                  return const SafarEmpty(
                    title: 'No group options yet',
                    message:
                        'Run the engine once the trip has a few constraints and ideas. '
                        'Each option explains why it was selected.',
                    icon: Icons.auto_awesome_outlined,
                  );
                }
                if (batch.items.isEmpty) {
                  return SafarEmpty(
                    title: 'Nothing clears every constraint',
                    message: batch.message ??
                        'Consider relaxing a budget, radius or time constraint privately.',
                    icon: Icons.filter_alt_off_outlined,
                  );
                }
                final trip = ref.watch(tripProvider(widget.tripId)).valueOrNull;
                return Column(
                  children: [
                    for (final item in batch.items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _RecommendationCard(
                          item: item,
                          modeLabel: batch.modeMeta.label.isEmpty
                              ? batch.mode
                              : batch.modeMeta.label,
                          busy: _busy || trip == null,
                          onPropose: trip == null
                              ? null
                              : () => _propose(item, trip),
                          onFeedback: (sentiment) =>
                              _feedback(item, sentiment),
                        ),
                      ),
                  ],
                );
              },
              loading: () => const SkeletonList(count: 2),
              error: (error, stack) => SafarErrorView(
                message: error.toString(),
                onRetry: () =>
                    ref.invalidate(engineProvider(widget.tripId)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetaCard extends StatelessWidget {
  const _MetaCard({required this.batch, required this.mode});

  final EngineBatch batch;
  final String mode;

  @override
  Widget build(BuildContext context) {
    final palette = context.safar;
    final meta = batch.meta;
    final evaluation = meta.evaluation;
    return SafarCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Eyebrow(
                  batch.modeMeta.label.isEmpty ? mode : batch.modeMeta.label,
                ),
              ),
              StatusChip(
                '${meta.eligibleCount}/${meta.candidateCount} eligible',
                tone: ChipTone.neutral,
              ),
            ],
          ),
          if (batch.modeMeta.intent.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(batch.modeMeta.intent, style: context.texts.bodySmall),
          ],
          if (evaluation != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _Metric(
                    label: 'Avg fit',
                    value: '${evaluation.satisfaction.meanAverageFit.round()}%',
                  ),
                ),
                Expanded(
                  child: _Metric(
                    label: 'Least-served',
                    value:
                        '${evaluation.fairness.leastServedMeanFit.round()}%',
                  ),
                ),
                Expanded(
                  child: _Metric(
                    label: 'Novelty',
                    value:
                        '${evaluation.satisfaction.meanNovelty.round()}%',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _Metric(
                    label: 'Constraint breaks',
                    value: '${evaluation.constraints.violations}',
                  ),
                ),
                Expanded(
                  child: _Metric(
                    label: 'Unique tags',
                    value: '${evaluation.diversity.uniqueTags}',
                  ),
                ),
                Expanded(
                  child: _Metric(
                    label: 'Members',
                    value: '${meta.membersCount}',
                  ),
                ),
              ],
            ),
          ],
          if (meta.clarifyingQuestion != null &&
              meta.clarifyingQuestion!.isNotEmpty) ...[
            const SizedBox(height: 12),
            InfoBanner(
              text: meta.clarifyingQuestion!,
              icon: Icons.help_outline,
              tone: ChipTone.ember,
            ),
          ],
          if (meta.pulseCoverage != null) ...[
            const SizedBox(height: 8),
            Text('Pulse coverage · ${meta.pulseCoverage}', style: context.texts.labelSmall),
          ],
          if (meta.disclosure != null) ...[
            const SizedBox(height: 10),
            Text(
              meta.disclosure!,
              style: context.texts.labelSmall?.copyWith(
                color: palette.faint,
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: context.texts.titleMedium),
        Text(label, style: context.texts.labelSmall),
      ],
    );
  }
}

class _RecommendationCard extends StatelessWidget {
  const _RecommendationCard({
    required this.item,
    required this.modeLabel,
    required this.busy,
    required this.onPropose,
    required this.onFeedback,
  });

  final RecommendationItem item;
  final String modeLabel;
  final bool busy;
  final VoidCallback? onPropose;
  final ValueChanged<String> onFeedback;

  @override
  Widget build(BuildContext context) {
    final palette = context.safar;
    final explanation = item.explanation;
    final activity = item.activity;
    return SafarCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: palette.ink,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  '${item.rank}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: palette.surface,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Eyebrow('$modeLabel · ${item.status}'),
              ),
              Text(
                '${item.score.round()}',
                style: context.texts.headlineSmall?.copyWith(
                  color: palette.ember,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            activity?.name ?? 'Group option',
            style: context.texts.titleMedium,
          ),
          const SizedBox(height: 3),
          Text(
            explanation.summary,
            style: context.texts.bodySmall?.copyWith(height: 1.45),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              StatusChip('Avg ${item.averageFit.round()}%', tone: ChipTone.jade),
              StatusChip(
                'Lowest ${item.minimumFit.round()}%',
                tone: item.minimumFit < 50 ? ChipTone.rose : ChipTone.neutral,
              ),
              if (explanation.estimatedCost > 0)
                StatusChip(
                  formatMoney(explanation.estimatedCost, explanation.currency),
                ),
              if (explanation.durationMinutes > 0)
                StatusChip('${explanation.durationMinutes}m'),
              if (explanation.travelMinutes > 0)
                StatusChip('${explanation.travelMinutes}m travel'),
              if (explanation.distanceKm > 0)
                StatusChip('${explanation.distanceKm.toStringAsFixed(1)} km'),
            ],
          ),
          if (explanation.whySelected.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Why this surfaced', style: context.texts.labelMedium),
            const SizedBox(height: 4),
            for (final reason in explanation.whySelected.take(3))
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Container(
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                          color: palette.ember,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(reason, style: context.texts.bodySmall),
                    ),
                  ],
                ),
              ),
          ],
          if (explanation.suits.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Suits · ${explanation.suits.join(', ')}',
              style: context.texts.labelSmall,
            ),
          ],
          if (explanation.mayNotPrefer.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Might not suit · ${explanation.mayNotPrefer.join(', ')}',
              style: context.texts.labelSmall,
            ),
          ],
          if (explanation.uncertainties.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Uncertain · ${explanation.uncertainties.join(', ')}',
              style: context.texts.labelSmall?.copyWith(color: palette.faint),
            ),
          ],
          if (explanation.constraintsChecked.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final check in explanation.constraintsChecked.take(4))
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      check.status == 'pass'
                          ? Icons.check_circle_outline
                          : check.status == 'warn'
                          ? Icons.error_outline
                          : Icons.info_outline,
                      size: 14,
                      color: check.status == 'pass'
                          ? palette.jade
                          : check.status == 'warn'
                          ? palette.rose
                          : palette.faint,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${titleCase(check.constraint)} · ${check.detail}',
                        style: context.texts.labelSmall,
                      ),
                    ),
                  ],
                ),
              ),
          ],
          if (item.respect != null) ...[
            const SizedBox(height: 10),
            InfoBanner(
              text:
                  '${item.respect!.status}${item.respect!.guidance == null ? '' : ' · ${item.respect!.guidance}'}',
              icon: item.respect!.fragile
                  ? Icons.warning_amber_outlined
                  : Icons.spa_outlined,
              tone: item.respect!.fragile ? ChipTone.ember : ChipTone.jade,
            ),
          ],
          if (explanation.memberFitsAnonymous.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Member fit (anonymous)', style: context.texts.labelSmall),
            const SizedBox(height: 6),
            Row(
              children: [
                for (final fit in explanation.memberFitsAnonymous)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          value: (fit / 100).clamp(0, 1),
                          minHeight: 5,
                          backgroundColor: palette.line,
                          color: fit < 50 ? palette.rose : palette.jade,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
          if (explanation.dataFreshness != null) ...[
            const SizedBox(height: 10),
            SourceLabel(
              source: explanation.dataFreshness!.label,
              confidence: explanation.dataFreshness!.lastVerifiedAt == null
                  ? null
                  : 'verified ${formatDateShort(explanation.dataFreshness!.lastVerifiedAt)}',
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: busy || onPropose == null ? null : onPropose,
                  child: const Text('Propose to group'),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: 'I would love this',
                onPressed: busy ? null : () => onFeedback('loved'),
                icon: Icon(
                  item.myFeedback == 'loved'
                      ? Icons.favorite
                      : Icons.favorite_border,
                  size: 20,
                  color: palette.ember,
                ),
              ),
              IconButton(
                tooltip: 'Not for me',
                onPressed: busy ? null : () => onFeedback('not_for_me'),
                icon: Icon(
                  item.myFeedback == 'not_for_me'
                      ? Icons.thumb_down
                      : Icons.thumb_down_outlined,
                  size: 19,
                ),
              ),
            ],
          ),
          Text(
            'Feedback is consent-based and adjusts future ranking only. '
            'It never edits confirmed items.',
            style: context.texts.labelSmall?.copyWith(color: palette.faint),
          ),
        ],
      ),
    );
  }
}
