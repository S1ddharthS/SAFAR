import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/safar_theme.dart';
import '../../core/widgets/safar_widgets.dart';

class MoreHubScreen extends ConsumerWidget {
  const MoreHubScreen({super.key, required this.tripId});

  final String tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.safar;
    final trip = ref.watch(tripProvider(tripId)).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Eyebrow('All tools'),
            Text(
              (trip?.name.trim().isNotEmpty ?? false)
                  ? trip!.name
                  : 'Trip workspace',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 36),
        children: [
          InfoBanner(
            text:
                'Every tool reads the live trip data. Changes to the confirmed '
                'plan still go through group approval.',
            icon: Icons.hub_outlined,
            tone: ChipTone.ember,
          ),
          const SizedBox(height: 20),
          _Group(
            title: 'Decide & adapt',
            caption: 'Compare, negotiate and watch the plan without rewriting it.',
            tiles: [
              _HubTile(
                icon: Icons.compare_arrows_rounded,
                title: 'Trip Twin',
                caption: 'Compare a confirmed day with an alternative.',
                onTap: () => context.push('/trips/$tripId/twin'),
              ),
              _HubTile(
                icon: Icons.handshake_outlined,
                title: 'Negotiator',
                caption: 'Find a fair compromise between two options.',
                onTap: () => context.push('/trips/$tripId/negotiate'),
              ),
              _HubTile(
                icon: Icons.schedule_outlined,
                title: 'Opportunity clock',
                caption: 'What still fits in today’s free windows.',
                onTap: () => context.push('/trips/$tripId/opportunity'),
              ),
              _HubTile(
                icon: Icons.monitor_heart_outlined,
                title: 'Plan intelligence',
                caption: 'Effort, fragility, domino and Shadowplans.',
                onTap: () => context.push('/trips/$tripId/plan'),
              ),
              _HubTile(
                icon: Icons.notification_important_outlined,
                title: 'Material watch',
                caption: 'Alert only when a tracked fact changes.',
                onTap: () => context.push('/trips/$tripId/watch'),
              ),
              _HubTile(
                icon: Icons.question_answer_outlined,
                title: 'Ground questions',
                caption: 'Ask opted-in locals for observations.',
                onTap: () => context.push('/trips/$tripId/ground'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _Group(
            title: 'Group',
            caption: 'Agreements, shared work and ways to include people.',
            tiles: [
              _HubTile(
                icon: Icons.group_outlined,
                title: 'People & invites',
                caption: 'Invite someone, change roles or remove a member.',
                onTap: () => context.push('/trips/$tripId/members'),
              ),
              _HubTile(
                icon: Icons.rule_outlined,
                title: 'Journey Pact',
                caption: 'Must-dos, exceptions and private limits.',
                onTap: () => context.push('/trips/$tripId/pact'),
              ),
              _HubTile(
                icon: Icons.checklist_rtl_outlined,
                title: 'Tasks',
                caption: 'Shared planner with load balance.',
                onTap: () => context.push('/trips/$tripId/tasks'),
              ),
              _HubTile(
                icon: Icons.call_split_rounded,
                title: 'Branches',
                caption: 'Split the group and plan a reunion.',
                onTap: () => context.push('/trips/$tripId/branches'),
              ),
              _HubTile(
                icon: Icons.link_rounded,
                title: 'One-Link Companion',
                caption: 'Let someone answer once, without an account.',
                onTap: () => context.push('/trips/$tripId/companion'),
              ),
              _HubTile(
                icon: Icons.flag_outlined,
                title: 'Missions',
                caption: 'Optional, self-reported travel challenges.',
                onTap: () => context.push('/trips/$tripId/missions'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _Group(
            title: 'Explore',
            caption: 'Places near the base and travellers on a similar path.',
            tiles: [
              _HubTile(
                icon: Icons.map_outlined,
                title: 'Nearby map',
                caption: 'Estimated distances from the trip base.',
                onTap: () => context.push('/trips/$tripId/nearby'),
              ),
              _HubTile(
                icon: Icons.diversity_3_outlined,
                title: 'Travel Circles',
                caption: 'Topic communities and their posts.',
                onTap: () => context.push('/trips/$tripId/circles'),
              ),
              _HubTile(
                icon: Icons.people_alt_outlined,
                title: 'Connections',
                caption: 'Consent-based traveller matches.',
                onTap: () => context.push('/trips/$tripId/connections'),
              ),
              _HubTile(
                icon: Icons.people_outline_rounded,
                title: 'Local contributors',
                caption: 'Opted-in locals, not tourism authorities.',
                onTap: () => context.push('/trips/$tripId/contributors'),
              ),
              _HubTile(
                icon: Icons.timeline_rounded,
                title: 'Journey thread',
                caption: 'Traditions you loved on earlier trips.',
                onTap: () => context.push('/trips/$tripId/thread'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _Group(
            title: 'Offline & records',
            caption: 'Carry the confirmed plan when the network is not there.',
            tiles: [
              _HubTile(
                icon: Icons.shield_outlined,
                title: 'Solo Safety Centre',
                caption: 'Check-ins, emergency contacts and local offline emergency dialers.',
                onTap: () => context.push('/trips/$tripId/safety'),
              ),
              _HubTile(
                icon: Icons.cloud_off_outlined,
                title: 'Offline snapshot',
                caption: 'Confirmed plan, members and pact — read-only.',
                onTap: () => context.push('/trips/$tripId/offline'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SafarCard(
            color: palette.surface,
            child: Row(
              children: [
                Icon(Icons.lock_outline, size: 18, color: palette.ember),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Private budgets, accessibility needs and private memories '
                    'never appear in shared views. Sharing is always opt-in.',
                    style: context.texts.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.caption, required this.tiles});

  final String title;
  final String caption;
  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: title),
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: Text(caption, style: context.texts.bodySmall),
        ),
        for (var index = 0; index < tiles.length; index++) ...[
          if (index > 0) const SizedBox(height: 8),
          tiles[index],
        ],
      ],
    );
  }
}

class _HubTile extends StatelessWidget {
  const _HubTile({
    required this.icon,
    required this.title,
    required this.caption,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String caption;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.safar;
    return SafarCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      radius: 18,
      child: Row(
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
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.texts.titleSmall),
                const SizedBox(height: 2),
                Text(
                  caption,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.bodySmall,
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, size: 18, color: palette.faint),
        ],
      ),
    );
  }
}
