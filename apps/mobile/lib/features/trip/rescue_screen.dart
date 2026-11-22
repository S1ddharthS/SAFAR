import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/engine.dart';
import '../../core/network/api_exception.dart';
import '../../core/providers.dart';
import '../../core/theme/safar_theme.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/safar_widgets.dart';

const _kinds = [
  ('rain', 'Rain or bad weather', Icons.water_drop_outlined),
  ('closure', 'Unexpected closure', Icons.block_outlined),
  ('traffic', 'Traffic delay', Icons.traffic_outlined),
  ('fatigue', 'Fatigue or low energy', Icons.battery_2_bar_outlined),
  ('budget', 'Budget change', Icons.savings_outlined),
  ('time', 'Time constraint', Icons.timer_outlined),
];

class RescueScreen extends ConsumerStatefulWidget {
  const RescueScreen({super.key, required this.tripId});

  final String tripId;

  @override
  ConsumerState<RescueScreen> createState() => _RescueScreenState();
}

class _RescueScreenState extends ConsumerState<RescueScreen> {
  String _kind = 'rain';
  String? _itemId;
  int _extraMinutes = 45;
  RescueAnalysis? _analysis;
  bool _busy = false;
  String? _error;

  Future<void> _analyze() async {
    setState(() {
      _busy = true;
      _error = null;
      _analysis = null;
    });
    try {
      final analysis = await ref
          .read(engineRepositoryProvider)
          .analyzeRescue(
            widget.tripId,
            kind: _kind,
            itemId: _itemId,
            extraMinutes: _extraMinutes,
          );
      if (!mounted) return;
      setState(() => _analysis = analysis);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _propose(RescueProposal proposal, RescueOption option) async {
    final activityId = option.activityId;
    if (activityId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Propose replacement?'),
        content: Text(
          '“${option.name}” will replace “${proposal.title}” on '
          '${formatDateShort(proposal.day)} at ${formatTime(proposal.startTime)}. '
          'Nothing changes until the group approves it.',
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
          .read(engineRepositoryProvider)
          .proposeRescue(
            widget.tripId,
            kind: _kind,
            itemId: proposal.itemId,
            activityId: activityId,
            day: proposal.day,
            startTime: proposal.startTime,
            extraMinutes: _extraMinutes,
          );
      ref.invalidate(proposalsProvider(widget.tripId));
      ref.invalidate(itineraryProvider(widget.tripId));
      ref.invalidate(tripProvider(widget.tripId));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Rescue proposal created for the group.')),
      );
      context.push('/trips/${widget.tripId}/proposals');
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
    final itinerary = ref.watch(itineraryProvider(widget.tripId));
    final items = itinerary.valueOrNull?.items.where((i) => !i.cancelled).toList() ?? [];
    return Scaffold(
      appBar: AppBar(title: const Text('Trip Rescue')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            const Eyebrow('When plans break'),
            const SizedBox(height: 8),
            Text('Find a way through.', style: context.texts.headlineLarge),
            const SizedBox(height: 8),
            Text(
              'Tell SAFAR what changed. It shows affected activities, protected time and '
              'grounded alternatives — then proposes changes for the group to approve.',
              style: context.texts.bodySmall?.copyWith(height: 1.5),
            ),
            const SizedBox(height: 18),
            const Eyebrow('What happened?'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (kind, label, icon) in _kinds)
                  ChoiceChip(
                    avatar: Icon(icon, size: 16),
                    label: Text(label),
                    selected: _kind == kind,
                    onSelected: (_) => setState(() => _kind = kind),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            if (items.isNotEmpty) ...[
              DropdownButtonFormField<String>(
                initialValue: _itemId,
                decoration: const InputDecoration(
                  labelText: 'Affected itinerary item (optional)',
                ),
                items: [
                  const DropdownMenuItem<String>(
                    value: null,
                    child: Text('Let SAFAR choose the nearest day'),
                  ),
                  for (final item in items)
                    DropdownMenuItem(
                      value: item.id,
                      child: Text(
                        '${formatDateShort(item.day)} · ${item.startTime} · ${item.title}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (value) => setState(() => _itemId = value),
              ),
              const SizedBox(height: 14),
            ],
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Extra time needed · $_extraMinutes min',
                    style: context.texts.titleSmall,
                  ),
                ),
              ],
            ),
            Slider(
              value: _extraMinutes.toDouble(),
              min: 15,
              max: 180,
              divisions: 11,
              label: '$_extraMinutes',
              onChanged: (value) =>
                  setState(() => _extraMinutes = value.round()),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy ? null : _analyze,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.healing_outlined, size: 18),
                label: const Text('Analyse disruption'),
              ),
            ),
            const SizedBox(height: 10),
            const InfoBanner(
              text:
                  'Rescue only creates a proposal. Protected time is never replaced and nothing '
                  'changes until the group approves.',
              icon: Icons.shield_outlined,
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              InfoBanner(text: _error!, tone: ChipTone.rose),
            ],
            if (_analysis != null) ...[
              const SizedBox(height: 22),
              _AnalysisView(
                analysis: _analysis!,
                busy: _busy,
                onPropose: _propose,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AnalysisView extends StatelessWidget {
  const _AnalysisView({
    required this.analysis,
    required this.busy,
    required this.onPropose,
  });

  final RescueAnalysis analysis;
  final bool busy;
  final Future<void> Function(RescueProposal, RescueOption) onPropose;

  @override
  Widget build(BuildContext context) {
    final palette = context.safar;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SafarCard(
          color: palette.emberSoft.withValues(alpha: 0.45),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(child: Eyebrow('Disruption')),
                  StatusChip(analysis.disruption.label, tone: ChipTone.ember),
                ],
              ),
              if (analysis.disruption.note != null) ...[
                const SizedBox(height: 8),
                Text(analysis.disruption.note!, style: context.texts.bodyMedium),
              ],
              if (analysis.message != null) ...[
                const SizedBox(height: 8),
                Text(analysis.message!, style: context.texts.bodySmall),
              ],
            ],
          ),
        ),
        if (analysis.affected.isNotEmpty) ...[
          const SizedBox(height: 18),
          const SectionHeader(eyebrow: 'Affected', title: 'Plans that need care'),
          for (final item in analysis.affected)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SafarCard(
                padding: const EdgeInsets.all(14),
                radius: 18,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${formatClock(item.startTime)} · ${item.title}',
                      style: context.texts.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(item.reason, style: context.texts.bodySmall),
                  ],
                ),
              ),
            ),
        ],
        if (analysis.protected.isNotEmpty) ...[
          const SizedBox(height: 12),
          InfoBanner(
            tone: ChipTone.jade,
            icon: Icons.lock_clock_outlined,
            text:
                'Protected time stays untouched: '
                '${analysis.protected.map((item) => item.title).join(', ')}.',
          ),
        ],
        if (analysis.consequences != null) ...[
          const SizedBox(height: 14),
          _ConsequencesCard(consequences: analysis.consequences!),
        ],
        const SizedBox(height: 20),
        const SectionHeader(
          eyebrow: 'Grounded alternatives',
          title: 'Ways forward',
        ),
        if (analysis.proposals.isEmpty)
          const SafarEmpty(
            icon: Icons.search_off,
            title: 'No suitable replacements',
            message:
                'The catalog has no eligible activity for this disruption. Adjust the disruption or add activities.',
          )
        else
          for (final proposal in analysis.proposals)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _RescueProposalCard(
                proposal: proposal,
                busy: busy,
                onPropose: (option) => onPropose(proposal, option),
              ),
            ),
        if (analysis.disclosure != null) ...[
          const SizedBox(height: 6),
          Text(analysis.disclosure!, style: context.texts.labelSmall),
        ],
      ],
    );
  }
}

class _ConsequencesCard extends StatelessWidget {
  const _ConsequencesCard({required this.consequences});

  final RescueConsequences consequences;

  @override
  Widget build(BuildContext context) {
    final parts = <String>[
      if (consequences.costDelta != 0)
        '${consequences.costDelta > 0 ? '+' : ''}${formatMoney(consequences.costDelta)}',
      if (consequences.timeSavedOrLost.isNotEmpty) consequences.timeSavedOrLost,
      if (consequences.durationDeltaMinutes != 0)
        '${consequences.durationDeltaMinutes > 0 ? '+' : ''}${consequences.durationDeltaMinutes} min',
      if (consequences.pactConflictCount > 0)
        '${consequences.pactConflictCount} pact conflicts',
    ];
    return InfoBanner(
      icon: Icons.compare_arrows,
      text: parts.isEmpty
          ? 'No material cost or timing change.'
          : parts.join(' · '),
    );
  }
}

class _RescueProposalCard extends StatelessWidget {
  const _RescueProposalCard({
    required this.proposal,
    required this.busy,
    required this.onPropose,
  });

  final RescueProposal proposal;
  final bool busy;
  final ValueChanged<RescueOption> onPropose;

  @override
  Widget build(BuildContext context) {
    final palette = context.safar;
    return SafarCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(proposal.title, style: context.texts.titleMedium),
          const SizedBox(height: 4),
          Text(
            '${formatDateShort(proposal.day)} · ${formatTime(proposal.startTime)} · ${proposal.reason}',
            style: context.texts.bodySmall,
          ),
          if (proposal.travelMinutes > 0)
            Text(
              '${proposal.travelMinutes} min travel to alternatives',
              style: context.texts.labelSmall,
            ),
          const SizedBox(height: 12),
          for (final option in proposal.options)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: option.name == proposal.recommended
                    ? palette.jadeSoft.withValues(alpha: 0.5)
                    : palette.raised,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: palette.line),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                option.name,
                                style: context.texts.titleSmall,
                              ),
                            ),
                            if (option.name == proposal.recommended) ...[
                              const SizedBox(width: 6),
                              const StatusChip('Recommended', tone: ChipTone.jade),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          [
                            if (option.price != null)
                              formatMoney(option.price),
                            if (option.duration != null)
                              '${option.duration} min',
                            if (option.indoor == true) 'indoor',
                            option.source,
                            if (option.score != null)
                              'score ${option.score!.round()}',
                          ].join(' · '),
                          style: context.texts.bodySmall,
                        ),
                        if (option.note != null) ...[
                          const SizedBox(height: 4),
                          Text(option.note!, style: context.texts.labelSmall),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: 'Propose this replacement',
                    onPressed: busy || option.activityId == null
                        ? null
                        : () => onPropose(option),
                    icon: const Icon(Icons.arrow_outward, size: 18),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
