import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/safar_theme.dart';
import 'trip_channel.dart';
import 'trip_realtime.dart';

/// Compact indicator for the trip's live channel. Tapping while reconnecting
/// retries immediately; pull-to-refresh remains the fallback when it is closed.
class TripLiveChip extends ConsumerWidget {
  const TripLiveChip({super.key, required this.tripId, this.compact = false});

  final String tripId;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.safar;
    final live = ref.watch(tripRealtimeProvider(tripId));
    final (label, color, icon) = switch (live.status) {
      RealtimeStatus.live => ('Live', palette.jade, Icons.sensors_rounded),
      RealtimeStatus.connecting => (
        'Connecting',
        palette.muted,
        Icons.sensors_outlined,
      ),
      RealtimeStatus.reconnecting => (
        'Reconnecting',
        palette.ember,
        Icons.sync_problem_rounded,
      ),
      RealtimeStatus.closed => (
        'Not live',
        palette.faint,
        Icons.sensors_off_rounded,
      ),
      RealtimeStatus.idle => (
        'Not live',
        palette.faint,
        Icons.sensors_off_rounded,
      ),
    };

    final event = live.lastEvent;
    final tooltip = live.reconnecting
        ? 'Tap to retry live updates'
        : live.live
        ? (event == null
              ? 'Live updates for this trip workspace'
              : '${event.event}${event.actor.isEmpty ? '' : ' · ${event.actor}'}')
        : 'Live updates are offline. Pull to refresh for the latest plan.';

    final chip = Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: context.texts.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );

    return Tooltip(
      message: tooltip,
      child: live.reconnecting
          ? InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: () => ref
                  .read(tripRealtimeProvider(tripId).notifier)
                  .reconnectNow(),
              child: chip,
            )
          : chip,
    );
  }
}
