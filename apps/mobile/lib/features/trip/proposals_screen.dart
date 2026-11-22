import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/itinerary.dart';
import '../../core/providers.dart';
import '../../core/realtime/live_status_chip.dart';
import '../../core/theme/safar_theme.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/safar_widgets.dart';
import '../auth/auth_controller.dart';

class ProposalsScreen extends ConsumerStatefulWidget {
  const ProposalsScreen({super.key, required this.tripId});

  final String tripId;

  @override
  ConsumerState<ProposalsScreen> createState() => _ProposalsScreenState();
}

class _ProposalsScreenState extends ConsumerState<ProposalsScreen> {
  String _filter = 'open';
  bool _busy = false;

  Future<void> _refresh() async {
    ref.invalidate(proposalsProvider(widget.tripId));
    ref.invalidate(itineraryProvider(widget.tripId));
    try {
      await ref.read(proposalsProvider(widget.tripId).future);
    } on Object {
      // AsyncView renders failures.
    }
  }

  Future<void> _vote(Proposal proposal, String value) async {
    final comment = TextEditingController();
    if (proposal.myVote == value) {
      // Tapping the current vote is idempotent; offer a comment instead.
    }
    final submitted = await showSafarSheet<bool>(
      context,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SafarSheetHeader(
            title: value == 'yes'
                ? 'Vote yes'
                : value == 'no'
                ? 'Vote no'
                : 'Abstain',
            subtitle:
                'Your vote is attributed to you. Comments are visible to this trip.',
          ),
          TextField(
            controller: comment,
            maxLines: 2,
            maxLength: 500,
            decoration: const InputDecoration(
              labelText: 'Comment (optional)',
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
                  child: Text(
                    value == 'yes'
                        ? 'Record yes'
                        : value == 'no'
                        ? 'Record no'
                        : 'Abstain',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    final text = comment.text.trim();
    comment.dispose();
    if (submitted != true) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(itineraryRepositoryProvider)
          .vote(
            widget.tripId,
            proposal.id,
            value,
            comment: text.isEmpty ? null : text,
          );
      await _refresh();
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _decide(Proposal proposal, String action) async {
    final verb = switch (action) {
      'approve' => 'Approve',
      'reject' => 'Reject',
      _ => 'Withdraw',
    };
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$verb this proposal?'),
        content: Text(
          action == 'approve'
              ? 'Approving confirms “${proposal.title}” into the itinerary. '
                    'A new version is recorded.'
              : action == 'reject'
              ? '“${proposal.title}” will not change the confirmed plan.'
              : 'Your proposal “${proposal.title}” will be removed from voting.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: action == 'approve' ? null : context.safar.rose,
            ),
            child: Text(verb),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      final repository = ref.read(itineraryRepositoryProvider);
      switch (action) {
        case 'approve':
          await repository.approve(widget.tripId, proposal.id);
        case 'reject':
          await repository.reject(widget.tripId, proposal.id);
        default:
          await repository.withdraw(widget.tripId, proposal.id);
      }
      ref.invalidate(itineraryProvider(widget.tripId));
      ref.invalidate(tripProvider(widget.tripId));
      ref.invalidate(engineProvider(widget.tripId));
      await _refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Proposal ${verb.toLowerCase()}d.')),
      );
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final proposals = ref.watch(proposalsProvider(widget.tripId));
    final itinerary = ref.watch(itineraryProvider(widget.tripId)).valueOrNull;
    final me = ref.watch(authControllerProvider).user;
    final role = itinerary?.myRole ?? 'member';
    final canManage = role == 'owner' || role == 'admin';

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back),
        ),
        title: const Text('Group decisions'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(
              child: TripLiveChip(tripId: widget.tripId, compact: true),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: AsyncView(
          value: proposals,
          onRetry: () => ref.invalidate(proposalsProvider(widget.tripId)),
          builder: (items) {
            final filtered = switch (_filter) {
              'open' => items.where((p) => p.status == 'open').toList(),
              'decided' => items.where((p) => p.decided).toList(),
              _ => items,
            };
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
                children: [
                  const Eyebrow('Proposals'),
                  const SizedBox(height: 8),
                  Text(
                    'The group decides.\nThe plan waits.',
                    style: context.texts.displaySmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'A confirmed item only changes after a proposal is approved. '
                    'Votes and comments stay inside this trip.',
                    style: context.texts.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final option in const [
                          ('open', 'Open'),
                          ('decided', 'Decided'),
                          ('all', 'All'),
                        ])
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(option.$2),
                              selected: _filter == option.$1,
                              onSelected: (_) =>
                                  setState(() => _filter = option.$1),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (filtered.isEmpty)
                    SafarEmpty(
                      title: _filter == 'open'
                          ? 'No open proposals'
                          : 'No proposals here',
                      message: _filter == 'open'
                          ? 'Send an option from the engine to start a vote.'
                          : 'Proposals appear here after the group votes.',
                      icon: Icons.how_to_vote_outlined,
                      action: FilledButton(
                        onPressed: () =>
                            context.push('/trips/${widget.tripId}/engine'),
                        child: const Text('Open the engine'),
                      ),
                    )
                  else
                    for (final proposal in filtered)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _ProposalCard(
                          tripId: widget.tripId,
                          proposal: proposal,
                          busy: _busy,
                          myUserId: me?.id,
                          canManage: canManage,
                          onVote: (value) => _vote(proposal, value),
                          onDecide: (action) => _decide(proposal, action),
                        ),
                      ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ProposalCard extends ConsumerStatefulWidget {
  const _ProposalCard({
    required this.tripId,
    required this.proposal,
    required this.busy,
    required this.canManage,
    required this.onVote,
    required this.onDecide,
    this.myUserId,
  });

  final String tripId;
  final Proposal proposal;
  final bool busy;
  final bool canManage;
  final String? myUserId;
  final ValueChanged<String> onVote;
  final ValueChanged<String> onDecide;

  @override
  ConsumerState<_ProposalCard> createState() => _ProposalCardState();
}

class _ProposalCardState extends ConsumerState<_ProposalCard> {
  CostImpact? _impact;
  bool _impactBusy = false;
  bool _expanded = false;

  Future<void> _toggleImpact() async {
    if (_expanded) {
      setState(() => _expanded = false);
      return;
    }
    final proposal = widget.proposal;
    final inline = proposal.costImpact;
    if (inline != null) {
      setState(() {
        _impact = inline;
        _expanded = true;
      });
      return;
    }
    setState(() {
      _expanded = true;
      _impactBusy = true;
    });
    try {
      final detail = await ref
          .read(itineraryRepositoryProvider)
          .getProposal(widget.tripId, proposal.id);
      if (!mounted) return;
      setState(() => _impact = detail.costImpact);
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      if (mounted) setState(() => _impactBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.safar;
    final proposal = widget.proposal;
    final busy = widget.busy;
    final canManage = widget.canManage;
    final myUserId = widget.myUserId;
    final onVote = widget.onVote;
    final onDecide = widget.onDecide;
    final votes = proposal.votes;
    final total = votes.total;
    final isOpen = proposal.status == 'open';
    final isMine = proposal.author?.id == myUserId;
    return SafarCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StatusChip(
                proposal.kind,
                tone: proposal.kind == 'replace_item'
                    ? ChipTone.ember
                    : ChipTone.neutral,
              ),
              const SizedBox(width: 6),
              StatusChip(
                proposal.status,
                tone: proposal.status == 'approved'
                    ? ChipTone.jade
                    : proposal.status == 'rejected'
                    ? ChipTone.rose
                    : ChipTone.ember,
              ),
              const Spacer(),
              if (proposal.createdAt.isNotEmpty)
                Text(
                  timeAgo(proposal.createdAt),
                  style: context.texts.labelSmall,
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(proposal.title, style: context.texts.titleMedium),
          if (proposal.summary != null && proposal.summary!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(proposal.summary!, style: context.texts.bodySmall),
          ],
          const SizedBox(height: 6),
          Text(
            [
              if (proposal.author != null)
                'Proposed by ${proposal.author!.displayName}',
              if (proposal.targetDay != null)
                'for ${formatDateShort(proposal.targetDay)}',
            ].join(' · '),
            style: context.texts.labelSmall,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _VotePill(label: 'Yes', count: votes.yes, color: palette.jade),
              const SizedBox(width: 6),
              _VotePill(label: 'No', count: votes.no, color: palette.rose),
              const SizedBox(width: 6),
              _VotePill(label: 'Abstain', count: votes.abstain, color: palette.faint),
              const Spacer(),
              if (proposal.myVote != null)
                Text(
                  'You voted ${proposal.myVote}',
                  style: context.texts.labelSmall,
                ),
            ],
          ),
          if (total > 0) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: Row(
                children: [
                  if (votes.yes > 0)
                    Expanded(
                      flex: votes.yes,
                      child: Container(height: 5, color: palette.jade),
                    ),
                  if (votes.abstain > 0)
                    Expanded(
                      flex: votes.abstain,
                      child: Container(height: 5, color: palette.line),
                    ),
                  if (votes.no > 0)
                    Expanded(
                      flex: votes.no,
                      child: Container(height: 5, color: palette.rose),
                    ),
                ],
              ),
            ),
          ],
          if (proposal.pactConflicts.isNotEmpty) ...[
            const SizedBox(height: 10),
            InfoBanner(
              text: proposal.pactConflicts
                  .map((conflict) => '${conflict.item}: ${conflict.resolution}')
                  .join(' '),
              icon: Icons.handshake_outlined,
              tone: ChipTone.ember,
            ),
          ],
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _toggleImpact,
              icon: Icon(
                _expanded ? Icons.expand_less : Icons.request_quote_outlined,
                size: 17,
              ),
              label: Text(_expanded ? 'Hide impact' : 'Cost & conflicts'),
            ),
          ),
          if (_expanded) _ImpactPanel(impact: _impact, loading: _impactBusy),
          if (proposal.comments.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final comment in proposal.comments.take(3))
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text(
                  '${comment.user?.displayName ?? 'Traveller'}: ${comment.comment}',
                  style: context.texts.bodySmall,
                ),
              ),
          ],
          if (isOpen) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: busy ? null : () => onVote('yes'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: palette.jade,
                    ),
                    child: const Text('Yes'),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: OutlinedButton(
                    onPressed: busy ? null : () => onVote('no'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: palette.rose,
                    ),
                    child: const Text('No'),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: OutlinedButton(
                    onPressed: busy ? null : () => onVote('abstain'),
                    child: const Text('Abstain'),
                  ),
                ),
              ],
            ),
            if (canManage || isMine) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: busy ? null : () => onDecide('approve'),
                      child: const Text('Approve into plan'),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    tooltip: 'Reject proposal',
                    onPressed: busy ? null : () => onDecide('reject'),
                    icon: Icon(
                      Icons.close,
                      size: 19,
                      color: palette.rose,
                    ),
                  ),
                  if (isMine)
                    IconButton(
                      tooltip: 'Withdraw proposal',
                      onPressed: busy ? null : () => onDecide('withdraw'),
                      icon: const Icon(Icons.undo, size: 19),
                    ),
                ],
              ),
            ],
            Text(
              'Approval is checked against the trip pact, protected time and member constraints.',
              style: context.texts.labelSmall?.copyWith(color: palette.faint),
            ),
          ],
        ],
      ),
    );
  }
}

class _ImpactPanel extends StatelessWidget {
  const _ImpactPanel({required this.impact, required this.loading});

  final CostImpact? impact;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final palette = context.safar;
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    final data = impact;
    if (data == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          'No impact estimate is available for this proposal yet.',
          style: context.texts.labelSmall,
        ),
      );
    }
    final delta = data.totalDelta;
    final sign = delta > 0 ? '+' : '';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.raised,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (data.error != null && data.error!.isNotEmpty) ...[
            InfoBanner(text: data.error!, icon: Icons.error_outline),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              Expanded(
                child: Text(
                  '$sign${formatMoney(delta, data.currency)} total',
                  style: context.texts.titleSmall,
                ),
              ),
              Text(
                '≈ ${formatMoney(data.perMemberEstimate, data.currency)} / person',
                style: context.texts.labelSmall,
              ),
            ],
          ),
          if (data.note.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(data.note, style: context.texts.labelSmall),
          ],
          if (data.operations.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final operation in data.operations)
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Row(
                  children: [
                    StatusChip(operation.op),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        [
                          operation.title ?? '',
                          if (operation.day != null)
                            formatDateShort(operation.day),
                          if (operation.startTime != null)
                            formatTime(operation.startTime),
                        ].where((part) => part.isNotEmpty).join(' · '),
                        style: context.texts.labelSmall,
                      ),
                    ),
                    if (operation.cost != null)
                      Text(
                        formatMoney(operation.cost, data.currency),
                        style: context.texts.labelSmall,
                      ),
                  ],
                ),
              ),
          ],
          if (data.budgetConflicts.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Eyebrow('Budget conflicts'),
            const SizedBox(height: 4),
            for (final conflict in data.budgetConflicts)
              Text(
                '• ${conflict.item ?? 'Member'}: ${conflict.summary}',
                style: context.texts.labelSmall,
              ),
          ],
          if (data.pactConflicts.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Eyebrow('Pact conflicts'),
            const SizedBox(height: 4),
            for (final conflict in data.pactConflicts)
              Text(
                '• ${conflict.item ?? 'Rule'}: ${conflict.summary}',
                style: context.texts.labelSmall,
              ),
          ],
          if (data.scheduleConflicts.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Eyebrow('Schedule conflicts'),
            const SizedBox(height: 4),
            for (final conflict in data.scheduleConflicts)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '• ${conflict.item ?? 'Item'}: ${conflict.summary}',
                        style: context.texts.labelSmall,
                      ),
                    ),
                    if (conflict.protected)
                      const StatusChip('Protected', tone: ChipTone.rose),
                  ],
                ),
              ),
          ],
          if (data.requiresApproval) ...[
            const SizedBox(height: 8),
            Text(
              'Group approval is required before this touches the confirmed plan.',
              style: context.texts.labelSmall?.copyWith(
                color: palette.ember,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _VotePill extends StatelessWidget {
  const _VotePill({
    required this.label,
    required this.count,
    required this.color,
  });

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        '$label $count',
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
