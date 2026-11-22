import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/common.dart';
import '../../core/network/api_exception.dart';
import '../../core/providers.dart';
import '../../core/theme/safar_theme.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/safar_widgets.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  bool _busy = false;

  Future<void> _refresh() async {
    ref.invalidate(notificationsProvider);
    try {
      await ref.read(notificationsProvider.future);
    } on Object {
      // Rendered by AsyncView.
    }
  }

  Future<void> _markAll() async {
    setState(() => _busy = true);
    try {
      await ref.read(userRepositoryProvider).markAllRead();
      ref.invalidate(notificationsProvider);
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(NotificationItem item) async {
    if (!item.read) {
      try {
        await ref.read(userRepositoryProvider).markRead(item.id);
        ref.invalidate(notificationsProvider);
      } on ApiException {
        // Reading the notification is best-effort; navigation still works.
      }
    }
    if (!mounted) return;
    final link = item.link;
    if (link != null && link.startsWith('/')) {
      context.push(link);
      return;
    }
    if (item.tripId != null) {
      context.push('/trips/${item.tripId}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(notificationsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          TextButton(
            onPressed: _busy || (feed.valueOrNull?.unread ?? 0) == 0
                ? null
                : _markAll,
            child: const Text('Mark all read'),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: AsyncView(
            value: feed,
            onRetry: () => ref.invalidate(notificationsProvider),
            builder: (data) {
              if (data.items.isEmpty) {
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: const [
                    SizedBox(height: 50),
                    SafarEmpty(
                      icon: Icons.notifications_none,
                      title: 'Nothing new',
                      message:
                          'Votes, approvals and trip updates will appear here. '
                          'Quiet mode limits what SAFAR sends.',
                    ),
                  ],
                );
              }
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                children: [
                  Eyebrow(
                    data.unread == 0
                        ? 'All caught up'
                        : '${data.unread} unread',
                  ),
                  const SizedBox(height: 10),
                  for (final item in data.items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _NotificationTile(
                        item: item,
                        onTap: () => _open(item),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.item, required this.onTap});

  final NotificationItem item;
  final VoidCallback onTap;

  IconData get _icon => switch (item.kind) {
    'vote' => Icons.how_to_vote_outlined,
    'approval' => Icons.verified_outlined,
    'memory' => Icons.photo_library_outlined,
    'rescue' => Icons.healing_outlined,
    'expense' => Icons.receipt_long_outlined,
    _ => Icons.notifications_none,
  };

  @override
  Widget build(BuildContext context) {
    final palette = context.safar;
    return SafarCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      radius: 18,
      color: item.read ? null : palette.emberSoft.withValues(alpha: 0.45),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: item.read ? palette.raised : palette.emberSoft,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(
              _icon,
              size: 18,
              color: item.read ? palette.muted : palette.ember,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.title,
                        style: context.texts.titleSmall,
                      ),
                    ),
                    if (!item.read)
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: palette.ember,
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
                if (item.body != null && item.body!.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(item.body!, style: context.texts.bodySmall),
                ],
                const SizedBox(height: 4),
                Text(
                  '${titleCase(item.kind)} · ${timeAgo(item.createdAt)}',
                  style: context.texts.labelSmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right, size: 18, color: palette.faint),
        ],
      ),
    );
  }
}
