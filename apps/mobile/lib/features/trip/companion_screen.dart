import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/itinerary.dart';
import '../../core/models/monitoring.dart';
import '../../core/native/share_links.dart';
import '../../core/providers.dart';
import '../../core/theme/safar_theme.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/safar_widgets.dart';

const _ttlChoices = [(60, '1 hour'), (1440, '24 hours'), (10080, '7 days')];

class CompanionScreen extends ConsumerStatefulWidget {
  const CompanionScreen({super.key, required this.tripId});

  final String tripId;

  @override
  ConsumerState<CompanionScreen> createState() => _CompanionScreenState();
}

class _CompanionScreenState extends ConsumerState<CompanionScreen> {
  String _purpose = 'vote';
  String? _targetId;
  int _ttl = 1440;
  int _formNonce = 0;
  bool _creating = false;
  String? _revokingId;
  CompanionLinkCreated? _created;

  String get _tripId => widget.tripId;

  void _setPurpose(String purpose) {
    if (purpose == _purpose) return;
    setState(() {
      _purpose = purpose;
      _targetId = null;
      _formNonce++;
    });
  }

  String _absolute(String url) => absoluteWebLink(url) ?? url;

  Future<void> _share() async {
    final created = _created;
    if (created == null) return;
    final url =
        absoluteWebLink(created.url) ?? 'safar://companion/${created.token}';
    final title = created.link.target?.title;
    final tripName = ref.read(tripProvider(_tripId)).valueOrNull?.name;
    final shared = await shareLink(
      url: url,
      subject: title == null ? 'SAFAR decision' : 'SAFAR: $title',
      message: title == null
          ? 'Your answer helps us decide${tripName == null ? '' : ' for $tripName'}. No account needed.'
          : '$title${tripName == null ? '' : ' · $tripName'}. One answer, no account needed.',
    );
    if (!shared) {
      await Clipboard.setData(ClipboardData(text: url));
      _notify('Sharing is not available here. The link was copied instead.');
    }
  }

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _create() async {
    final targetId = _targetId;
    if (targetId == null || _creating) return;
    setState(() => _creating = true);
    try {
      final created = await ref
          .read(companionRepositoryProvider)
          .create(
            _tripId,
            purpose: _purpose,
            targetId: targetId,
            ttlMinutes: _ttl,
          );
      ref.invalidate(companionLinksProvider(_tripId));
      if (!mounted) return;
      setState(() {
        _created = created;
        _targetId = null;
        _formNonce++;
      });
      _notify('Link created. Copy it now — the token is shown only once.');
    } on Object catch (error) {
      _notify(error.toString());
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _copy(String url) async {
    await Clipboard.setData(ClipboardData(text: _absolute(url)));
    _notify('Companion link copied.');
  }

  Future<void> _revoke(CompanionLink link) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Revoke this link?'),
        content: const Text(
          'The link will stop working immediately. Answers already received '
          'stay recorded anonymously.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _revokingId = link.id);
    try {
      await ref.read(companionRepositoryProvider).revoke(_tripId, link.id);
      ref.invalidate(companionLinksProvider(_tripId));
      _notify('Link revoked. It can no longer be answered.');
    } on Object catch (error) {
      _notify(error.toString());
    } finally {
      if (mounted) setState(() => _revokingId = null);
    }
  }

  Future<void> _viewResponses(CompanionLink link) async {
    try {
      final data = await ref
          .read(companionRepositoryProvider)
          .responses(_tripId, link.id);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Anonymous answers'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (data.items.isEmpty)
                    const Text('No answers yet.')
                  else
                    for (final answer in data.items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                StatusChip(
                                  titleCase(answer.value),
                                  tone: ChipTone.neutral,
                                ),
                                const Spacer(),
                                Text(
                                  timeAgo(answer.createdAt),
                                  style: Theme.of(dialogContext)
                                      .textTheme
                                      .labelSmall,
                                ),
                              ],
                            ),
                            if (answer.comment != null &&
                                answer.comment!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(answer.comment!),
                              ),
                          ],
                        ),
                      ),
                  const SizedBox(height: 6),
                  Text(
                    data.disclosure,
                    style: Theme.of(dialogContext).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } on Object catch (error) {
      _notify(error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.safar;
    final links = ref.watch(companionLinksProvider(_tripId));
    final proposals = ref.watch(proposalsProvider(_tripId));
    final itinerary = ref.watch(itineraryProvider(_tripId));

    final voteTargets =
        (proposals.valueOrNull ?? const <Proposal>[])
            .where((proposal) => proposal.status == 'open')
            .toList();
    final checkinTargets =
        (itinerary.valueOrNull?.items ?? const <ItineraryItem>[])
            .where((item) => item.status == 'confirmed')
            .toList();
    final targets = <({String id, String title})>[
      if (_purpose == 'vote')
        for (final proposal in voteTargets)
          (id: proposal.id, title: proposal.title)
      else
        for (final item in checkinTargets) (id: item.id, title: item.title),
    ];

    final rows = links.valueOrNull ?? const <CompanionLink>[];
    final active = rows.where((link) => link.active).length;
    final answers = rows.fold<int>(0, (sum, link) => sum + link.anonymousResponses);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back),
        ),
        title: const Text('One-Link Companion'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(companionLinksProvider(_tripId));
          ref.invalidate(proposalsProvider(_tripId));
          ref.invalidate(itineraryProvider(_tripId));
          try {
            await ref.read(companionLinksProvider(_tripId).future);
          } on Object {
            // The list surfaces the failure inline.
          }
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            const Eyebrow('One answer, no account'),
            const SizedBox(height: 8),
            Text('Share one question', style: context.texts.displaySmall),
            const SizedBox(height: 8),
            Text(
              'Send a single open decision or check-in to somebody outside '
              'the trip. Each link answers one question once, expires on its '
              'own and records no identity.',
              style: context.texts.bodySmall,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: StatTile(
                    label: 'Links',
                    value: '${rows.length}',
                    hint: 'For this trip',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: StatTile(
                    label: 'Active',
                    value: '$active',
                    hint: 'Answerable',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: StatTile(
                    label: 'Answers',
                    value: '$answers',
                    hint: 'Anonymous',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            SafarCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionHeader(
                    eyebrow: 'Create',
                    title: 'Create a link',
                  ),
                  SegmentedButton<String>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                        value: 'vote',
                        icon: Icon(Icons.how_to_vote_outlined, size: 17),
                        label: Text('Vote'),
                      ),
                      ButtonSegment(
                        value: 'checkin',
                        icon: Icon(Icons.person_pin_circle_outlined, size: 17),
                        label: Text('Check-in'),
                      ),
                    ],
                    selected: {_purpose},
                    onSelectionChanged: (selection) =>
                        _setPurpose(selection.first),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    key: ValueKey('$_purpose-$_formNonce-target'),
                    initialValue: _targetId,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: _purpose == 'vote'
                          ? 'Open decision'
                          : 'Confirmed item',
                      helperText: _purpose == 'vote'
                          ? 'Only open decisions can be shared.'
                          : 'Only confirmed items can be shared.',
                    ),
                    items: [
                      for (final target in targets)
                        DropdownMenuItem(
                          value: target.id,
                          child: Text(
                            target.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) => setState(() => _targetId = value),
                  ),
                  if (targets.isEmpty) ...[
                    const SizedBox(height: 10),
                    InfoBanner(
                      text: _purpose == 'vote'
                          ? 'There is no open decision to share right now.'
                          : 'No confirmed itinerary items are available yet.',
                      icon: Icons.hourglass_empty_rounded,
                    ),
                  ],
                  const SizedBox(height: 14),
                  Text('Expires', style: context.texts.labelMedium),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final (minutes, label) in _ttlChoices)
                        ChoiceChip(
                          label: Text(label),
                          selected: _ttl == minutes,
                          onSelected: (_) => setState(() => _ttl = minutes),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Single use regardless of expiry.',
                    style: context.texts.labelSmall,
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _targetId == null || _creating
                          ? null
                          : _create,
                      icon: _creating
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.link, size: 18),
                      label: const Text('Create link'),
                    ),
                  ),
                ],
              ),
            ),
            if (_created != null) ...[
              const SizedBox(height: 16),
              SafarCard(
                color: palette.jadeSoft,
                borderColor: palette.jade.withValues(alpha: 0.35),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.check_circle_outline,
                            size: 18, color: palette.jade),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Link ready — copy it now',
                            style: context.texts.titleSmall
                                ?.copyWith(color: palette.jade),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SelectableText(
                      _absolute(_created!.url),
                      style: context.texts.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _copy(_created!.url),
                            icon: const Icon(Icons.copy_all_outlined, size: 17),
                            label: const Text('Copy'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.tonalIcon(
                            onPressed: () => context.push(
                              '/companion/${_created!.token}',
                            ),
                            icon: const Icon(Icons.visibility_outlined, size: 17),
                            label: const Text('Preview'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _share,
                        icon: const Icon(Icons.ios_share_rounded, size: 17),
                        label: const Text('Share link'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'The token is not stored in readable form and is never '
                      'shown again. Preview opens the answer page on this device.',
                      style: context.texts.labelSmall,
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),
            const SectionHeader(
              eyebrow: 'Your links',
              title: 'Created for this trip',
            ),
            links.when(
              data: (items) {
                if (items.isEmpty) {
                  return SafarEmpty(
                    icon: Icons.link_off_rounded,
                    title: 'No links yet',
                    message:
                        'Create a vote or check-in link so one person outside '
                        'the trip can answer without an account.',
                  );
                }
                return Column(
                  children: [
                    for (final link in items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _LinkCard(
                          link: link,
                          busy: _revokingId == link.id,
                          onRevoke: () => _revoke(link),
                          onView: () => _viewResponses(link),
                        ),
                      ),
                  ],
                );
              },
              loading: () => const SkeletonList(count: 2, itemHeight: 96),
              error: (error, _) => SafarErrorView(
                message: error.toString(),
                onRetry: () => ref.invalidate(companionLinksProvider(_tripId)),
              ),
            ),
            const SizedBox(height: 18),
            const InfoBanner(
              text:
                  'Links are signed, scoped to one proposal or itinerary item, '
                  'single-use and expiring. Responses are anonymous: no '
                  'account, email, IP address or device identifier is stored. '
                  'A link never changes the confirmed plan.',
              icon: Icons.shield_outlined,
              tone: ChipTone.jade,
            ),
          ],
        ),
      ),
    );
  }
}

class _LinkCard extends StatelessWidget {
  const _LinkCard({
    required this.link,
    required this.busy,
    required this.onRevoke,
    required this.onView,
  });

  final CompanionLink link;
  final bool busy;
  final VoidCallback onRevoke;
  final VoidCallback onView;

  ChipTone get _tone => switch (link.status) {
    'active' => ChipTone.jade,
    'revoked' => ChipTone.rose,
    _ => ChipTone.neutral,
  };

  @override
  Widget build(BuildContext context) {
    final palette = context.safar;
    final target = link.target;
    return SafarCard(
      padding: const EdgeInsets.all(14),
      radius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        StatusChip(
                          link.purpose == 'vote' ? 'Vote' : 'Check-in',
                          tone: link.purpose == 'vote'
                              ? ChipTone.ember
                              : ChipTone.jade,
                        ),
                        Text(
                          target?.title ?? 'Target removed',
                          style: context.texts.titleSmall,
                        ),
                        StatusChip(titleCase(link.status), tone: _tone),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${link.usedCount}/${link.maxUses} used · expires '
                      '${formatDateShort(link.expiresAt)} '
                      '${formatClock(link.expiresAt)} · '
                      '${link.anonymousResponses} anonymous answer(s)',
                      style: context.texts.labelSmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (link.responseValues.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final entry in link.responseValues.entries)
                  StatusChip('${titleCase(entry.key)} · ${entry.value}'),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              if (link.anonymousResponses > 0)
                TextButton.icon(
                  onPressed: onView,
                  icon: const Icon(Icons.visibility_outlined, size: 16),
                  label: const Text('View answers'),
                ),
              const Spacer(),
              if (link.active)
                OutlinedButton.icon(
                  onPressed: busy ? null : onRevoke,
                  icon: busy
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(Icons.link_off, size: 16, color: palette.rose),
                  label: const Text('Revoke'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
