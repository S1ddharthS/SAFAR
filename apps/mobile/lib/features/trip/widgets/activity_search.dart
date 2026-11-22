import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/discovery.dart';
import '../../../core/providers.dart';
import '../../../core/theme/safar_theme.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/safar_widgets.dart';

/// Searchable catalog list used by planning tools. Selection state lives in
/// the parent; this widget only renders results and reports taps.
class ActivitySearchList extends ConsumerStatefulWidget {
  const ActivitySearchList({
    super.key,
    required this.destinationId,
    required this.trailing,
    required this.onTap,
  });

  final String? destinationId;
  final Widget Function(Activity activity) trailing;
  final ValueChanged<Activity> onTap;

  @override
  ConsumerState<ActivitySearchList> createState() => _ActivitySearchListState();
}

class _ActivitySearchListState extends ConsumerState<ActivitySearchList> {
  final _controller = TextEditingController();
  String? _query;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final destinationId = widget.destinationId;
    if (destinationId == null || destinationId.isEmpty) {
      return const InfoBanner(
        text: 'Set a destination for this trip before comparing catalog '
            'activities. The confirmed plan is never changed here.',
        icon: Icons.place_outlined,
      );
    }
    final search = ref.watch(
      activitySearchProvider(
        ActivitySearchQuery(
          destinationId: destinationId,
          query: _query,
          limit: 30,
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _controller,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Search this destination',
            prefixIcon: const Icon(Icons.search, size: 20),
            suffixIcon: _controller.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear',
                    onPressed: () {
                      _controller.clear();
                      setState(() => _query = null);
                    },
                    icon: const Icon(Icons.close, size: 18),
                  ),
          ),
          onSubmitted: (value) => setState(
            () => _query = value.trim().isEmpty ? null : value.trim(),
          ),
        ),
        const SizedBox(height: 12),
        AsyncView<SearchResult>(
          value: search,
          onRetry: () => ref.invalidate(
            activitySearchProvider(
              ActivitySearchQuery(
                destinationId: destinationId,
                query: _query,
                limit: 30,
              ),
            ),
          ),
          skeleton: const SkeletonList(count: 3, itemHeight: 58),
          builder: (data) {
            if (data.items.isEmpty) {
              return Text(
                'No catalog activity matches this search.',
                style: context.texts.bodySmall,
              );
            }
            return Column(
              children: [
                for (final item in data.items)
                  _ActivityTile(
                    item: item,
                    trailing: widget.trailing(item.activity),
                    onTap: () => widget.onTap(item.activity),
                  ),
                if (data.disclosure.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SourceLabel(source: data.disclosure),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({
    required this.item,
    required this.trailing,
    required this.onTap,
  });

  final SearchItem item;
  final Widget trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.safar;
    final activity = item.activity;
    final meta = [
      if (activity.durationMinutes > 0)
        '${activity.durationMinutes} min',
      if (activity.priceEstimate > 0)
        formatMoney(activity.priceEstimate, activity.currency),
      if (activity.tags.isNotEmpty) activity.tags.first,
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SafarCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        radius: 16,
        onTap: onTap,
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: palette.raised,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                activity.indoor
                    ? Icons.home_work_outlined
                    : Icons.explore_outlined,
                size: 17,
                color: palette.muted,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    activity.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.titleSmall,
                  ),
                  if (meta.isNotEmpty)
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.texts.labelSmall,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            trailing,
          ],
        ),
      ),
    );
  }
}
