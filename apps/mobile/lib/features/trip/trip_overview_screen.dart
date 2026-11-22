import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/itinerary.dart';
import '../../core/providers.dart';
import '../../core/realtime/live_status_chip.dart';
import '../../core/theme/safar_theme.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/safar_widgets.dart';

class TripOverviewScreen extends ConsumerWidget {
  const TripOverviewScreen({super.key, required this.tripId});

  final String tripId;

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(tripProvider(tripId));
    ref.invalidate(membersProvider(tripId));
    ref.invalidate(itineraryProvider(tripId));
    ref.invalidate(engineProvider(tripId));
    ref.invalidate(expensesProvider(tripId));
    ref.invalidate(pulseProvider(tripId));
    try {
      await ref.read(tripProvider(tripId).future);
    } on Object {
      // AsyncView renders failures.
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.safar;
    final trip = ref.watch(tripProvider(tripId));
    final members = ref.watch(membersProvider(tripId));
    final itinerary = ref.watch(itineraryProvider(tripId));
    final engine = ref.watch(engineProvider(tripId));
    final expenses = ref.watch(expensesProvider(tripId));

    return Scaffold(
      body: AsyncView(
        value: trip,
        onRetry: () => ref.invalidate(tripProvider(tripId)),
        skeleton: const SkeletonList(count: 2),
        builder: (data) {
          final next = data.nextAction;
          return RefreshIndicator(
            onRefresh: () => _refresh(ref),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverAppBar(
                  pinned: true,
                  leading: IconButton(
                    tooltip: 'Back',
                    onPressed: () => context.canPop()
                        ? context.pop()
                        : context.go('/dashboard'),
                    icon: const Icon(Icons.arrow_back),
                  ),
                  actions: [
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Center(
                        child: TripLiveChip(tripId: tripId, compact: true),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Assistant',
                      onPressed: () =>
                          context.push('/trips/$tripId/assistant'),
                      icon: const Icon(Icons.auto_awesome_outlined),
                    ),
                    const SizedBox(width: 4),
                  ],
                  title: Text(
                    data.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 34),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      Container(
                        padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
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
                            Row(
                              children: [
                                Expanded(
                                  child: Eyebrow(
                                    data.destinationName,
                                    color: palette.ember,
                                  ),
                                ),
                                StatusChip(
                                  data.status,
                                  tone: data.status == 'confirmed'
                                      ? ChipTone.jade
                                      : ChipTone.ember,
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              data.name,
                              style: context.texts.displaySmall,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${data.dateRangeLabel} · ${data.dayCount} days · ${data.memberCount} travellers',
                              style: context.texts.bodySmall,
                            ),
                            if (data.description != null &&
                                data.description!.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Text(
                                data.description!,
                                style: context.texts.bodySmall?.copyWith(
                                  height: 1.5,
                                ),
                              ),
                            ],
                            const SizedBox(height: 16),
                            members.when(
                              data: (list) => InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () => context.push(
                                  '/trips/$tripId/members',
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 4,
                                  ),
                                  child: Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      for (final member in list.take(6))
                                        Tooltip(
                                          message:
                                              '${member.displayName} · ${member.role}',
                                          child: SafarAvatar(
                                            name: member.displayName,
                                            size: 32,
                                            highlight: member.isSelf,
                                            imageUrl: member.user?.avatarUrl,
                                          ),
                                        ),
                                      if (list.length > 6)
                                        Text(
                                          '+${list.length - 6}',
                                          style: context.texts.labelSmall,
                                        ),
                                      if (list.isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            left: 4,
                                          ),
                                          child: Text(
                                            list.length == 1
                                                ? 'Just you so far'
                                                : '${list.length} in the group',
                                            style: context.texts.labelSmall,
                                          ),
                                        ),
                                      const Icon(
                                        Icons.chevron_right_rounded,
                                        size: 18,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              loading: () => const SkeletonBox(
                                height: 30,
                                width: 160,
                                radius: 99,
                              ),
                              error: (error, stack) => Text(
                                'Members could not be loaded',
                                style: context.texts.labelSmall,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (next != null) ...[
                        const SizedBox(height: 16),
                        SafarCard(
                          color: palette.surface,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: palette.emberSoft,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  Icons.north_east_rounded,
                                  size: 18,
                                  color: palette.ember,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Eyebrow('Next move'),
                                    const SizedBox(height: 4),
                                    Text(
                                      next.title,
                                      style: context.texts.titleSmall,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      next.reason,
                                      style: context.texts.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 22),
                      const SectionHeader(eyebrow: 'The plan', title: 'Itinerary'),
                      itinerary.when(
                        loading: () =>
                            const SkeletonBox(height: 148, radius: 24),
                        error: (error, stack) => SafarActionTile(
                          icon: Icons.error_outline,
                          label: 'Itinerary could not be loaded',
                          caption: 'Tap to retry',
                          onTap: () =>
                              ref.invalidate(itineraryProvider(tripId)),
                        ),
                        data: (plan) {
                          final progress = _planProgress(plan);
                          return SafarCard(
                            onTap: () =>
                                context.push('/trips/$tripId/itinerary'),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        progress.items == 0
                                            ? 'Nothing confirmed yet'
                                            : '${progress.items} items across ${progress.days} days',
                                        style: context.texts.titleSmall,
                                      ),
                                    ),
                                    StatusChip('v${progress.version}'),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  progress.items == 0
                                      ? 'Use the engine or add ideas from Discover, then vote as a group.'
                                      : '${formatMoney(progress.cost, progress.currency)} planned · ${formatMoney(progress.perPerson, progress.currency)} per person',
                                  style: context.texts.bodySmall,
                                ),
                                if (progress.items > 0) ...[
                                  const SizedBox(height: 12),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(99),
                                    child: LinearProgressIndicator(
                                      value:
                                          (progress.items / (progress.days * 4))
                                              .clamp(0.05, 1),
                                      minHeight: 6,
                                      backgroundColor: palette.line,
                                      color: palette.jade,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Text(
                                      'Open timeline',
                                      style:
                                          context.texts.labelMedium?.copyWith(
                                        color: palette.ember,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Icon(
                                      Icons.arrow_forward,
                                      size: 15,
                                      color: palette.ember,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 14),
                      engine.when(
                        data: (batch) {
                          final top = batch?.items.isNotEmpty == true
                              ? batch!.items.first
                              : null;
                          if (top == null) {
                            return SafarActionTile(
                              icon: Icons.auto_awesome,
                              label: 'Find group options',
                              caption: 'Run the Group Experience Engine',
                              onTap: () =>
                                  context.push('/trips/$tripId/engine'),
                            );
                          }
                          final name =
                              top.activity?.name ?? 'A group recommendation';
                          return SafarCard(
                            onTap: () =>
                                context.push('/trips/$tripId/engine'),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Expanded(
                                      child: Eyebrow('Top group option'),
                                    ),
                                    StatusChip(
                                      batch!.modeMeta.label.isEmpty
                                          ? batch.mode
                                          : batch.modeMeta.label,
                                      tone: ChipTone.ember,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(name, style: context.texts.titleMedium),
                                const SizedBox(height: 4),
                                Text(
                                  top.explanation.summary,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: context.texts.bodySmall,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Avg fit ${top.averageFit.round()}% · lowest ${top.minimumFit.round()}%',
                                  style: context.texts.labelSmall,
                                ),
                              ],
                            ),
                          );
                        },
                        loading: () => const SkeletonBox(
                          height: 70,
                          radius: 18,
                        ),
                        error: (error, stack) => SafarActionTile(
                          icon: Icons.auto_awesome,
                          label: 'Find group options',
                          caption: 'Open the engine',
                          onTap: () =>
                              context.push('/trips/$tripId/engine'),
                        ),
                      ),
                      const SizedBox(height: 14),
                      expenses.when(
                        data: (data) {
                          final currency = data.totals.keys.isEmpty
                              ? 'EUR'
                              : data.totals.keys.first;
                          final total = data.totals[currency] ?? 0;
                          return SafarCard(
                            onTap: () =>
                                context.push('/trips/$tripId/expenses'),
                            child: Row(
                              children: [
                                Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    color: palette.jadeSoft,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    Icons.account_balance_wallet_outlined,
                                    size: 19,
                                    color: palette.jade,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        data.items.isEmpty
                                            ? 'No shared expenses yet'
                                            : '${formatMoney(total, currency)} shared',
                                        style: context.texts.titleSmall,
                                      ),
                                      Text(
                                        data.items.isEmpty
                                            ? 'Track costs without exposing member budgets'
                                            : '${data.items.length} entries · settle up fairly',
                                        style: context.texts.bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  Icons.chevron_right,
                                  size: 18,
                                  color: palette.faint,
                                ),
                              ],
                            ),
                          );
                        },
                        loading: () => const SkeletonBox(
                          height: 64,
                          radius: 18,
                        ),
                        error: (error, stack) => const SizedBox.shrink(),
                      ),
                      const SizedBox(height: 24),
                      const SectionHeader(eyebrow: 'Workspace', title: 'Everything for this trip'),
                      GridView.count(
                        crossAxisCount: 3,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 0.98,
                        children: [
                          _Tool(
                            icon: Icons.how_to_vote_outlined,
                            label: 'Voting',
                            onTap: () =>
                                context.push('/trips/$tripId/proposals'),
                          ),
                          _Tool(
                            icon: Icons.auto_awesome_outlined,
                            label: 'Engine',
                            onTap: () =>
                                context.push('/trips/$tripId/engine'),
                          ),
                          _Tool(
                            icon: Icons.bolt_outlined,
                            label: 'Pulse',
                            onTap: () => context.push('/trips/$tripId/pulse'),
                          ),
                          _Tool(
                            icon: Icons.directions_bus_outlined,
                            label: 'Rescue',
                            onTap: () => context.push('/trips/$tripId/rescue'),
                          ),
                          _Tool(
                            icon: Icons.photo_library_outlined,
                            label: 'Memories',
                            onTap: () =>
                                context.push('/trips/$tripId/memories'),
                          ),
                          _Tool(
                            icon: Icons.auto_stories_outlined,
                            label: 'Studio',
                            onTap: () => context.push('/trips/$tripId/studio'),
                          ),
                          _Tool(
                            icon: Icons.replay_outlined,
                            label: 'Replay',
                            onTap: () => context.push('/trips/$tripId/replay'),
                          ),
                          _Tool(
                            icon: Icons.travel_explore_outlined,
                            label: 'Import',
                            onTap: () => context.push('/trips/$tripId/import'),
                          ),
                          _Tool(
                            icon: Icons.flight_takeoff_outlined,
                            label: 'Assistant',
                            onTap: () =>
                                context.push('/trips/$tripId/assistant'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SafarActionTile(
                        icon: Icons.widgets_outlined,
                        label: 'More trip tools',
                        caption:
                            'Twin, Pact, tasks, nearby, offline and every other tool',
                        onTap: () => context.push('/trips/$tripId/more'),
                      ),
                      const SizedBox(height: 22),
                      InfoBanner(
                        text:
                            'Confirmed itineraries only change through a group proposal. '
                            'Member preferences and budgets stay private.',
                        icon: Icons.lock_outline,
                      ),
                    ]),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  _Progress _planProgress(Itinerary itinerary) {
    return _Progress(
      items: itinerary.totals.items,
      days: itinerary.totals.days,
      cost: itinerary.totals.cost,
      perPerson: itinerary.totals.perPerson,
      currency: itinerary.totals.currency,
      version: itinerary.confirmedVersion,
    );
  }
}

class _Progress {
  const _Progress({
    required this.items,
    required this.days,
    required this.cost,
    required this.perPerson,
    required this.currency,
    required this.version,
  });

  final int items;
  final int days;
  final double cost;
  final double perPerson;
  final String currency;
  final int version;
}

class _Tool extends StatelessWidget {
  const _Tool({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.safar;
    return SafarCard(
      padding: const EdgeInsets.all(12),
      radius: 18,
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: palette.emberSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 19, color: palette.ember),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.texts.labelSmall?.copyWith(color: palette.ink),
          ),
        ],
      ),
    );
  }
}
