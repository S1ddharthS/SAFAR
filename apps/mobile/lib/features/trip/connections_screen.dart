import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/social.dart';
import '../../core/providers.dart';
import '../../core/theme/safar_theme.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/safar_widgets.dart';

class ConnectionsScreen extends ConsumerStatefulWidget {
  const ConnectionsScreen({super.key, required this.tripId});

  final String tripId;

  @override
  ConsumerState<ConnectionsScreen> createState() => _ConnectionsScreenState();
}

class _ConnectionsScreenState extends ConsumerState<ConnectionsScreen> {
  bool _busy = false;

  Future<void> _connect(TravellerMatch match) async {
    final message = TextEditingController();
    final submitted = await showSafarSheet<bool>(
      context,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SafarSheetHeader(
            title: 'Connect with ${match.displayName}',
            subtitle:
                'They must accept before a connection exists. Your exact '
                'location is never shared.',
          ),
          TextField(
            controller: message,
            maxLines: 2,
            maxLength: 300,
            decoration: const InputDecoration(
              labelText: 'Note (optional)',
              hintText: 'We both love slow mornings and markets.',
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(sheetContext).pop(false),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.of(sheetContext).pop(true),
                  child: const Text('Send request'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    final note = message.text.trim();
    message.dispose();
    if (submitted != true) return;
    setState(() => _busy = true);
    try {
      await ref.read(socialRepositoryProvider).requestConnection(
            toUserId: match.id,
            tripId: widget.tripId,
            message: note.isEmpty ? null : note,
          );
      ref.invalidate(connectionRequestsProvider);
      _snack('Connection request sent.');
    } on Object catch (error) {
      _snack(error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _decide(ConnectionRequestItem request, bool accept) async {
    setState(() => _busy = true);
    try {
      await ref
          .read(socialRepositoryProvider)
          .decideConnection(request.id, accept: accept);
      ref.invalidate(connectionRequestsProvider);
      ref.invalidate(serendipityProvider);
      _snack(accept ? 'Connection accepted.' : 'Request declined.');
    } on Object catch (error) {
      _snack(error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.safar;
    final feed = ref.watch(serendipityProvider);
    final requests = ref.watch(connectionRequestsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Connections')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(serendipityProvider);
          ref.invalidate(connectionRequestsProvider);
          try {
            await ref.read(connectionRequestsProvider.future);
          } on Object {
            // Async sections render failures.
          }
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 36),
          children: [
            const InfoBanner(
              text:
                  'Traveller matches come from shared interests, never from '
                  'live location. Requests need mutual acceptance.',
              icon: Icons.handshake_outlined,
            ),
            const SizedBox(height: 16),
            requests.when(
              data: (items) {
                final incoming = items
                    .where((r) =>
                        r.direction == 'incoming' && r.status == 'pending')
                    .toList();
                final outgoing = items
                    .where((r) =>
                        r.direction == 'outgoing' && r.status == 'pending')
                    .toList();
                if (incoming.isEmpty && outgoing.isEmpty) {
                  return const SizedBox.shrink();
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SectionHeader(
                      eyebrow: 'Requests',
                      title: incoming.isEmpty
                          ? 'Waiting for replies'
                          : 'Waiting for you',
                    ),
                    for (final request in incoming)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: SafarCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  SafarAvatar(
                                    name: request.fromUser?.displayName ??
                                        'Traveller',
                                    size: 34,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          request.fromUser?.displayName ??
                                              'A traveller',
                                          style: context.texts.titleSmall,
                                        ),
                                        Text(
                                          'Asked ${timeAgo(request.createdAt)}',
                                          style: context.texts.labelSmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              if (request.message != null &&
                                  request.message!.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  request.message!,
                                  style: context.texts.bodySmall,
                                ),
                              ],
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: _busy
                                          ? null
                                          : () => _decide(request, false),
                                      child: const Text('Decline'),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: FilledButton(
                                      onPressed: _busy
                                          ? null
                                          : () => _decide(request, true),
                                      child: const Text('Accept'),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    for (final request in outgoing)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: SafarCard(
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Waiting for ${request.toUser?.displayName ?? 'a traveller'} to reply',
                                  style: context.texts.bodySmall,
                                ),
                              ),
                              const StatusChip('Pending', tone: ChipTone.ember),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                  ],
                );
              },
              loading: () => const SkeletonList(count: 1, itemHeight: 80),
              error: (error, stack) => SafarErrorView(
                message: error.toString(),
                onRetry: () => ref.invalidate(connectionRequestsProvider),
              ),
            ),
            SectionHeader(
              eyebrow: 'Signals',
              title: 'Travellers with shared interests',
            ),
            feed.when(
              data: (data) {
                if (!data.eligible) {
                  return SafarEmpty(
                    icon: Icons.person_search_outlined,
                    title: 'Matching is private by default',
                    message: data.message ??
                        'Complete your travel profile to receive interest-based '
                        'signals. Location is never used.',
                  );
                }
                if (data.matches.isEmpty) {
                  return const SafarEmpty(
                    icon: Icons.person_search_outlined,
                    title: 'No matches yet',
                    message:
                        'Signals appear as more travellers share compatible '
                        'interests.',
                  );
                }
                return Column(
                  children: [
                    for (final match in data.matches)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: SafarCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  SafarAvatar(
                                    name: match.displayName,
                                    size: 36,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          match.displayName,
                                          style: context.texts.titleSmall,
                                        ),
                                        if (match.headline != null ||
                                            match.homeCity != null)
                                          Text(
                                            [
                                              if (match.headline != null)
                                                match.headline!,
                                              if (match.homeCity != null)
                                                match.homeCity!,
                                            ].join(' · '),
                                            style: context.texts.labelSmall,
                                          ),
                                      ],
                                    ),
                                  ),
                                  StatusChip(
                                    '${(match.score * 100).round()}% fit',
                                    tone: ChipTone.jade,
                                  ),
                                ],
                              ),
                              if (match.sharedInterests.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    for (final interest
                                        in match.sharedInterests.take(4))
                                      StatusChip(interest),
                                  ],
                                ),
                              ],
                              if (match.reasons.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                for (final reason in match.reasons.take(3))
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 3),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Icon(
                                          Icons.circle,
                                          size: 5,
                                          color: palette.faint,
                                        ),
                                        const SizedBox(width: 7),
                                        Expanded(
                                          child: Text(
                                            reason,
                                            style: context.texts.labelSmall,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Text(
                                    'Privacy: ${titleCase(match.privacy)}',
                                    style: context.texts.labelSmall,
                                  ),
                                  const Spacer(),
                                  FilledButton.tonal(
                                    onPressed: _busy
                                        ? null
                                        : () => _connect(match),
                                    child: const Text('Connect'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    SourceLabel(source: data.disclosure),
                  ],
                );
              },
              loading: () => const SkeletonList(count: 2, itemHeight: 96),
              error: (error, stack) => SafarErrorView(
                message: error.toString(),
                onRetry: () => ref.invalidate(serendipityProvider),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
