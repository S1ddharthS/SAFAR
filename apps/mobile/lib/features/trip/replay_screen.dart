import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/memories.dart';
import '../../core/network/api_exception.dart';
import '../../core/providers.dart';
import '../../core/theme/safar_theme.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/safar_widgets.dart';

class ReplayScreen extends ConsumerStatefulWidget {
  const ReplayScreen({super.key, required this.tripId});

  final String tripId;

  @override
  ConsumerState<ReplayScreen> createState() => _ReplayScreenState();
}

class _ReplayScreenState extends ConsumerState<ReplayScreen> {
  bool _busy = false;

  Future<void> _openTravelBook() async {
    setState(() => _busy = true);
    try {
      final book = await ref
          .read(memoryRepositoryProvider)
          .travelBook(widget.tripId);
      if (!mounted) return;
      await showSafarSheet<void>(
        context,
        builder: (_) => SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SafarSheetHeader(
                title: 'Travel book',
                subtitle:
                    'Generated from approved events and memories you are allowed to see.',
              ),
              SelectableText(book, style: context.texts.bodyMedium),
              const SizedBox(height: 12),
              const InfoBanner(
                icon: Icons.privacy_tip_outlined,
                text:
                    'Private memories and unapproved groups are excluded. Nothing here is shared publicly.',
              ),
            ],
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

  @override
  Widget build(BuildContext context) {
    final replay = ref.watch(replayProvider(widget.tripId));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Journey Replay'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(replayProvider(widget.tripId)),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(replayProvider(widget.tripId));
            try {
              await ref.read(replayProvider(widget.tripId).future);
            } on Object {
              // Rendered by AsyncView.
            }
          },
          child: AsyncView(
            value: replay,
            onRetry: () => ref.invalidate(replayProvider(widget.tripId)),
            builder: (data) => ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                const Eyebrow('Look back'),
                const SizedBox(height: 8),
                Text(data.trip.name, style: context.texts.headlineLarge),
                const SizedBox(height: 4),
                Text(
                  '${data.trip.destination} · ${formatDate(data.trip.startDate)} → ${formatDate(data.trip.endDate)}',
                  style: context.texts.bodySmall,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: StatTile(
                        label: 'Days',
                        value: '${data.stats.daysRecorded}',
                        icon: Icons.calendar_today_outlined,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: StatTile(
                        label: 'Memories',
                        value: '${data.stats.memories}',
                        icon: Icons.photo_library_outlined,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: StatTile(
                        label: 'Approved',
                        value: '${data.stats.approvedEvents}',
                        icon: Icons.verified_outlined,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: StatTile(
                        label: 'Media',
                        value: '${data.stats.media}',
                        icon: Icons.image_outlined,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: StatTile(
                        label: 'Contributors',
                        value: '${data.stats.contributors}',
                        icon: Icons.people_outline,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(child: SizedBox.shrink()),
                  ],
                ),
                const SizedBox(height: 14),
                InfoBanner(text: data.permissions, icon: Icons.lock_outline),
                const SizedBox(height: 10),
                InfoBanner(
                  text: data.formatNote,
                  icon: Icons.auto_stories_outlined,
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _openTravelBook,
                    icon: const Icon(Icons.menu_book_outlined, size: 18),
                    label: const Text('Open travel book'),
                  ),
                ),
                const SizedBox(height: 22),
                SectionHeader(
                  eyebrow: '${data.days.length} days recorded',
                  title: 'The replay',
                ),
                if (data.days.isEmpty)
                  const SafarEmpty(
                    icon: Icons.replay_outlined,
                    title: 'Nothing to replay yet',
                    message:
                        'Add memories and approve memory groups during the trip to build the replay.',
                  )
                else
                  for (final day in data.days)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _ReplayDayCard(day: day),
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReplayDayCard extends StatelessWidget {
  const _ReplayDayCard({required this.day});

  final ReplayDay day;

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
                child: Text(
                  formatDate(day.date),
                  style: context.texts.titleMedium,
                ),
              ),
              Text(formatWeekday(day.date), style: context.texts.labelSmall),
            ],
          ),
          if (day.items.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final item in day.items)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Text(
                      item.startTime,
                      style: context.texts.labelSmall?.copyWith(
                        color: palette.ember,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        item.title,
                        style: context.texts.bodyMedium,
                      ),
                    ),
                    if (item.protected)
                      Icon(
                        Icons.lock_clock_outlined,
                        size: 14,
                        color: palette.jade,
                      ),
                  ],
                ),
              ),
          ],
          if (day.memories.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Eyebrow('Memories'),
            const SizedBox(height: 6),
            for (final memory in day.memories)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  memory.textContent?.isNotEmpty == true
                      ? '“${memory.textContent}”'
                      : '${memory.kind} memory',
                  style: context.texts.bodySmall,
                ),
              ),
          ],
          if (day.events.isNotEmpty) ...[
            const SizedBox(height: 6),
            const Eyebrow('Groups'),
            const SizedBox(height: 6),
            for (final event in day.events)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.auto_awesome_outlined,
                      size: 13,
                      color: palette.faint,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(event.title, style: context.texts.titleSmall),
                          if (event.summary != null)
                            Text(
                              event.summary!,
                              style: context.texts.bodySmall,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
