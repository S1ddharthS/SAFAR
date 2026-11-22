import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/trip.dart';
import '../../core/network/api_exception.dart';
import '../../core/providers.dart';
import '../../core/theme/safar_theme.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/safar_widgets.dart';

const _interestOptions = [
  'food',
  'culture',
  'outdoors',
  'nature',
  'nightlife',
  'shopping',
  'relaxed',
  'adventure',
  'photography',
  'local',
];

class PulseScreen extends ConsumerWidget {
  const PulseScreen({super.key, required this.tripId});

  final String tripId;

  Future<void> _openEditor(BuildContext context, WidgetRef ref) async {
    final saved = await showSafarSheet<bool>(
      context,
      builder: (_) => _PulseSheet(tripId: tripId),
    );
    if (saved == true) {
      ref.invalidate(pulseProvider(tripId));
      ref.invalidate(engineProvider(tripId));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pulse = ref.watch(pulseProvider(tripId));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Daily Pulse'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(pulseProvider(tripId)),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(pulseProvider(tripId));
            try {
              await ref.read(pulseProvider(tripId).future);
            } on Object {
              // Rendered by AsyncView.
            }
          },
          child: AsyncView(
            value: pulse,
            onRetry: () => ref.invalidate(pulseProvider(tripId)),
            builder: (data) => ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                Eyebrow(formatDayLabel(data.date)),
                const SizedBox(height: 8),
                Text('How is the group feeling?', style: context.texts.headlineLarge),
                const SizedBox(height: 8),
                Text(
                  'Each traveller shares their own energy, budget comfort and time. '
                  'SAFAR uses these signals to shape recommendations.',
                  style: context.texts.bodySmall?.copyWith(height: 1.5),
                ),
                const SizedBox(height: 16),
                _CoverageCard(
                  shared: data.coverageShared,
                  members: data.coverageMembers,
                ),
                const SizedBox(height: 12),
                InfoBanner(text: data.privacy, icon: Icons.lock_outline),
                const SizedBox(height: 18),
                if (data.myPulse != null)
                  _MyPulseCard(
                    pulse: data.myPulse!,
                    onEdit: () => _openEditor(context, ref),
                  )
                else
                  SafarCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Eyebrow('Not shared yet'),
                        const SizedBox(height: 8),
                        Text(
                          'Add your pulse so the group plan respects how you feel today.',
                          style: context.texts.bodyMedium,
                        ),
                        const SizedBox(height: 14),
                        FilledButton(
                          onPressed: () => _openEditor(context, ref),
                          child: const Text('Share my pulse'),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 22),
                const SectionHeader(
                  eyebrow: 'Shared today',
                  title: 'Group pulse',
                ),
                if (data.items.isEmpty)
                  const SafarEmpty(
                    icon: Icons.waves_outlined,
                    title: 'No pulses shared yet',
                    message:
                        'Pulses are private by default. Members appear here only after sharing.',
                  )
                else
                  for (final item in data.items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _PulseTile(pulse: item),
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String formatDayLabel(String raw) {
  final weekday = formatWeekday(raw);
  final date = formatDate(raw);
  return weekday.isEmpty ? date : '$weekday · $date';
}

class _CoverageCard extends StatelessWidget {
  const _CoverageCard({required this.shared, required this.members});

  final int shared;
  final int members;

  @override
  Widget build(BuildContext context) {
    final palette = context.safar;
    final ratio = members == 0 ? 0.0 : (shared / members).clamp(0.0, 1.0);
    return SafarCard(
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: palette.jadeSoft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.groups_2_outlined, color: palette.jade, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  members == 0 ? 'No members yet' : '$shared of $members shared',
                  style: context.texts.titleMedium,
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 6,
                    backgroundColor: palette.line,
                    color: palette.jade,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Coverage helps SAFAR avoid over-fitting to one person.',
                  style: context.texts.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MyPulseCard extends StatelessWidget {
  const _MyPulseCard({required this.pulse, required this.onEdit});

  final Pulse pulse;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final palette = context.safar;
    return SafarCard(
      color: palette.emberSoft.withValues(alpha: 0.6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: Eyebrow('Your pulse')),
              StatusChip(
                'Energy ${pulse.energy}/5',
                tone: ChipTone.ember,
                icon: Icons.bolt,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final interest in pulse.interests)
                StatusChip(interest, tone: ChipTone.neutral),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            [
              if (pulse.availableMinutes != null)
                '${pulse.availableMinutes} min available',
              'Budget comfort ${pulse.budgetComfort}/5',
              if (pulse.radiusKm != null)
                '${pulse.radiusKm!.toStringAsFixed(0)} km radius',
            ].join(' · '),
            style: context.texts.bodySmall,
          ),
          if (pulse.note != null && pulse.note!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('“${pulse.note}”', style: context.texts.bodyMedium),
          ],
          const SizedBox(height: 14),
          OutlinedButton(onPressed: onEdit, child: const Text('Update pulse')),
        ],
      ),
    );
  }
}

class _PulseTile extends StatelessWidget {
  const _PulseTile({required this.pulse});

  final Pulse pulse;

  @override
  Widget build(BuildContext context) {
    final palette = context.safar;
    final name = pulse.isSelf ? 'You' : (pulse.authorName ?? 'A traveller');
    return SafarCard(
      padding: const EdgeInsets.all(15),
      radius: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SafarAvatar(name: name, size: 34, highlight: pulse.isSelf),
              const SizedBox(width: 10),
              Expanded(child: Text(name, style: context.texts.titleSmall)),
              for (var i = 0; i < 5; i++)
                Padding(
                  padding: const EdgeInsets.only(left: 2),
                  child: Icon(
                    Icons.circle,
                    size: 7,
                    color: i < pulse.energy ? palette.ember : palette.line,
                  ),
                ),
            ],
          ),
          if (pulse.interests.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final interest in pulse.interests)
                  StatusChip(interest, tone: ChipTone.neutral),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Text(
            [
              if (pulse.availableMinutes != null)
                '${pulse.availableMinutes} min',
              'Budget ${pulse.budgetComfort}/5',
              if (pulse.radiusKm != null)
                '${pulse.radiusKm!.toStringAsFixed(0)} km',
            ].join(' · '),
            style: context.texts.bodySmall,
          ),
          if (pulse.note != null && pulse.note!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('“${pulse.note}”', style: context.texts.bodySmall),
          ],
        ],
      ),
    );
  }
}

class _PulseSheet extends ConsumerStatefulWidget {
  const _PulseSheet({required this.tripId});

  final String tripId;

  @override
  ConsumerState<_PulseSheet> createState() => _PulseSheetState();
}

class _PulseSheetState extends ConsumerState<_PulseSheet> {
  late final Pulse? _existing = ref
      .read(pulseProvider(widget.tripId))
      .valueOrNull
      ?.myPulse;
  late double _energy = (_existing?.energy ?? 3).toDouble();
  late int _budget = _existing?.budgetComfort ?? 3;
  late double _radius = _existing?.radiusKm ?? 10;
  late int _minutes = _existing?.availableMinutes ?? 240;
  late final Set<String> _interests = {...?_existing?.interests};
  late final Set<String> _activityPrefs = {...?_existing?.activityPrefs};
  late final _note = TextEditingController(text: _existing?.note ?? '');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(tripRepositoryProvider)
          .savePulse(
            widget.tripId,
            energy: _energy.round(),
            interests: _interests.toList(),
            availableMinutes: _minutes,
            budgetComfort: _budget,
            radiusKm: _radius,
            activityPrefs: _activityPrefs.toList(),
            note: _note.text.trim().isEmpty ? null : _note.text.trim(),
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
    final palette = context.safar;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SafarSheetHeader(
            title: 'Your pulse',
            subtitle: 'Private to you until you share it. Group members only see what you choose.',
          ),
          Text('Energy · ${_energy.round()}/5', style: context.texts.titleSmall),
          Slider(
            value: _energy,
            min: 1,
            max: 5,
            divisions: 4,
            label: _energy.round().toString(),
            onChanged: (value) => setState(() => _energy = value),
          ),
          const SizedBox(height: 10),
          Text('Available time · $_minutes min', style: context.texts.titleSmall),
          Slider(
            value: _minutes.toDouble(),
            min: 60,
            max: 720,
            divisions: 11,
            label: '$_minutes',
            onChanged: (value) => setState(() => _minutes = value.round()),
          ),
          const SizedBox(height: 10),
          Text(
            'Budget comfort · $_budget/5',
            style: context.texts.titleSmall,
          ),
          Slider(
            value: _budget.toDouble(),
            min: 1,
            max: 5,
            divisions: 4,
            label: '$_budget',
            onChanged: (value) => setState(() => _budget = value.round()),
          ),
          const SizedBox(height: 10),
          Text(
            'Travel radius · ${_radius.toStringAsFixed(0)} km',
            style: context.texts.titleSmall,
          ),
          Slider(
            value: _radius,
            min: 1,
            max: 40,
            divisions: 13,
            label: _radius.toStringAsFixed(0),
            onChanged: (value) => setState(() => _radius = value),
          ),
          const SizedBox(height: 8),
          const Eyebrow('Interests today'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final interest in _interestOptions)
                FilterChip(
                  label: Text(interest),
                  selected: _interests.contains(interest),
                  onSelected: (selected) => setState(() {
                    selected
                        ? _interests.add(interest)
                        : _interests.remove(interest);
                  }),
                ),
            ],
          ),
          const SizedBox(height: 16),
          const Eyebrow('Activity pace'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final pref in const ['slow', 'balanced', 'active'])
                FilterChip(
                  label: Text(pref),
                  selected: _activityPrefs.contains(pref),
                  onSelected: (selected) => setState(() {
                    selected
                        ? _activityPrefs.add(pref)
                        : _activityPrefs.remove(pref);
                  }),
                ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _note,
            maxLines: 3,
            maxLength: 280,
            decoration: const InputDecoration(
              labelText: 'Anything the plan should know?',
              hintText: 'e.g. I need a quieter afternoon today',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            InfoBanner(
              text: _error!,
              tone: ChipTone.rose,
              icon: Icons.error_outline,
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Share pulse'),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.lock_outline, size: 14, color: palette.faint),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Budgets and exact preferences are never shown to other members.',
                  style: context.texts.labelSmall,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
