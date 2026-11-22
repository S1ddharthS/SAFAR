import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/discovery.dart';
import '../../core/models/trip.dart';
import '../../core/providers.dart';
import '../../core/theme/safar_theme.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/safar_widgets.dart';
import 'widgets/activity_search.dart';

class BranchesScreen extends ConsumerStatefulWidget {
  const BranchesScreen({super.key, required this.tripId});

  final String tripId;

  @override
  ConsumerState<BranchesScreen> createState() => _BranchesScreenState();
}

class _BranchesScreenState extends ConsumerState<BranchesScreen> {
  bool _busy = false;

  Future<void> _create(List<Member> members, String? destinationId) async {
    final name = TextEditingController();
    final reunionAt = TextEditingController();
    final reunionPlace = TextEditingController();
    final selected = <String>{};
    Activity? activity;

    final submitted = await showSafarSheet<bool>(
      context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SafarSheetHeader(
                title: 'Create a branch',
                subtitle:
                    'Split the group for part of the day and plan a reunion. '
                    'The confirmed itinerary is unchanged.',
              ),
              TextField(
                controller: name,
                maxLength: 80,
                decoration: const InputDecoration(
                  labelText: 'Branch name',
                  hintText: 'Museum morning',
                ),
              ),
              const SizedBox(height: 8),
              Text('Who splits off', style: context.texts.labelMedium),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final member in members)
                    FilterChip(
                      label: Text(member.displayName),
                      selected: selected.contains(member.id),
                      onSelected: (value) => setSheetState(() {
                        if (value) {
                          selected.add(member.id);
                        } else {
                          selected.remove(member.id);
                        }
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Text('Branch activity (optional)', style: context.texts.labelMedium),
              const SizedBox(height: 6),
              ActivitySearchList(
                destinationId: destinationId,
                trailing: (candidate) => Icon(
                  activity?.id == candidate.id
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  size: 20,
                  color: activity?.id == candidate.id
                      ? context.safar.jade
                      : context.safar.faint,
                ),
                onTap: (candidate) => setSheetState(() => activity = candidate),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: reunionAt,
                      keyboardType: TextInputType.datetime,
                      decoration: const InputDecoration(
                        labelText: 'Reunion time',
                        hintText: '18:00',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: reunionPlace,
                      maxLength: 120,
                      decoration: const InputDecoration(
                        labelText: 'Reunion place',
                        counterText: '',
                      ),
                    ),
                  ),
                ],
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
                      onPressed: () => Navigator.of(sheetContext).pop(true),
                      child: const Text('Create branch'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    final title = name.text.trim();
    final time = reunionAt.text.trim();
    final place = reunionPlace.text.trim();
    name.dispose();
    reunionAt.dispose();
    reunionPlace.dispose();
    if (submitted != true) return;
    if (title.isEmpty) {
      _snack('Give the branch a name.');
      return;
    }
    if (selected.isEmpty) {
      _snack('Choose at least one active member for the branch.');
      return;
    }
    if (time.isNotEmpty &&
        !RegExp(r'^[0-2][0-9]:[0-5][0-9]$').hasMatch(time)) {
      _snack('Use a 24-hour reunion time such as 18:00.');
      return;
    }
    setState(() => _busy = true);
    try {
      final creation = await ref
          .read(tripRepositoryProvider)
          .createBranch(
            widget.tripId,
            name: title,
            memberIds: selected.toList(),
            activityId: activity?.id,
            reunionAt: time.isEmpty ? null : time,
            reunionPlace: place.isEmpty ? null : place,
          );
      ref.invalidate(branchesProvider(widget.tripId));
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Branch created'),
          content: Text(creation.feasibility.note.isEmpty
              ? 'The branch is saved. Reunion feasibility is unverified.'
              : creation.feasibility.note),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } on Object catch (error) {
      _snack(error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.safar;
    final trip = ref.watch(tripProvider(widget.tripId));
    final members = ref.watch(membersProvider(widget.tripId));
    final branches = ref.watch(branchesProvider(widget.tripId));
    final memberNames = {
      for (final member in members.valueOrNull ?? const <Member>[])
        member.id: member.displayName,
    };
    return Scaffold(
      appBar: AppBar(title: const Text('Branches')),
      body: AsyncView<List<Branch>>(
        value: branches,
        onRetry: () => ref.invalidate(branchesProvider(widget.tripId)),
        skeleton: const SkeletonList(count: 2, itemHeight: 76),
        builder: (items) {
          final activeMembers = (members.valueOrNull ?? const <Member>[])
              .where((member) => member.status == 'active')
              .toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 36),
            children: [
              const InfoBanner(
                text:
                    'Branches let the group split without changing the '
                    'confirmed plan. Reunion feasibility is an estimate only '
                    'when both places exist in the catalog.',
                icon: Icons.call_split,
              ),
              const SizedBox(height: 16),
              SectionHeader(
                eyebrow: 'Group',
                title: items.isEmpty ? 'No branches yet' : 'Open branches',
              ),
              if (items.isEmpty)
                SafarEmpty(
                  icon: Icons.alt_route,
                  title: 'Nobody has split off',
                  message: 'Create a branch when part of the group wants a '
                      'different activity.',
                  action: activeMembers.isEmpty
                      ? null
                      : FilledButton.icon(
                          onPressed: _busy
                              ? null
                              : () => _create(
                                  activeMembers,
                                  trip.valueOrNull?.destinationId,
                                ),
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Create a branch'),
                        ),
                )
              else ...[
                for (final branch in items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: SafarCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  branch.name,
                                  style: context.texts.titleSmall,
                                ),
                              ),
                              StatusChip(
                                branch.status,
                                tone: branch.status == 'open'
                                    ? ChipTone.jade
                                    : ChipTone.neutral,
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            branch.memberIds.isEmpty
                                ? 'No members recorded'
                                : branch.memberIds
                                      .map((id) => memberNames[id] ?? 'Member')
                                      .join(' · '),
                            style: context.texts.labelSmall,
                          ),
                          if (branch.reunionAt != null ||
                              branch.reunionPlace != null) ...[
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Icon(
                                  Icons.handshake_outlined,
                                  size: 15,
                                  color: palette.jade,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    [
                                      if (branch.reunionAt != null)
                                        'Reunion ${formatTime(branch.reunionAt)}',
                                      if (branch.reunionPlace != null)
                                        branch.reunionPlace!,
                                    ].join(' at '),
                                    style: context.texts.bodySmall,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 6),
                OutlinedButton.icon(
                  onPressed: _busy || activeMembers.isEmpty
                      ? null
                      : () => _create(
                          activeMembers,
                          trip.valueOrNull?.destinationId,
                        ),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Create a branch'),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
