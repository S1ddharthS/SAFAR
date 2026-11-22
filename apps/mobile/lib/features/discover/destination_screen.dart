import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/safar_theme.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/safar_widgets.dart';
import 'activity_card.dart';

class DestinationScreen extends ConsumerStatefulWidget {
  const DestinationScreen({super.key, required this.destinationId});

  final String destinationId;

  @override
  ConsumerState<DestinationScreen> createState() => _DestinationScreenState();
}

class _DestinationScreenState extends ConsumerState<DestinationScreen> {
  final _search = TextEditingController();
  String _query = '';
  String _lens = 'balanced';
  bool _indoor = false;
  bool _accessible = false;
  double? _maxBudget;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  ActivitySearchQuery get _queryObject => ActivitySearchQuery(
    destinationId: widget.destinationId,
    query: _query.isEmpty ? null : _query,
    lens: _lens,
    maxBudget: _maxBudget,
    indoor: _indoor,
    accessible: _accessible,
  );

  Future<void> _pickBudget() async {
    var value = _maxBudget ?? 60;
    final result = await showSafarSheet<double?>(
      context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SafarSheetHeader(
              title: 'Budget ceiling',
              subtitle: 'Only activities at or below this estimate are listed.',
            ),
            Text(
              formatMoney(value),
              style: context.texts.headlineMedium,
            ),
            Slider(
              value: value,
              min: 0,
              max: 250,
              divisions: 50,
              label: formatMoney(value),
              onChanged: (next) => setSheetState(() => value = next),
            ),
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(sheetContext).pop(0.0),
                  child: const Text('Clear'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: () => Navigator.of(sheetContext).pop(value),
                  child: const Text('Apply'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    setState(() => _maxBudget = result == 0 ? null : result);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.safar;
    final detail = ref.watch(destinationProvider(widget.destinationId));
    final results = ref.watch(activitySearchProvider(_queryObject));

    return Scaffold(
      body: AsyncView(
        value: detail,
        onRetry: () => ref.invalidate(destinationProvider(widget.destinationId)),
        skeleton: const SkeletonList(count: 3),
        builder: (data) {
          final destination = data.destination;
          final image = ref.read(apiClientProvider).mediaUrl(destination.heroImage);
          return CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 280,
                pinned: true,
                leading: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: IconButton.filledTonal(
                    tooltip: 'Back',
                    onPressed: () => context.pop(),
                    icon: const Icon(Icons.arrow_back, size: 20),
                  ),
                ),
                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      SafarImage(url: image, height: 280, radius: 0),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              palette.ink.withValues(alpha: 0.72),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        left: 20,
                        right: 20,
                        bottom: 20,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              destination.location.toUpperCase(),
                              style: const TextStyle(
                                fontSize: 10,
                                letterSpacing: 1.6,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFFF0A34A),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              destination.name,
                              style: const TextStyle(
                                fontFamily: 'SafarSerif',
                                fontSize: 34,
                                height: 1.1,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFFFDF9F0),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 34),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    Text(
                      destination.description,
                      style: context.texts.bodyMedium?.copyWith(height: 1.55),
                    ),
                    if (destination.tags.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final tag in destination.tags)
                            StatusChip(tag.replaceAll('_', ' '), tone: ChipTone.neutral),
                        ],
                      ),
                    ],
                    if (destination.bestMonths.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Best months · ${destination.bestMonths.map((m) => _month(m)).join(', ')}',
                        style: context.texts.bodySmall,
                      ),
                    ],
                    if (destination.activityCount > 0) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${destination.activityCount} catalogued ideas',
                        style: context.texts.bodySmall,
                      ),
                    ],
                    const SizedBox(height: 22),
                    const SectionHeader(
                      eyebrow: 'Find your pace',
                      title: 'Activity ideas',
                    ),
                    TextField(
                      controller: _search,
                      onChanged: (value) => setState(() => _query = value.trim()),
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: 'Search food, art, walks…',
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
                    const SizedBox(height: 12),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final lens in const [
                            ('balanced', 'Balanced'),
                            ('iconic', 'Iconic'),
                            ('similar', 'More like this'),
                          ])
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(lens.$2),
                                selected: _lens == lens.$1,
                                onSelected: (_) =>
                                    setState(() => _lens = lens.$1),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilterChip(
                          label: const Text('Indoor'),
                          selected: _indoor,
                          onSelected: (value) => setState(() => _indoor = value),
                        ),
                        FilterChip(
                          label: const Text('Step-free access'),
                          selected: _accessible,
                          onSelected: (value) =>
                              setState(() => _accessible = value),
                        ),
                        FilterChip(
                          label: Text(
                            _maxBudget == null
                                ? 'Budget'
                                : 'Up to ${formatMoney(_maxBudget)}',
                          ),
                          selected: _maxBudget != null,
                          onSelected: (_) => _pickBudget(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () {
                          _search.clear();
                          setState(() {
                            _query = '';
                            _lens = 'balanced';
                            _indoor = false;
                            _accessible = false;
                            _maxBudget = null;
                          });
                        },
                        icon: const Icon(Icons.restart_alt, size: 17),
                        label: const Text('Reset'),
                      ),
                    ),
                    const SizedBox(height: 6),
                    results.when(
                      data: (result) {
                        if (result.items.isEmpty) {
                          return SafarEmpty(
                            title: 'Nothing matches those filters',
                            message:
                                'Widen the budget, clear a filter, or try another mood.',
                            icon: Icons.filter_alt_off_outlined,
                            action: TextButton(
                              onPressed: () {
                                _search.clear();
                                setState(() {
                                  _query = '';
                                  _lens = 'balanced';
                                  _indoor = false;
                                  _accessible = false;
                                  _maxBudget = null;
                                });
                              },
                              child: const Text('Clear filters'),
                            ),
                          );
                        }
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (result.disclosure.isNotEmpty) ...[
                              InfoBanner(
                                text: result.disclosure,
                                icon: Icons.info_outline,
                              ),
                              const SizedBox(height: 12),
                            ],
                            for (final item in result.items)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: ActivityCard(
                                  item: item,
                                  onTap: () => openPlaceWithTripPicker(
                                    context,
                                    ref,
                                    activityId: item.activity.id,
                                    activityName: item.activity.name,
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                      loading: () => const SkeletonList(count: 3),
                      error: (error, stack) => SafarErrorView(
                        message: error.toString(),
                        onRetry: () =>
                            ref.invalidate(activitySearchProvider(_queryObject)),
                      ),
                    ),
                  ]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  static const _monthNames = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  static String _month(int month) {
    if (month < 1 || month > 12) return '$month';
    return _monthNames[month - 1];
  }
}
