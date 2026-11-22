import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/trip.dart';
import '../../core/providers.dart';
import '../../core/theme/safar_theme.dart';
import '../../core/widgets/safar_widgets.dart';

class TripListScreen extends ConsumerStatefulWidget {
  const TripListScreen({super.key});

  @override
  ConsumerState<TripListScreen> createState() => _TripListScreenState();
}

class _TripListScreenState extends ConsumerState<TripListScreen> {
  String _filter = 'all';

  Future<void> _refresh() async {
    ref.invalidate(tripsProvider);
    try {
      await ref.read(tripsProvider.future);
    } on Object {
      // Handled by AsyncView.
    }
  }

  @override
  Widget build(BuildContext context) {
    final trips = ref.watch(tripsProvider);
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/trips/new'),
        icon: const Icon(Icons.add),
        label: const Text('New trip'),
      ),
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
            children: [
              const Eyebrow('Trips'),
              const SizedBox(height: 8),
              Text('Every journey,\nin one place.', style: context.texts.displayMedium),
              const SizedBox(height: 18),
              AsyncView(
                value: trips,
                onRetry: () => ref.invalidate(tripsProvider),
                builder: (items) {
                  if (items.isEmpty) {
                    return SafarEmpty(
                      title: 'No trips yet',
                      message:
                          'Start with dates and a destination. The group can join later.',
                      icon: Icons.luggage_outlined,
                      action: FilledButton(
                        onPressed: () => context.push('/trips/new'),
                        child: const Text('Create your first trip'),
                      ),
                    );
                  }
                  final filtered = switch (_filter) {
                    'active' => items.where((trip) => trip.status != 'completed').toList(),
                    'past' => items.where((trip) => trip.status == 'completed').toList(),
                    _ => items,
                  };
                  filtered.sort((a, b) => a.startDate.compareTo(b.startDate));
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final option in const [
                              ('all', 'All'),
                              ('active', 'Planning'),
                              ('past', 'Past'),
                            ])
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: Text(option.$2),
                                  selected: _filter == option.$1,
                                  onSelected: (_) =>
                                      setState(() => _filter = option.$1),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (filtered.isEmpty)
                        const SafarEmpty(
                          title: 'Nothing in this view',
                          message: 'Switch the filter to see your other trips.',
                          icon: Icons.filter_alt_off_outlined,
                        )
                      else
                        for (final trip in filtered)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _TripCard(trip: trip),
                          ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TripCard extends StatelessWidget {
  const _TripCard({required this.trip});

  final Trip trip;

  @override
  Widget build(BuildContext context) {
    final palette = context.safar;
    return SafarCard(
      onTap: () => context.push('/trips/${trip.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Eyebrow(
                  trip.destinationName,
                  color: palette.ember,
                  maxLines: 1,
                ),
              ),
              StatusChip(
                trip.status,
                tone: trip.status == 'confirmed' ? ChipTone.jade : ChipTone.ember,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(trip.name, style: context.texts.headlineSmall),
          const SizedBox(height: 6),
          Text(
            '${trip.dateRangeLabel} · ${trip.dayCount} days',
            style: context.texts.bodySmall,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Icon(Icons.group_outlined, size: 16, color: palette.faint),
              const SizedBox(width: 5),
              Text('${trip.memberCount} travellers', style: context.texts.bodySmall),
              const Spacer(),
              Text(
                trip.isOwner ? 'You own this trip' : 'You are ${trip.myRole}',
                style: context.texts.labelSmall,
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, size: 17, color: palette.faint),
            ],
          ),
        ],
      ),
    );
  }
}
