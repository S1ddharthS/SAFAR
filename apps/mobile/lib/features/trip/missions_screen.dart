import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/trip.dart';
import '../../core/providers.dart';
import '../../core/theme/safar_theme.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/safar_widgets.dart';

class MissionsScreen extends ConsumerStatefulWidget {
  const MissionsScreen({super.key, required this.tripId});

  final String tripId;

  @override
  ConsumerState<MissionsScreen> createState() => _MissionsScreenState();
}

class _MissionsScreenState extends ConsumerState<MissionsScreen> {
  bool _busy = false;

  Future<void> _act(Mission mission, String action) async {
    if (action == 'disable') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Disable this mission?'),
          content: Text(
            '“${mission.title}” stops being offered to the group. Past '
            'completions remain in the trip history.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: context.safar.rose,
              ),
              child: const Text('Disable'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    setState(() => _busy = true);
    try {
      final repository = ref.read(tripRepositoryProvider);
      switch (action) {
        case 'join':
          await repository.joinMission(widget.tripId, mission.id);
        case 'complete':
          await repository.completeMission(widget.tripId, mission.id);
        default:
          await repository.disableMission(widget.tripId, mission.id);
      }
      ref.invalidate(missionsProvider(widget.tripId));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(switch (action) {
            'join' => 'Mission joined.',
            'complete' => 'Mission marked complete. It is self-reported.',
            _ => 'Mission disabled.',
          }),
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
    final palette = context.safar;
    final role = ref.watch(itineraryProvider(widget.tripId)).valueOrNull?.myRole;
    final canManage = role == 'owner' || role == 'admin';
    return Scaffold(
      appBar: AppBar(title: const Text('Missions')),
      body: AsyncView<List<Mission>>(
        value: ref.watch(missionsProvider(widget.tripId)),
        onRetry: () => ref.invalidate(missionsProvider(widget.tripId)),
        skeleton: const SkeletonList(count: 2, itemHeight: 96),
        builder: (missions) {
          final active = missions.where((m) => m.status == 'active').toList();
          final others = missions.where((m) => m.status != 'active').toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 36),
            children: [
              const InfoBanner(
                text:
                    'Optional, self-reported invitations to try something new. '
                    'Completing one never changes the confirmed plan or your '
                    'standing in the group.',
                icon: Icons.flag_outlined,
              ),
              const SizedBox(height: 16),
              if (active.isEmpty)
                const SafarEmpty(
                  icon: Icons.flag_outlined,
                  title: 'No missions right now',
                  message:
                      'Missions appear when the group has room for an optional '
                      'challenge.',
                )
              else
                for (final mission in active)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _MissionCard(
                      mission: mission,
                      busy: _busy,
                      canManage: canManage,
                      onAct: (action) => _act(mission, action),
                    ),
                  ),
              if (others.isNotEmpty) ...[
                const SizedBox(height: 14),
                const SectionHeader(eyebrow: 'History', title: 'Past missions'),
                for (final mission in others)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SafarCard(
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  mission.title,
                                  style: context.texts.titleSmall,
                                ),
                                Text(
                                  mission.myStatus == 'completed'
                                      ? 'You completed this'
                                      : 'Not completed',
                                  style: context.texts.labelSmall,
                                ),
                              ],
                            ),
                          ),
                          StatusChip(
                            mission.myStatus == 'completed'
                                ? 'completed'
                                : mission.status,
                            tone: mission.myStatus == 'completed'
                                ? ChipTone.jade
                                : ChipTone.neutral,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
              if (active.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.info_outline, size: 14, color: palette.faint),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Missions respect your accessibility needs and the '
                        'trip pact.',
                        style: context.texts.labelSmall,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _MissionCard extends StatelessWidget {
  const _MissionCard({
    required this.mission,
    required this.busy,
    required this.canManage,
    required this.onAct,
  });

  final Mission mission;
  final bool busy;
  final bool canManage;
  final ValueChanged<String> onAct;

  @override
  Widget build(BuildContext context) {
    final constraints = mission.constraints;
    return SafarCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(mission.title, style: context.texts.titleSmall),
              ),
              if (mission.completed)
                const StatusChip('Completed', tone: ChipTone.jade)
              else if (mission.myStatus != null)
                const StatusChip('Joined', tone: ChipTone.ember)
              else
                const StatusChip('Optional'),
            ],
          ),
          const SizedBox(height: 4),
          Text(mission.description, style: context.texts.bodySmall),
          if (constraints != null) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (constraints.maxCost != null)
                  StatusChip(
                    '≤ ${formatMoney(constraints.maxCost)}',
                    tone: ChipTone.neutral,
                  ),
                if (constraints.maxEffort != null)
                  StatusChip('Effort ≤ ${constraints.maxEffort}'),
                if (constraints.tag != null) StatusChip(constraints.tag!),
                if (constraints.respectAccessibility)
                  const StatusChip('Accessible', tone: ChipTone.jade),
                if (constraints.suggestedActivity != null)
                  StatusChip('Suggested: ${constraints.suggestedActivity}'),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              if (!mission.completed && mission.myStatus == null)
                Expanded(
                  child: FilledButton(
                    onPressed: busy ? null : () => onAct('join'),
                    child: const Text('Join mission'),
                  ),
                ),
              if (!mission.completed && mission.myStatus != null) ...[
                Expanded(
                  child: FilledButton(
                    onPressed: busy ? null : () => onAct('complete'),
                    child: const Text('Mark complete'),
                  ),
                ),
              ],
              if (canManage) ...[
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Disable mission',
                  onPressed: busy ? null : () => onAct('disable'),
                  icon: Icon(
                    Icons.block_outlined,
                    size: 19,
                    color: context.safar.rose,
                  ),
                ),
              ],
            ],
          ),
          if (mission.selfReported)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Self-reported — no proof is required or implied.',
                style: context.texts.labelSmall?.copyWith(
                  color: context.safar.faint,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
