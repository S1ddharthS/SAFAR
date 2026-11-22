import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/memories.dart';
import '../../core/network/api_exception.dart';
import '../../core/providers.dart';
import '../../core/theme/safar_theme.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/safar_widgets.dart';

class StudioScreen extends ConsumerStatefulWidget {
  const StudioScreen({super.key, required this.tripId});

  final String tripId;

  @override
  ConsumerState<StudioScreen> createState() => _StudioScreenState();
}

class _StudioScreenState extends ConsumerState<StudioScreen> {
  bool _busy = false;

  Future<void> _suggest() async {
    setState(() => _busy = true);
    try {
      final created = await ref
          .read(memoryRepositoryProvider)
          .suggestEvents(widget.tripId);
      ref.invalidate(studioProvider(widget.tripId));
      ref.invalidate(replayProvider(widget.tripId));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            created.isEmpty
                ? 'No new memory groups found yet.'
                : '${created.length} suggestion${created.length == 1 ? '' : 's'} awaiting approval.',
          ),
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _approve(StudioEvent event) async {
    setState(() => _busy = true);
    try {
      await ref
          .read(memoryRepositoryProvider)
          .approveEvent(widget.tripId, event.id);
      ref.invalidate(studioProvider(widget.tripId));
      ref.invalidate(replayProvider(widget.tripId));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Memory group approved for the travel book.')),
      );
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
    final studio = ref.watch(studioProvider(widget.tripId));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Memory Studio'),
        actions: [
          IconButton(
            tooltip: 'Memories',
            onPressed: () => context.push('/trips/${widget.tripId}/memories'),
            icon: const Icon(Icons.photo_library_outlined),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(studioProvider(widget.tripId));
            try {
              await ref.read(studioProvider(widget.tripId).future);
            } on Object {
              // Rendered by AsyncView.
            }
          },
          child: AsyncView(
            value: studio,
            onRetry: () => ref.invalidate(studioProvider(widget.tripId)),
            builder: (data) => ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                const Eyebrow('Quiet intelligence'),
                const SizedBox(height: 8),
                Text('Memory Studio', style: context.texts.headlineLarge),
                const SizedBox(height: 8),
                Text(
                  'Group moments from the memories you already chose to share. Suggested groups '
                  'stay unapproved until a contributor or trip admin confirms them.',
                  style: context.texts.bodySmall?.copyWith(height: 1.5),
                ),
                const SizedBox(height: 16),
                InfoBanner(
                  text: data.disclosure,
                  icon: Icons.info_outline,
                ),
                const SizedBox(height: 16),
                SafarCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Eyebrow('This trip'),
                      const SizedBox(height: 8),
                      Text(
                        '${data.memories.length} memories · ${data.events.length} groups',
                        style: context.texts.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton(
                              onPressed: _busy ? null : _suggest,
                              child: const Text('Suggest groups'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => context.push(
                                '/trips/${widget.tripId}/memories',
                              ),
                              child: const Text('Add memories'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const SectionHeader(
                  eyebrow: 'Groups',
                  title: 'Memory events',
                ),
                if (data.events.isEmpty)
                  const SafarEmpty(
                    icon: Icons.auto_awesome_outlined,
                    title: 'No groups yet',
                    message:
                        'Add a few memories, then ask SAFAR to group them by time and place.',
                  )
                else
                  for (final event in data.events)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _EventCard(
                        event: event,
                        busy: _busy,
                        onApprove: () => _approve(event),
                      ),
                    ),
                const SizedBox(height: 20),
                const SectionHeader(
                  eyebrow: 'What is on',
                  title: 'Capabilities',
                ),
                SafarCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final entry in data.capabilities.entries)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                entry.value == false
                                    ? Icons.remove_circle_outline
                                    : Icons.check_circle_outline,
                                size: 16,
                                color: entry.value == false
                                    ? context.safar.faint
                                    : context.safar.jade,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      titleCase(entry.key),
                                      style: context.texts.titleSmall,
                                    ),
                                    Text(
                                      '${entry.value}',
                                      style: context.texts.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({
    required this.event,
    required this.busy,
    required this.onApprove,
  });

  final StudioEvent event;
  final bool busy;
  final VoidCallback onApprove;

  @override
  Widget build(BuildContext context) {
    final approved = event.status == 'approved';
    return SafarCard(
      padding: const EdgeInsets.all(15),
      radius: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(event.title, style: context.texts.titleMedium),
              ),
              StatusChip(
                event.status,
                tone: approved ? ChipTone.jade : ChipTone.ember,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${formatDate(event.startAt)} · ${formatClock(event.startAt)}'
            '${event.memoryIds.isEmpty ? '' : ' · ${event.memoryIds.length} memories'}',
            style: context.texts.bodySmall,
          ),
          if (event.summary != null && event.summary!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(event.summary!, style: context.texts.bodySmall),
          ],
          if (!approved) ...[
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: busy ? null : onApprove,
              child: const Text('Approve group'),
            ),
          ],
        ],
      ),
    );
  }
}
