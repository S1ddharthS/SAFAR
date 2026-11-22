import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/monitoring.dart';
import '../../core/providers.dart';
import '../../core/storage/offline_queue.dart';
import '../../core/theme/safar_theme.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/safar_widgets.dart';

class OfflineScreen extends ConsumerStatefulWidget {
  const OfflineScreen({super.key, required this.tripId});

  final String tripId;

  @override
  ConsumerState<OfflineScreen> createState() => _OfflineScreenState();
}

class _OfflineScreenState extends ConsumerState<OfflineScreen> {
  final _capture = TextEditingController();
  List<OfflineCapture> _queue = const [];
  bool _queueLoading = true;
  bool _saving = false;
  bool _syncing = false;
  SyncOutcome? _outcome;

  String get _tripId => widget.tripId;

  @override
  void initState() {
    super.initState();
    _loadQueue();
  }

  @override
  void dispose() {
    _capture.dispose();
    super.dispose();
  }

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _loadQueue() async {
    try {
      final all = await ref.read(offlineQueueProvider).load();
      if (!mounted) return;
      setState(() {
        _queue = all.where((entry) => entry.tripId == _tripId).toList();
        _queueLoading = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() => _queueLoading = false);
    }
  }

  Future<void> _saveCapture() async {
    final text = _capture.text.trim();
    if (text.isEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(offlineQueueProvider)
          .add(
            OfflineCapture(
              clientId: OfflineQueue.newClientId(),
              tripId: _tripId,
              text: text,
              capturedAt: DateTime.now().toUtc().toIso8601String(),
            ),
          );
      await _loadQueue();
      if (!mounted) return;
      _capture.clear();
      _notify('Saved on this device. Sync when you are back online.');
    } on Object catch (error) {
      _notify(error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _sync() async {
    if (_queue.isEmpty || _syncing) return;
    setState(() => _syncing = true);
    try {
      final outcome = await ref
          .read(memoryRepositoryProvider)
          .sync(_tripId, [
            for (final capture in _queue)
              {
                'client_id': capture.clientId,
                'operation': 'memory_create',
                'payload': capture.payload,
              },
          ]);
      final settled = {
        for (final result in outcome.results)
          if (result.status == 'applied' || result.status == 'skipped')
            result.clientId,
      };
      await ref.read(offlineQueueProvider).remove(settled);
      await _loadQueue();
      ref.invalidate(syncQueueProvider(_tripId));
      ref.invalidate(memoriesProvider(_tripId));
      ref.invalidate(offlineSnapshotProvider(_tripId));
      if (!mounted) return;
      setState(() => _outcome = outcome);
      _notify(
        '${outcome.applied} applied · ${outcome.skipped} already synced · '
        '${outcome.rejected} rejected.',
      );
    } on Object catch (error) {
      _notify('Could not sync: $error');
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _refresh() async {
    ref.invalidate(offlineSnapshotProvider(_tripId));
    ref.invalidate(syncQueueProvider(_tripId));
    await _loadQueue();
    try {
      await ref.read(offlineSnapshotProvider(_tripId).future);
    } on Object {
      // The snapshot section surfaces the failure.
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(offlineSnapshotProvider(_tripId));
    final history = ref.watch(syncQueueProvider(_tripId));

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back),
        ),
        title: const Text('Offline plan'),
        actions: [
          IconButton(
            tooltip: 'Sync queued captures',
            onPressed: _queue.isEmpty || _syncing ? null : _sync,
            icon: _syncing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_upload_outlined),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            const Eyebrow('Offline'),
            const SizedBox(height: 8),
            Text('The plan, without a signal', style: context.texts.displaySmall),
            const SizedBox(height: 8),
            Text(
              'Snapshot the confirmed plan, members and meeting points. '
              'Private budgets, access needs and private memories are excluded.',
              style: context.texts.bodySmall,
            ),
            const SizedBox(height: 16),
            snapshot.when(
              data: (data) => _SnapshotSummary(snapshot: data, queued: _queue.length),
              loading: () => const SkeletonBox(height: 150, radius: 18),
              error: (error, _) => SafarErrorView(
                message: error.toString(),
                onRetry: () => ref.invalidate(offlineSnapshotProvider(_tripId)),
              ),
            ),
            const SizedBox(height: 18),
            _CaptureCard(
              controller: _capture,
              saving: _saving,
              onSave: _saveCapture,
            ),
            const SizedBox(height: 12),
            _QueueCard(
              queue: _queue,
              loading: _queueLoading,
              syncing: _syncing,
              outcome: _outcome,
              onSync: _sync,
            ),
            const SizedBox(height: 18),
            snapshot.when(
              data: (data) => _SnapshotBody(snapshot: data),
              loading: () => const SizedBox.shrink(),
              error: (error, _) => const SizedBox.shrink(),
            ),
            const SizedBox(height: 18),
            const SectionHeader(
              eyebrow: 'Server view',
              title: 'Sync history',
            ),
            history.when(
              data: (items) {
                if (items.isEmpty) {
                  return Text(
                    'Nothing synced yet.',
                    style: context.texts.bodySmall,
                  );
                }
                return Column(
                  children: [
                    for (final entry in items.take(20))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: SafarCard(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          radius: 14,
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      titleCase(
                                        entry.operation.replaceAll('_', ' '),
                                      ),
                                      style: context.texts.labelMedium,
                                    ),
                                    Text(
                                      entry.clientId.length > 8
                                          ? '…${entry.clientId.substring(entry.clientId.length - 8)}'
                                          : entry.clientId,
                                      style: context.texts.labelSmall,
                                    ),
                                  ],
                                ),
                              ),
                              StatusChip(
                                titleCase(entry.status),
                                tone: switch (entry.status) {
                                  'applied' => ChipTone.jade,
                                  'rejected' => ChipTone.rose,
                                  _ => ChipTone.neutral,
                                },
                              ),
                              const SizedBox(width: 8),
                              Text(
                                entry.appliedAt == null
                                    ? 'pending'
                                    : timeAgo(entry.appliedAt),
                                style: context.texts.labelSmall,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
              loading: () => const SkeletonBox(height: 48, radius: 14),
              error: (error, _) => InfoBanner(
                text: error.toString(),
                icon: Icons.cloud_off_outlined,
                tone: ChipTone.rose,
              ),
            ),
            const SizedBox(height: 18),
            const InfoBanner(
              text:
                  'Offline captures are stored on this device only. They sync '
                  'to your trip memories once the API is reachable, and client '
                  'ids make retries idempotent. Nothing is overwritten silently.',
              icon: Icons.shield_outlined,
              tone: ChipTone.jade,
            ),
          ],
        ),
      ),
    );
  }
}

class _SnapshotSummary extends StatelessWidget {
  const _SnapshotSummary({required this.snapshot, required this.queued});

  final OfflineSnapshot snapshot;
  final int queued;

  @override
  Widget build(BuildContext context) {
    final palette = context.safar;
    final stale = snapshot.stale;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InfoBanner(
          text: stale
              ? 'Generated ${formatDate(snapshot.generatedAt)}. This snapshot '
                  'is stale — refresh before relying on it.'
              : 'Generated ${formatDate(snapshot.generatedAt)} · stale after '
                  '${formatDate(snapshot.staleAfter)}. Refresh before '
                  'travelling if the plan changed.',
          icon: stale ? Icons.cloud_off_outlined : Icons.shield_outlined,
          tone: stale ? ChipTone.ember : ChipTone.jade,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: StatTile(
                label: 'Confirmed',
                value: '${snapshot.items.length}',
                hint: 'items',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: StatTile(
                label: 'Members',
                value: '${snapshot.members.length}',
                hint: 'active',
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: StatTile(
                label: 'Queued',
                value: '$queued',
                hint: 'on device',
                icon: queued > 0 ? Icons.cloud_upload_outlined : null,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: StatTile(
                label: 'Version',
                value: 'v${snapshot.confirmedVersion}',
                hint: 'confirmed',
              ),
            ),
          ],
        ),
        if (stale) ...[
          const SizedBox(height: 8),
          Text(
            'Stale snapshots are still readable, but treat them as a record, '
            'not current truth.',
            style: context.texts.labelSmall?.copyWith(color: palette.ember),
          ),
        ],
      ],
    );
  }
}

class _CaptureCard extends StatelessWidget {
  const _CaptureCard({
    required this.controller,
    required this.saving,
    required this.onSave,
  });

  final TextEditingController controller;
  final bool saving;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return SafarCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            eyebrow: 'Offline capture',
            title: 'Write a memory now',
          ),
          Text(
            'Saved on this device immediately, even with no connection. It '
            'joins the trip memories once you sync.',
            style: context.texts.bodySmall,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            minLines: 3,
            maxLines: 6,
            maxLength: 4000,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Memory',
              hintText: 'The bakery on the corner, the rain, the laugh…',
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonalIcon(
              onPressed: saving ? null : onSave,
              icon: saving
                  ? const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined, size: 17),
              label: const Text('Save on device'),
            ),
          ),
        ],
      ),
    );
  }
}

class _QueueCard extends StatelessWidget {
  const _QueueCard({
    required this.queue,
    required this.loading,
    required this.syncing,
    required this.outcome,
    required this.onSync,
  });

  final List<OfflineCapture> queue;
  final bool loading;
  final bool syncing;
  final SyncOutcome? outcome;
  final VoidCallback onSync;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const SkeletonBox(height: 80, radius: 18);
    }
    if (queue.isEmpty) {
      return InfoBanner(
        text: outcome == null
            ? 'Nothing queued on this device.'
            : 'Queue synced. ${outcome!.note}',
        icon: Icons.cloud_done_outlined,
        tone: ChipTone.jade,
      );
    }
    return SafarCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            eyebrow: 'Waiting to sync',
            title: '${queue.length} capture(s)',
          ),
          for (final capture in queue) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const StatusChip('Memory', tone: ChipTone.ember),
                      const Spacer(),
                      Text(
                        timeAgo(capture.capturedAt),
                        style: context.texts.labelSmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    capture.text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.bodySmall,
                  ),
                ],
              ),
            ),
          ],
          if (outcome != null && outcome!.results.isNotEmpty) ...[
            const SizedBox(height: 6),
            for (final result in outcome!.results)
              Text(
                '${result.clientId.length > 6 ? result.clientId.substring(result.clientId.length - 6) : result.clientId}'
                ' · ${result.status}${result.reason == null ? '' : ' — ${result.reason}'}',
                style: context.texts.labelSmall,
              ),
            const SizedBox(height: 8),
          ],
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: syncing ? null : onSync,
              icon: syncing
                  ? const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_upload_outlined, size: 17),
              label: Text(syncing ? 'Syncing…' : 'Sync now'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SnapshotBody extends StatelessWidget {
  const _SnapshotBody({required this.snapshot});

  final OfflineSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final trip = snapshot.trip;
    final currency = trip.currency;
    final widgets = <Widget>[];
    String? lastDay;
    for (final item in snapshot.items) {
      if (item.day != lastDay) {
        lastDay = item.day;
        widgets.add(
          Padding(
            padding: EdgeInsets.only(
              top: widgets.isEmpty ? 0 : 14,
              bottom: 6,
            ),
            child: Eyebrow(formatDateShort(item.day), maxLines: 1),
          ),
        );
      }
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: SafarCard(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            radius: 14,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.title, style: context.texts.titleSmall),
                      const SizedBox(height: 2),
                      Text(
                        [
                          formatTime(item.startTime),
                          if (item.place != null) item.place!.name,
                          if (item.place?.address != null)
                            item.place!.address!,
                        ].where((part) => part.isNotEmpty).join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.texts.labelSmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      formatMoney(item.costEstimate, currency),
                      style: context.texts.labelSmall,
                    ),
                    if (item.isProtected)
                      const Padding(
                        padding: EdgeInsets.only(top: 3),
                        child: StatusChip('Protected', tone: ChipTone.jade),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          eyebrow: 'Snapshot',
          title: [
            if (trip.destination != null && trip.destination!.isNotEmpty)
              trip.destination!,
            '${formatDateShort(trip.startDate)} → ${formatDateShort(trip.endDate)}',
          ].join(' · '),
        ),
        if (snapshot.items.isEmpty)
          Text(
            'No confirmed items to snapshot yet.',
            style: context.texts.bodySmall,
          )
        else
          ...widgets,
        if (snapshot.members.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text('Members', style: context.texts.labelMedium),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final member in snapshot.members)
                StatusChip(
                  '${member.displayName} · ${titleCase(member.role)}',
                ),
            ],
          ),
        ],
        if (snapshot.pact != null) ...[
          const SizedBox(height: 14),
          Text('Pact', style: context.texts.labelMedium),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final entry in snapshot.pact!.mustDo)
                StatusChip('Must: $entry', tone: ChipTone.ember),
              for (final entry in snapshot.pact!.flexible)
                StatusChip('Flexible: $entry'),
              for (final entry in snapshot.pact!.confirmedTimes.entries)
                StatusChip('${entry.key} ${entry.value}'),
            ],
          ),
        ],
        const SizedBox(height: 12),
        Text(snapshot.disclosure, style: context.texts.labelSmall),
      ],
    );
  }
}
