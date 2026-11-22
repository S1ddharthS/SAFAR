import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/discovery.dart';
import '../../core/providers.dart';
import '../../core/theme/safar_theme.dart';
import '../../core/widgets/safar_widgets.dart';

class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key});

  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    ref.invalidate(destinationsProvider);
    try {
      await ref.read(destinationsProvider.future);
    } on Object {
      // Rendered by AsyncView.
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.safar;
    final destinations = ref.watch(destinationsProvider);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            children: [
              const Eyebrow('Discover'),
              const SizedBox(height: 8),
              Text('Places worth\nthe detour.', style: context.texts.displayMedium),
              const SizedBox(height: 8),
              Text(
                'Destination intelligence with its source attached. Estimates stay labelled.',
                style: context.texts.bodySmall,
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _search,
                onChanged: (value) => setState(() => _query = value.trim()),
                decoration: InputDecoration(
                  hintText: 'Search destinations, countries or moods',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear',
                          onPressed: () {
                            _search.clear();
                            setState(() => _query = '');
                          },
                          icon: const Icon(Icons.close, size: 18),
                        ),
                ),
              ),
              const SizedBox(height: 20),
              AsyncView(
                value: destinations,
                onRetry: () => ref.invalidate(destinationsProvider),
                builder: (items) {
                  final needle = _query.toLowerCase();
                  final filtered = needle.isEmpty
                      ? items
                      : items
                            .where(
                              (destination) =>
                                  destination.name.toLowerCase().contains(needle) ||
                                  destination.country.toLowerCase().contains(needle) ||
                                  destination.description.toLowerCase().contains(needle) ||
                                  destination.tags.any(
                                    (tag) => tag.toLowerCase().contains(needle),
                                  ),
                            )
                            .toList();
                  if (filtered.isEmpty) {
                    return SafarEmpty(
                      title: 'No destinations match',
                      message: 'Try a country, a city or a mood such as “coast”.',
                      icon: Icons.travel_explore_outlined,
                      action: _query.isEmpty
                          ? null
                          : TextButton(
                              onPressed: () {
                                _search.clear();
                                setState(() => _query = '');
                              },
                              child: const Text('Clear search'),
                            ),
                    );
                  }
                  return Column(
                    children: [
                      for (final destination in filtered)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: _DestinationCard(destination: destination),
                        ),
                      if (_query.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Catalog entries show their verification age. Community '
                            'reports are attributed and never presented as verified fact.',
                            style: TextStyle(
                              fontSize: 11,
                              height: 1.5,
                              color: palette.faint,
                            ),
                          ),
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

class _DestinationCard extends ConsumerWidget {
  const _DestinationCard({required this.destination});

  final Destination destination;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.safar;
    final image = ref.watch(apiClientProvider).mediaUrl(destination.heroImage);
    final hasImage = image.isNotEmpty;
    return SafarCard(
      padding: EdgeInsets.zero,
      onTap: () => context.push('/destinations/${destination.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              SafarImage(
                url: image,
                height: 176,
                radius: 22,
                label: hasImage ? null : destination.name,
              ),
              if (hasImage)
                Positioned(
                  left: 14,
                  bottom: 14,
                  right: 14,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: palette.ink.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            destination.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: 'SafarSerif',
                              fontSize: 21,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFFFDF9F0),
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.arrow_outward,
                          size: 17,
                          color: Color(0xFFFDF9F0),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        destination.location,
                        style: context.texts.labelMedium,
                      ),
                    ),
                    StatusChip(
                      '${destination.activityCount} ideas',
                      tone: ChipTone.ember,
                    ),
                  ],
                ),
                if (destination.description.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    destination.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.bodySmall?.copyWith(height: 1.45),
                  ),
                ],
                if (destination.tags.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final tag in destination.tags.take(4))
                        StatusChip(tag.replaceAll('_', ' ')),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
