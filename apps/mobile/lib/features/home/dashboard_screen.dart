import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/trip.dart';
import '../../core/providers.dart';
import '../../core/theme/safar_theme.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/safar_widgets.dart';
import '../auth/auth_controller.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.safar;
    final auth = ref.watch(authControllerProvider);
    final trips = ref.watch(tripsProvider);
    final me = ref.watch(meProvider);
    final unread = ref.watch(notificationsProvider).valueOrNull?.unread ?? 0;
    final name = auth.user?.displayName ?? me.valueOrNull?.user.displayName ?? 'traveller';

    Future<void> refresh() async {
      ref.invalidate(tripsProvider);
      ref.invalidate(meProvider);
      ref.invalidate(notificationsProvider);
      try {
        await ref.read(tripsProvider.future);
      } on Object {
        // The error surface is rendered by AsyncView.
      }
    }

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            children: [
              Row(
                children: [
                  Text(
                    'SAFAR',
                    style: TextStyle(
                      fontFamily: 'SafarSerif',
                      fontSize: 17,
                      letterSpacing: 3,
                      fontWeight: FontWeight.w600,
                      color: palette.ink,
                    ),
                  ),
                  const Spacer(),
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      IconButton(
                        tooltip: 'Notifications',
                        onPressed: () => context.push('/notifications'),
                        icon: const Icon(Icons.notifications_none_rounded),
                      ),
                      if (unread > 0)
                        Positioned(
                          right: 8,
                          top: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: palette.ember,
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(
                              unread > 9 ? '9+' : '$unread',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: palette.surface,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 2),
                  Semantics(
                    button: true,
                    label: 'Your profile',
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => context.go('/profile'),
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: Center(
                          child: SafarAvatar(
                            name: name,
                            size: 36,
                            imageUrl: auth.user?.avatarUrl,
                            highlight: true,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Eyebrow(_greeting()),
              const SizedBox(height: 8),
              Text(
                'Where to next,\n$name?',
                style: context.texts.displayMedium?.copyWith(height: 1.08),
              ),
              const SizedBox(height: 22),
              AsyncView(
                value: trips,
                onRetry: () => ref.invalidate(tripsProvider),
                skeleton: const SkeletonList(count: 2),
                builder: (items) {
                  if (items.isEmpty) {
                    return _EmptyDashboard(
                      onCreate: () => context.push('/trips/new'),
                      onDiscover: () => context.go('/discover'),
                    );
                  }
                  final ordered = [...items]
                    ..sort((a, b) => a.startDate.compareTo(b.startDate));
                  final hero = ordered.firstWhere(
                    (trip) =>
                        (DateTime.tryParse(trip.endDate)?.isAfter(
                              DateTime.now().subtract(const Duration(days: 1)),
                            ) ??
                            true),
                    orElse: () => ordered.first,
                  );
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _TripHero(trip: hero),
                      const SizedBox(height: 22),
                      const SectionHeader(
                        eyebrow: 'Make a move',
                        title: 'Continue planning',
                      ),
                      GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 2.55,
                        children: [
                          SafarActionTile(
                            icon: Icons.add_road_outlined,
                            label: 'New trip',
                            caption: 'Start with dates',
                            onTap: () => context.push('/trips/new'),
                          ),
                          SafarActionTile(
                            icon: Icons.explore_outlined,
                            label: 'Discover',
                            caption: 'Places and ideas',
                            onTap: () => context.go('/discover'),
                          ),
                          SafarActionTile(
                            icon: Icons.auto_awesome_outlined,
                            label: 'Ask SAFAR',
                            caption: 'Grounded answers',
                            onTap: () => context.go('/assistant'),
                          ),
                          SafarActionTile(
                            icon: Icons.fingerprint,
                            label: 'Journey DNA',
                            caption: 'Your travel style',
                            onTap: () => context.push('/journey-dna'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      SectionHeader(
                        title: 'Your trips',
                        action: 'All trips',
                        onAction: () => context.go('/trips'),
                      ),
                      for (final trip in ordered)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _TripRow(trip: trip),
                        ),
                    ],
                  );
                },
              ),
              if (me.valueOrNull != null) ...[
                const SizedBox(height: 14),
                _DnaTeaser(scores: me.valueOrNull!.dna.scores),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TripHero extends StatelessWidget {
  const _TripHero({required this.trip});

  final Trip trip;

  @override
  Widget build(BuildContext context) {
    final palette = context.safar;
    final next = trip.nextAction;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [palette.emberSoft, palette.surface],
        ),
        border: Border.all(color: palette.line),
        boxShadow: [
          BoxShadow(
            color: palette.shadow.withValues(alpha: 0.08),
            blurRadius: 30,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Eyebrow(
                    trip.destinationName.toUpperCase(),
                    color: palette.ember,
                  ),
                ),
                StatusChip(
                  trip.status,
                  tone: trip.status == 'confirmed' ? ChipTone.jade : ChipTone.ember,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(trip.name, style: context.texts.headlineLarge),
            const SizedBox(height: 8),
            Text(
              '${trip.dateRangeLabel} · ${trip.dayCount} days · ${trip.memberCount} ${trip.memberCount == 1 ? 'traveller' : 'travellers'}',
              style: context.texts.bodySmall,
            ),
            if (next != null) ...[
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: palette.surface.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: palette.line),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.north_east_rounded, size: 18, color: palette.ember),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(next.title, style: context.texts.titleSmall),
                          const SizedBox(height: 3),
                          Text(next.reason, style: context.texts.bodySmall),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: () => context.push('/trips/${trip.id}'),
                    child: const Text('Open trip'),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.filledTonal(
                  tooltip: 'Itinerary',
                  onPressed: () =>
                      context.push('/trips/${trip.id}/itinerary'),
                  icon: const Icon(Icons.calendar_month_outlined, size: 20),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TripRow extends StatelessWidget {
  const _TripRow({required this.trip});

  final Trip trip;

  @override
  Widget build(BuildContext context) {
    final palette = context.safar;
    final initial = trip.destinationName.isEmpty
        ? 'S'
        : trip.destinationName.substring(0, 1).toUpperCase();
    return SafarCard(
      onTap: () => context.push('/trips/${trip.id}'),
      padding: const EdgeInsets.all(14),
      radius: 20,
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: palette.emberSoft,
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Text(
              initial,
              style: TextStyle(
                fontFamily: 'SafarSerif',
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: palette.ember,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  trip.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  '${trip.destinationName} · ${trip.dateRangeLabel}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.bodySmall,
                ),
              ],
            ),
          ),
          StatusChip(trip.myRole, tone: trip.isOwner ? ChipTone.ember : ChipTone.neutral),
        ],
      ),
    );
  }
}

class _DnaTeaser extends StatelessWidget {
  const _DnaTeaser({required this.scores});

  final Map<String, double> scores;

  @override
  Widget build(BuildContext context) {
    final palette = context.safar;
    final entries = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = entries.take(3).toList();
    if (top.isEmpty) return const SizedBox.shrink();
    return SafarCard(
      onTap: () => context.push('/journey-dna'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: Eyebrow('Journey DNA')),
              Icon(Icons.arrow_outward, size: 16, color: palette.faint),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Your style leans towards ${top.map((e) => e.key).join(', ')}.',
            style: context.texts.bodyMedium,
          ),
          const SizedBox(height: 14),
          for (final entry in top) ...[
            Row(
              children: [
                SizedBox(
                  width: 96,
                  child: Text(
                    titleCase(entry.key),
                    style: context.texts.bodySmall?.copyWith(
                      color: palette.muted,
                    ),
                  ),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: (entry.value / 10).clamp(0, 1),
                      minHeight: 6,
                      backgroundColor: palette.line,
                      color: palette.jade,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(entry.value.toStringAsFixed(1), style: context.texts.labelSmall),
              ],
            ),
            const SizedBox(height: 8),
          ],
          Text(
            'Editable at any time · never a permanent label',
            style: context.texts.labelSmall?.copyWith(color: palette.faint),
          ),
        ],
      ),
    );
  }
}

class _EmptyDashboard extends StatelessWidget {
  const _EmptyDashboard({required this.onCreate, required this.onDiscover});

  final VoidCallback onCreate;
  final VoidCallback onDiscover;

  @override
  Widget build(BuildContext context) {
    final palette = context.safar;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [palette.emberSoft, palette.surface],
        ),
        border: Border.all(color: palette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Eyebrow('First journey'),
          const SizedBox(height: 10),
          Text(
            'Plan together,\nwithout the group chat.',
            style: context.texts.headlineLarge,
          ),
          const SizedBox(height: 10),
          Text(
            'Start with a destination and dates. SAFAR keeps preferences private and '
            'explains every suggestion it makes.',
            style: context.texts.bodySmall?.copyWith(height: 1.5),
          ),
          const SizedBox(height: 20),
          FilledButton(onPressed: onCreate, child: const Text('Create a trip')),
          const SizedBox(height: 6),
          TextButton(onPressed: onDiscover, child: const Text('Explore destinations')),
        ],
      ),
    );
  }
}
