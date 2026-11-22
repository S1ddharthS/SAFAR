import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/discovery.dart';
import '../../core/providers.dart';
import '../../core/theme/safar_theme.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/safar_widgets.dart';

class ActivityCard extends ConsumerWidget {
  const ActivityCard({
    super.key,
    required this.item,
    this.onTap,
    this.compact = false,
  });

  final SearchItem item;
  final VoidCallback? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.safar;
    final activity = item.activity;
    final image = ref.watch(apiClientProvider).mediaUrl(activity.imageUrl);
    final facts = [
      if (activity.priceEstimate > 0)
        formatMoney(activity.priceEstimate, activity.currency),
      if (activity.durationMinutes > 0) _duration(activity.durationMinutes),
      if (activity.indoor) 'Indoor',
      if (activity.wheelchairAccessible == true) 'Step-free',
    ];

    return SafarCard(
      onTap: onTap,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!compact)
            Stack(
              children: [
                SafarImage(url: image, height: 150, radius: 22),
                Positioned(
                  left: 12,
                  top: 12,
                  child: StatusChip(
                    item.provenance.toLowerCase() == 'verified'
                        ? 'Verified'
                        : 'Estimated',
                    tone: item.provenance.toLowerCase() == 'verified'
                        ? ChipTone.jade
                        : ChipTone.neutral,
                  ),
                ),
                if (item.personalFit > 0)
                  Positioned(
                    right: 12,
                    top: 12,
                    child: StatusChip(
                      '${item.personalFit}% fit',
                      tone: ChipTone.ember,
                    ),
                  ),
              ],
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        activity.name,
                        style: context.texts.titleMedium,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (activity.iconic)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Icon(
                          Icons.workspace_premium_outlined,
                          size: 17,
                          color: palette.ember,
                        ),
                      ),
                  ],
                ),
                if (activity.description.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    activity.description,
                    maxLines: compact ? 2 : 3,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.bodySmall?.copyWith(height: 1.45),
                  ),
                ],
                if (facts.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final fact in facts)
                        StatusChip(fact, tone: ChipTone.neutral),
                    ],
                  ),
                ],
                if (activity.tags.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    activity.tags.take(4).join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.labelSmall,
                  ),
                ],
                if (item.respectNote != null &&
                    item.respectNote!.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  InfoBanner(
                    text: item.respectNote!,
                    icon: Icons.spa_outlined,
                    tone: ChipTone.jade,
                  ),
                ],
                if (item.similarTo != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Similar to ${item.similarTo}',
                    style: context.texts.labelSmall,
                  ),
                ],
                if (item.catalogFreshness != null) ...[
                  const SizedBox(height: 8),
                  SourceLabel(
                    source: item.catalogFreshness!.label,
                    confidence: item.catalogFreshness!.lastVerifiedAt == null
                        ? null
                        : 'verified ${formatDateShort(item.catalogFreshness!.lastVerifiedAt)}',
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _duration(int minutes) {
    if (minutes < 60) return '${minutes}m';
    final hours = minutes / 60;
    return hours == hours.roundToDouble()
        ? '${hours.round()}h'
        : '${hours.toStringAsFixed(1)}h';
  }
}

/// Opens the place evidence screen, choosing a trip first because reports and
/// forecasts are scoped to trips by the API.
Future<void> openPlaceWithTripPicker(
  BuildContext context,
  WidgetRef ref, {
  required String activityId,
  required String activityName,
}) async {
  final trips = ref.read(tripsProvider).valueOrNull ?? const [];
  if (trips.isEmpty) {
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Choose a trip first'),
        content: const Text(
          'Place evidence, access details and crowd forecasts are scoped to a trip. '
          'Create a trip to see them for this place.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              context.push('/trips/new');
            },
            child: const Text('Create a trip'),
          ),
        ],
      ),
    );
    return;
  }
  if (!context.mounted) return;
  await showSafarSheet<void>(
    context,
    builder: (sheetContext) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SafarSheetHeader(
          title: 'Open in a trip',
          subtitle: 'Evidence for “$activityName” is shown per trip.',
        ),
        for (final trip in trips)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SafarActionTile(
              icon: Icons.luggage_outlined,
              label: trip.name,
              caption: trip.dateRangeLabel,
              onTap: () {
                Navigator.of(sheetContext).pop();
                context.push(
                  '/trips/${trip.id}/places/$activityId',
                );
              },
            ),
          ),
      ],
    ),
  );
}
