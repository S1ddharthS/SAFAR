import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/common.dart';
import '../../core/providers.dart';
import '../../core/theme/safar_theme.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/safar_widgets.dart';
import '../auth/auth_controller.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'Your session ends on this device. Trip data stays with the group.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Stay'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(authControllerProvider.notifier).logout();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider);
    final palette = context.safar;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            tooltip: 'Notifications',
            onPressed: () => context.push('/notifications'),
            icon: const Icon(Icons.notifications_none_rounded),
          ),
          IconButton(
            tooltip: 'Settings',
            onPressed: () => context.push('/settings'),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(meProvider);
            try {
              await ref.read(meProvider.future);
            } on Object {
              // Rendered by AsyncView.
            }
          },
          child: AsyncView(
            value: me,
            onRetry: () => ref.invalidate(meProvider),
            builder: (data) => ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                Row(
                  children: [
                    SafarAvatar(
                      name: data.user.displayName,
                      size: 66,
                      imageUrl: data.user.avatarUrl,
                      highlight: true,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            data.user.displayName,
                            style: context.texts.headlineSmall,
                          ),
                          const SizedBox(height: 2),
                          Text(data.user.email, style: context.texts.bodySmall),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            children: [
                              if (data.user.isAdmin)
                                const StatusChip('Admin', tone: ChipTone.ember),
                              if (data.user.quietMode)
                                const StatusChip(
                                  'Quiet mode',
                                  tone: ChipTone.neutral,
                                ),
                              StatusChip(
                                data.profile.publicProfile
                                    ? 'Public profile'
                                    : 'Private profile',
                                tone: data.profile.publicProfile
                                    ? ChipTone.ember
                                    : ChipTone.jade,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (data.profile.headline != null ||
                    data.profile.homeCity != null) ...[
                  const SizedBox(height: 16),
                  SafarCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (data.profile.headline != null)
                          Text(
                            data.profile.headline!,
                            style: context.texts.titleMedium,
                          ),
                        if (data.profile.homeCity != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            data.profile.homeCity!,
                            style: context.texts.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                const SectionHeader(
                  eyebrow: 'Your signals',
                  title: 'Journey DNA',
                ),
                _DnaSummary(dna: data.dna),
                const SizedBox(height: 20),
                const SectionHeader(
                  eyebrow: 'Account',
                  title: 'How SAFAR works for you',
                ),
                SafarActionTile(
                  icon: Icons.fingerprint,
                  label: 'Journey DNA',
                  caption: 'Edit your travel signals',
                  onTap: () => context.push('/journey-dna'),
                ),
                const SizedBox(height: 8),
                SafarActionTile(
                  icon: Icons.tune,
                  label: 'Settings and privacy',
                  caption: 'Consents, visibility, theme',
                  onTap: () => context.push('/settings'),
                ),
                const SizedBox(height: 8),
                SafarActionTile(
                  icon: Icons.notifications_none_rounded,
                  label: 'Notifications',
                  caption: 'Votes, approvals and updates',
                  onTap: () => context.push('/notifications'),
                ),
                const SizedBox(height: 20),
                SafarCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Eyebrow('Consents'),
                      const SizedBox(height: 8),
                      Text(
                        'Policy ${data.policyVersion}',
                        style: context.texts.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final entry in data.consents.entries)
                            StatusChip(
                              entry.key,
                              tone: entry.value.granted
                                  ? ChipTone.jade
                                  : ChipTone.neutral,
                              icon: entry.value.granted
                                  ? Icons.check
                                  : Icons.remove,
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Consents are changeable at any time. Some are required for core features.',
                        style: context.texts.labelSmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: palette.rose,
                  ),
                  onPressed: () => _logout(context, ref),
                  icon: const Icon(Icons.logout, size: 18),
                  label: const Text('Sign out'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DnaSummary extends StatelessWidget {
  const _DnaSummary({required this.dna});

  final Dna dna;

  @override
  Widget build(BuildContext context) {
    final palette = context.safar;
    final entries = dna.scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (entries.isEmpty) {
      return SafarCard(
        onTap: () => context.push('/journey-dna'),
        child: Text(
          'No DNA signals yet. Add interests or set them explicitly.',
          style: context.texts.bodySmall,
        ),
      );
    }
    return SafarCard(
      onTap: () => context.push('/journey-dna'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Eyebrow('Top signals · editable'),
              ),
              Icon(Icons.arrow_outward, size: 15, color: palette.faint),
            ],
          ),
          const SizedBox(height: 10),
          for (final entry in entries.take(4)) ...[
            Row(
              children: [
                SizedBox(
                  width: 110,
                  child: Text(
                    titleCase(entry.key),
                    style: context.texts.bodySmall,
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
                Text(
                  entry.value.toStringAsFixed(1),
                  style: context.texts.labelSmall,
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          Text(
            dna.source == null ? 'Based on your activity' : 'Source: ${dna.source}',
            style: context.texts.labelSmall,
          ),
        ],
      ),
    );
  }
}
