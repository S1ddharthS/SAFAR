import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/discovery.dart';
import '../../core/models/monitoring.dart';
import '../../core/providers.dart';
import '../../core/theme/safar_theme.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/safar_widgets.dart';
import 'widgets/activity_search.dart';

const _fields = [
  ('opening_hours', 'Opening hours'),
  ('price_estimate', 'Price'),
  ('wheelchair_accessible', 'Step-free access'),
];

const _dayLabels = {
  'mon': 'Mon',
  'tue': 'Tue',
  'wed': 'Wed',
  'thu': 'Thu',
  'fri': 'Fri',
  'sat': 'Sat',
  'sun': 'Sun',
};

String _fieldLabel(String field) {
  for (final (value, label) in _fields) {
    if (value == field) return label;
  }
  return titleCase(field);
}

/// Normalises the shapes the API stores for a watched value: a raw value, a
/// `{value}` wrapper, or a `{value, previous}` wrapper after a change.
String describeWatchValue(String field, Object? raw) {
  var stored = raw;
  if (raw is Map && raw.containsKey('value')) stored = raw['value'];
  if (stored == null) return 'unknown';
  if (field == 'wheelchair_accessible') {
    if (stored == true) return 'step-free';
    if (stored == false) return 'not step-free';
    return 'unknown';
  }
  if (field == 'price_estimate') {
    if (stored is num) return formatMoney(stored.toDouble());
    return '$stored';
  }
  if (stored is Map) {
    final hours =
        stored.entries.where((entry) => _dayLabels.containsKey(entry.key)).toList();
    if (hours.isNotEmpty) {
      final distinct = hours.map((entry) => '${entry.value}').toSet();
      if (distinct.length == 1) return 'Every day ${hours.first.value}';
      return hours
          .map((entry) => '${_dayLabels[entry.key]} ${entry.value}')
          .join(' · ');
    }
    if (stored.isEmpty) return 'unknown';
    return stored.entries
        .map((entry) => '${titleCase('${entry.key}')} ${entry.value}')
        .join(' · ');
  }
  return '$stored';
}

class WatchScreen extends ConsumerStatefulWidget {
  const WatchScreen({super.key, required this.tripId});

  final String tripId;

  @override
  ConsumerState<WatchScreen> createState() => _WatchScreenState();
}

class _WatchScreenState extends ConsumerState<WatchScreen> {
  bool _checking = false;
  String? _removingId;
  WatchCheckResult? _result;

  String get _tripId => widget.tripId;

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _addWatch(String? destinationId) async {
    if (destinationId == null || destinationId.isEmpty) {
      _notify('Set a destination for this trip before watching catalog facts.');
      return;
    }
    var field = _fields.first.$1;
    var adding = false;
    await showSafarSheet<void>(
      context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SafarSheetHeader(
              title: 'Watch a fact',
              subtitle:
                  'SAFAR alerts only when the recorded value changes. '
                  'Watching never changes your confirmed plan.',
            ),
            Text('Field', style: context.texts.labelMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (value, label) in _fields)
                  ChoiceChip(
                    label: Text(label),
                    selected: field == value,
                    onSelected: (_) => setSheetState(() => field = value),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Text('Choose an activity', style: context.texts.labelMedium),
            const SizedBox(height: 8),
            SizedBox(
              height: 330,
              child: SingleChildScrollView(
                child: ActivitySearchList(
                  destinationId: destinationId,
                  trailing: (Activity activity) => adding
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          Icons.add_circle_outline,
                          size: 19,
                          color: context.safar.ember,
                        ),
                  onTap: (Activity activity) async {
                    if (adding) return;
                    setSheetState(() => adding = true);
                    try {
                      await ref
                          .read(tripRepositoryProvider)
                          .addMaterialWatch(
                            _tripId,
                            activityId: activity.id,
                            field: field,
                          );
                      ref.invalidate(watchesProvider(_tripId));
                      if (sheetContext.mounted) {
                        Navigator.of(sheetContext).pop();
                      }
                      _notify(
                        'Watching ${_fieldLabel(field).toLowerCase()} for '
                        '${activity.name}.',
                      );
                    } on Object catch (error) {
                      setSheetState(() => adding = false);
                      _notify(error.toString());
                    }
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _remove(WatchItem watch) async {
    if (_removingId != null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Stop watching this fact?'),
        content: Text(
          '${watch.activityName ?? 'This activity'} · '
          '${_fieldLabel(watch.field)}. You will no longer be alerted when it '
          'changes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep watching'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Stop watching'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _removingId = watch.id);
    try {
      await ref
          .read(tripRepositoryProvider)
          .removeMaterialWatch(_tripId, watch.id);
      ref.invalidate(watchesProvider(_tripId));
      _notify('Watch removed.');
    } on Object catch (error) {
      _notify(error.toString());
    } finally {
      if (mounted) setState(() => _removingId = null);
    }
  }

  Future<void> _check() async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      final result = await ref
          .read(tripRepositoryProvider)
          .checkMaterialWatches(_tripId);
      ref.invalidate(watchesProvider(_tripId));
      if (!mounted) return;
      setState(() => _result = result);
      _notify(
        'Checked ${result.checked} · ${result.changed.length} changed · '
        '${result.unchanged} unchanged.',
      );
    } on Object catch (error) {
      _notify(error.toString());
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final watches = ref.watch(watchesProvider(_tripId));
    final trip = ref.watch(tripProvider(_tripId)).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back),
        ),
        title: const Text('Material watch'),
        actions: [
          IconButton(
            tooltip: 'Check now',
            onPressed: _checking ? null : _check,
            icon: _checking
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: AsyncView<List<WatchItem>>(
        value: watches,
        onRetry: () => ref.invalidate(watchesProvider(_tripId)),
        builder: (items) {
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(watchesProvider(_tripId));
              try {
                await ref.read(watchesProvider(_tripId).future);
              } on Object {
                // The list surfaces the failure inline.
              }
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                const Eyebrow('Material change watch'),
                const SizedBox(height: 8),
                Text(
                  'Alert on changes that matter',
                  style: context.texts.displaySmall,
                ),
                const SizedBox(height: 8),
                Text(
                  'Track opening hours, price or step-free access. SAFAR '
                  'alerts only when the recorded value actually changes.',
                  style: context.texts.bodySmall,
                ),
                const SizedBox(height: 16),
                if (_result != null) ...[
                  _CheckResultCard(result: _result!),
                  const SizedBox(height: 12),
                ],
                SafarCard(
                  padding: const EdgeInsets.all(14),
                  radius: 18,
                  onTap: () => _addWatch(trip?.destinationId),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: context.safar.emberSoft,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.add_alert_outlined,
                          size: 19,
                          color: context.safar.ember,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Add a watch',
                              style: context.texts.titleSmall,
                            ),
                            Text(
                              'Only fields recorded in the catalog can be '
                              'tracked.',
                              style: context.texts.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        size: 18,
                        color: context.safar.faint,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                if (items.isEmpty)
                  SafarEmpty(
                    icon: Icons.radar_rounded,
                    title: 'Nothing watched yet',
                    message:
                        'Track a fact that could change before you travel. '
                        'You are alerted only when it does.',
                    action: FilledButton(
                      onPressed: () => _addWatch(trip?.destinationId),
                      child: const Text('Add a watch'),
                    ),
                  )
                else
                  for (final watch in items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _WatchCard(
                        watch: watch,
                        busy: _removingId == watch.id,
                        onRemove: () => _remove(watch),
                      ),
                    ),
                const SizedBox(height: 18),
                const InfoBanner(
                  text:
                      'Alerts never change your confirmed plan. If a watched '
                      'fact changes, review it and decide whether to propose '
                      'an update.',
                  icon: Icons.radar_rounded,
                  tone: ChipTone.jade,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _CheckResultCard extends StatelessWidget {
  const _CheckResultCard({required this.result});

  final WatchCheckResult result;

  @override
  Widget build(BuildContext context) {
    final palette = context.safar;
    return SafarCard(
      color: result.changed.isEmpty ? null : palette.emberSoft,
      borderColor: result.changed.isEmpty
          ? null
          : palette.ember.withValues(alpha: 0.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                result.changed.isEmpty
                    ? Icons.verified_outlined
                    : Icons.notification_important_outlined,
                size: 18,
                color: result.changed.isEmpty ? palette.jade : palette.ember,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  result.changed.isEmpty
                      ? 'Check complete — nothing changed'
                      : '${result.changed.length} tracked fact(s) changed',
                  style: context.texts.titleSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Checked ${result.checked} · unchanged ${result.unchanged}. '
            '${result.note}',
            style: context.texts.bodySmall,
          ),
          for (final change in result.changed) ...[
            const SizedBox(height: 8),
            Text(
              '${change.activityName} · ${_fieldLabel(change.field)}',
              style: context.texts.labelMedium,
            ),
            Text(
              '${describeWatchValue(change.field, change.previous)} → '
              '${describeWatchValue(change.field, change.current)}',
              style: context.texts.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

class _WatchCard extends StatelessWidget {
  const _WatchCard({
    required this.watch,
    required this.busy,
    required this.onRemove,
  });

  final WatchItem watch;
  final bool busy;
  final VoidCallback onRemove;

  ChipTone get _tone => switch (watch.status) {
    'changed' => ChipTone.ember,
    'target_missing' => ChipTone.rose,
    _ => ChipTone.jade,
  };

  @override
  Widget build(BuildContext context) {
    return SafarCard(
      padding: const EdgeInsets.all(14),
      radius: 18,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    StatusChip(titleCase(watch.status), tone: _tone),
                    StatusChip(_fieldLabel(watch.field)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  watch.activityName ?? 'Activity',
                  style: context.texts.titleSmall,
                ),
                const SizedBox(height: 3),
                Text(
                  'Last value: ${describeWatchValue(watch.field, watch.rawValue)}'
                  '${watch.lastCheckedAt == null ? ' · never checked' : ' · checked ${timeAgo(watch.lastCheckedAt)}'}',
                  style: context.texts.labelSmall,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Stop watching',
            onPressed: busy ? null : onRemove,
            icon: busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    Icons.delete_outline,
                    size: 18,
                    color: context.safar.faint,
                  ),
          ),
        ],
      ),
    );
  }
}
