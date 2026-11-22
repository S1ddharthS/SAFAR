import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/social.dart';
import '../../core/providers.dart';
import '../../core/theme/safar_theme.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/safar_widgets.dart';

class ThreadScreen extends ConsumerWidget {
  const ThreadScreen({super.key, required this.tripId});

  final String tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.safar;
    return Scaffold(
      appBar: AppBar(title: const Text('Journey thread')),
      body: AsyncView<ThreadResponse>(
        value: ref.watch(threadProvider),
        onRetry: () => ref.invalidate(threadProvider),
        skeleton: const SkeletonList(count: 2, itemHeight: 88),
        builder: (thread) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 36),
          children: [
            const InfoBanner(
              text:
                  'Your thread is private to you: it links places you keep '
                  'returning to across trips. It is never shown to the group '
                  'or to other travellers.',
              icon: Icons.auto_stories_outlined,
            ),
            const SizedBox(height: 16),
            SafarCard(
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: palette.emberSoft,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      Icons.auto_stories_outlined,
                      size: 22,
                      color: palette.ember,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          thread.completedTrips == 1
                              ? '1 journey completed'
                              : '${thread.completedTrips} journeys completed',
                          style: context.texts.titleSmall,
                        ),
                        Text(
                          thread.note.isEmpty
                              ? 'Traditions appear as you repeat places you love.'
                              : thread.note,
                          style: context.texts.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const SectionHeader(
              eyebrow: 'Traditions',
              title: 'Places that keep calling',
            ),
            if (thread.traditions.isEmpty)
              const SafarEmpty(
                icon: Icons.bookmark_border,
                title: 'No traditions yet',
                message:
                    'When you visit the same kind of place across journeys, it '
                    'shows up here as part of your travel thread.',
              )
            else
              for (final tradition in thread.traditions)
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
                                tradition.name,
                                style: context.texts.titleSmall,
                              ),
                            ),
                            if (tradition.priceEstimate > 0)
                              StatusChip(formatMoney(tradition.priceEstimate)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${tradition.durationMinutes} min per visit',
                          style: context.texts.labelSmall,
                        ),
                        if (tradition.sentiments.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final sentiment
                                  in tradition.sentiments.take(5))
                                StatusChip(sentiment, tone: ChipTone.jade),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
