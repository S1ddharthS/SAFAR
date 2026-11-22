import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/invitation.dart';
import '../../core/models/trip.dart';
import '../../core/native/share_links.dart';
import '../../core/network/api_exception.dart';
import '../../core/providers.dart';
import '../../core/theme/safar_theme.dart';
import '../../core/widgets/safar_widgets.dart';

const _roleLabels = {'owner': 'Owner', 'admin': 'Admin', 'member': 'Member'};
const _scopes = {
  'full': 'Full plan',
  'vote': 'Vote only',
  'pulse': 'Trip Pulse',
  'view': 'View only',
};

typedef _InviteDraft = ({
  String? email,
  String role,
  String scope,
  int days,
});

String _groupSummary(int count, int? planned) {
  final travellers = count == 1 ? '1 traveller' : '$count travellers';
  if (planned == null || planned <= 0 || planned == count) return travellers;
  return '$travellers · plan sized for $planned';
}

class MembersScreen extends ConsumerStatefulWidget {
  const MembersScreen({super.key, required this.tripId});

  final String tripId;

  @override
  ConsumerState<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends ConsumerState<MembersScreen> {
  bool _busy = false;

  Trip? get _trip => ref.read(tripProvider(widget.tripId)).valueOrNull;

  void _refresh() {
    ref.invalidate(membersProvider(widget.tripId));
    ref.invalidate(invitationsProvider(widget.tripId));
    ref.invalidate(tripProvider(widget.tripId));
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _run(Future<void> Function() action, String success) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      _refresh();
      _snack(success);
    } on ApiException catch (error) {
      _refresh();
      _snack(error.message);
    } on Object catch (error) {
      _snack('That did not go through. $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changeRole(Member member, Trip trip) async {
    final options = <(String, String, String)>[
      if (member.role != 'admin')
        ('admin', 'Make admin', 'Admins can invite people and edit the plan.'),
      if (member.role != 'member')
        ('member', 'Make member', 'Members join votes and the group plan.'),
      if (trip.isOwner && member.role != 'owner')
        (
          'owner',
          'Transfer ownership',
          'You become an admin and cannot undo this yourself.',
        ),
    ];
    if (options.isEmpty) return;
    final choice = await showSafarSheet<String>(
      context,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SafarSheetHeader(
            title: member.displayName,
            subtitle: 'Currently ${_roleLabels[member.role] ?? member.role}.',
          ),
          for (final (role, label, caption) in options)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(label),
              subtitle: Text(caption),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(sheetContext).pop(role),
            ),
        ],
      ),
    );
    if (choice == null) return;
    await _run(
      () => ref
          .read(tripRepositoryProvider)
          .updateMemberRole(widget.tripId, member.id, choice),
      choice == 'owner'
          ? 'Ownership transferred to ${member.displayName}.'
          : '${member.displayName} is now ${_roleLabels[choice]}.',
    );
  }

  Future<void> _remove(Member member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Remove ${member.displayName}?'),
        content: const Text(
          'They lose access to this plan and its private group details '
          'immediately.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(
      () => ref
          .read(tripRepositoryProvider)
          .removeMember(widget.tripId, member.id),
      '${member.displayName} was removed.',
    );
  }

  Future<void> _leave(Member member, Trip trip) async {
    if (trip.isOwner) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Leave this trip?'),
        content: const Text(
          'You will need a new invitation to return. Nothing you added is '
          'deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Stay'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Leave trip'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(tripRepositoryProvider)
          .removeMember(widget.tripId, member.id);
      ref.invalidate(tripsProvider);
      if (!mounted) return;
      context.go('/dashboard');
      _snack('You left ${trip.name}.');
    } on ApiException catch (error) {
      _snack(error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _linkFor(TripInvitation invitation) {
    final path = invitation.path.isNotEmpty
        ? invitation.path
        : '/invite/${invitation.token}';
    return absoluteWebLink(path) ?? 'safar://invite/${invitation.token}';
  }

  Future<void> _share(TripInvitation invitation, String tripName) async {
    final link = _linkFor(invitation);
    final shared = await shareLink(
      url: link,
      subject: 'Join $tripName on SAFAR',
      message:
          'You are invited to plan $tripName with us on SAFAR. '
          'This link works once and expires on '
          '${invitation.expiresAt?.split('T').first ?? 'its own schedule'}.',
    );
    if (!shared && mounted) {
      await Clipboard.setData(ClipboardData(text: link));
      _snack('Sharing is unavailable here, so the link was copied.');
    }
  }

  Future<void> _invite() async {
    final submitted = await showSafarSheet<_InviteDraft>(
      context,
      builder: (sheetContext) => const _InviteSheet(),
    );
    if (submitted == null) return;
    setState(() => _busy = true);
    try {
      final repository = ref.read(tripRepositoryProvider);
      final invitation = await repository.createInvitation(
        widget.tripId,
        email: submitted.email,
        role: submitted.role,
        scope: submitted.scope,
        expiresInDays: submitted.days,
      );
      ref.invalidate(invitationsProvider(widget.tripId));
      if (!mounted) return;
      await _showInviteCreated(invitation);
    } on ApiException catch (error) {
      _snack(error.message);
    } on Object catch (error) {
      _snack('The invitation was not created. $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showInviteCreated(TripInvitation invitation) async {
    final link = _linkFor(invitation);
    final tripName = _trip?.name ?? 'our trip';
    await showSafarSheet<void>(
      context,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SafarSheetHeader(
            title: 'Invitation ready',
            subtitle: 'Single use, expires in ${invitation.expiresAt?.split('T').first}.',
          ),
          SelectableText(link, style: context.texts.bodySmall),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: link));
                    if (sheetContext.mounted) {
                      Navigator.of(sheetContext).pop();
                      _snack('Link copied.');
                    }
                  },
                  icon: const Icon(Icons.copy_rounded, size: 17),
                  label: const Text('Copy'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () async {
                    Navigator.of(sheetContext).pop();
                    await _share(invitation, tripName);
                  },
                  icon: const Icon(Icons.ios_share_rounded, size: 17),
                  label: const Text('Share'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final trip = ref.watch(tripProvider(widget.tripId)).valueOrNull;
    final canManage = trip?.canManage ?? false;
    return Scaffold(
      appBar: AppBar(
        title: const Text('People'),
        actions: [
          if (canManage)
            IconButton(
              tooltip: 'Invite someone',
              onPressed: _busy ? null : _invite,
              icon: const Icon(Icons.person_add_alt_1_rounded),
            ),
        ],
      ),
      body: AsyncView<List<Member>>(
        value: ref.watch(membersProvider(widget.tripId)),
        onRetry: () => ref.invalidate(membersProvider(widget.tripId)),
        skeleton: const SkeletonList(count: 4, itemHeight: 76),
        builder: (members) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 36),
          children: [
            if (trip != null)
              InfoBanner(
                text: canManage
                    ? 'You manage this trip. Invitations are single use and '
                          'can be revoked at any time.'
                    : 'Everyone here sees the shared plan. Private limits and '
                          'preferences stay with each member.',
                icon: canManage ? Icons.admin_panel_settings_outlined : Icons.lock_outline,
                tone: canManage ? ChipTone.ember : ChipTone.neutral,
              ),
            const SizedBox(height: 16),
            SectionHeader(
              eyebrow: 'The group',
              title: _groupSummary(members.length, trip?.groupSize),
            ),
            const SizedBox(height: 10),
            for (final member in members)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _MemberCard(
                  member: member,
                  trip: trip,
                  busy: _busy,
                  canManage: canManage,
                  onChangeRole: trip == null ? null : () => _changeRole(member, trip),
                  onRemove: () => _remove(member),
                  onLeave: trip == null ? null : () => _leave(member, trip),
                ),
              ),
            if (canManage) ...[
              const SizedBox(height: 14),
              SectionHeader(
                eyebrow: 'Invitations',
                title: 'Open invites',
                action: 'New',
                onAction: _busy ? null : _invite,
              ),
              const SizedBox(height: 8),
              AsyncView<List<TripInvitation>>(
                value: ref.watch(invitationsProvider(widget.tripId)),
                onRetry: () =>
                    ref.invalidate(invitationsProvider(widget.tripId)),
                skeleton: const SkeletonList(count: 2, itemHeight: 84),
                builder: (invitations) => invitations.isEmpty
                    ? const SafarEmpty(
                        icon: Icons.mark_email_unread_outlined,
                        title: 'No open invitations',
                        message:
                            'Create a single-use link for the next person who '
                            'joins the trip.',
                      )
                    : Column(
                        children: [
                          for (final invitation in invitations)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _InvitationCard(
                                invitation: invitation,
                                busy: _busy,
                                onShare: () => _share(
                                  invitation,
                                  trip?.name ?? 'this trip',
                                ),
                                onRevoke: () => _run(
                                  () => ref
                                      .read(tripRepositoryProvider)
                                      .revokeInvitation(
                                        widget.tripId,
                                        invitation.id,
                                      ),
                                  'Invitation revoked.',
                                ),
                              ),
                            ),
                        ],
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InviteSheet extends StatefulWidget {
  const _InviteSheet();

  @override
  State<_InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends State<_InviteSheet> {
  final _email = TextEditingController();
  var _role = 'member';
  var _scope = 'full';
  var _days = 7;
  String? _error;

  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SafarSheetHeader(
            title: 'Invite someone',
            subtitle:
                'Links work once and expire. Leave email empty for a link '
                'you can pass on yourself.',
          ),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            decoration: InputDecoration(
              labelText: 'Email (optional)',
              helperText: 'If set, only that address can accept.',
              errorText: _error,
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _role,
            decoration: const InputDecoration(labelText: 'Role'),
            items: const [
              DropdownMenuItem(value: 'member', child: Text('Member')),
              DropdownMenuItem(value: 'admin', child: Text('Admin')),
            ],
            onChanged: (value) => setState(() => _role = value ?? 'member'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _scope,
            decoration: const InputDecoration(labelText: 'Access'),
            items: [
              for (final entry in _scopes.entries)
                DropdownMenuItem(value: entry.key, child: Text(entry.value)),
            ],
            onChanged: (value) => setState(() => _scope = value ?? 'full'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: _days,
            decoration: const InputDecoration(labelText: 'Expires'),
            items: const [
              DropdownMenuItem(value: 1, child: Text('In 1 day')),
              DropdownMenuItem(value: 3, child: Text('In 3 days')),
              DropdownMenuItem(value: 7, child: Text('In 7 days')),
              DropdownMenuItem(value: 14, child: Text('In 14 days')),
              DropdownMenuItem(value: 30, child: Text('In 30 days')),
            ],
            onChanged: (value) => setState(() => _days = value ?? 7),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: () {
                    final email = _email.text.trim();
                    if (email.isNotEmpty &&
                        !_emailPattern.hasMatch(email)) {
                      setState(
                        () => _error =
                            'Enter a valid email, or leave it empty for a link.',
                      );
                      return;
                    }
                    Navigator.of(context).pop<_InviteDraft>((
                      email: email.isEmpty ? null : email,
                      role: _role,
                      scope: _scope,
                      days: _days,
                    ));
                  },
                  child: const Text('Create invite'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MemberCard extends StatelessWidget {
  const _MemberCard({
    required this.member,
    required this.trip,
    required this.busy,
    required this.canManage,
    required this.onChangeRole,
    required this.onRemove,
    required this.onLeave,
  });

  final Member member;
  final Trip? trip;
  final bool busy;
  final bool canManage;
  final VoidCallback? onChangeRole;
  final VoidCallback onRemove;
  final VoidCallback? onLeave;

  @override
  Widget build(BuildContext context) {
    final palette = context.safar;
    final canEditOther =
        canManage && !member.isSelf && member.role != 'owner';
    return SafarCard(
      child: Row(
        children: [
          SafarAvatar(
            name: member.displayName,
            size: 40,
            highlight: member.isSelf,
            imageUrl: member.user?.avatarUrl,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        member.displayName,
                        style: context.texts.titleSmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (member.isSelf) ...[
                      const SizedBox(width: 6),
                      Text('you', style: context.texts.labelSmall),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    StatusChip(
                      _roleLabels[member.role] ?? member.role,
                      tone: member.role == 'owner'
                          ? ChipTone.ember
                          : member.role == 'admin'
                          ? ChipTone.jade
                          : ChipTone.neutral,
                    ),
                    if (member.isSelf) ...[
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          member.user?.email ?? '',
                          style: context.texts.labelSmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (member.isSelf && trip?.isOwner == false)
            TextButton(
              onPressed: busy ? null : onLeave,
              style: TextButton.styleFrom(foregroundColor: palette.rose),
              child: const Text('Leave'),
            )
          else if (canEditOther)
            PopupMenuButton<String>(
              tooltip: 'Manage ${member.displayName}',
              enabled: !busy,
              onSelected: (value) {
                if (value == 'remove') {
                  onRemove();
                } else {
                  onChangeRole?.call();
                }
              },
              itemBuilder: (menuContext) => [
                PopupMenuItem(value: 'role', child: const Text('Change role')),
                PopupMenuItem(
                  value: 'remove',
                  child: Text(
                    'Remove from trip',
                    style: TextStyle(color: palette.rose),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _InvitationCard extends StatelessWidget {
  const _InvitationCard({
    required this.invitation,
    required this.busy,
    required this.onShare,
    required this.onRevoke,
  });

  final TripInvitation invitation;
  final bool busy;
  final VoidCallback onShare;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final state = invitation.accepted
        ? 'Accepted'
        : invitation.expired
        ? 'Expired'
        : 'Open';
    final tone = invitation.accepted || invitation.expired
        ? ChipTone.neutral
        : ChipTone.jade;
    return SafarCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  invitation.email ?? 'Anyone with the link',
                  style: context.texts.titleSmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              StatusChip(state, tone: tone),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${_roleLabels[invitation.role] ?? invitation.role} · '
            '${_scopes[invitation.scope] ?? invitation.scope} · '
            'expires ${invitation.expiresAt?.split('T').first ?? 'later'}',
            style: context.texts.bodySmall,
          ),
          if (invitation.usable) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                TextButton.icon(
                  onPressed: busy ? null : onShare,
                  icon: const Icon(Icons.ios_share_rounded, size: 16),
                  label: const Text('Share'),
                ),
                TextButton.icon(
                  onPressed: busy ? null : onRevoke,
                  icon: const Icon(Icons.link_off_rounded, size: 16),
                  label: const Text('Revoke'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
