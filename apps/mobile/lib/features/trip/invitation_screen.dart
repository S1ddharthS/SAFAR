import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/invitation.dart';
import '../../core/network/api_exception.dart';
import '../../core/providers.dart';
import '../../core/theme/safar_theme.dart';
import '../../core/widgets/safar_widgets.dart';

class InvitationScreen extends ConsumerStatefulWidget {
  const InvitationScreen({super.key, required this.token});

  final String token;

  @override
  ConsumerState<InvitationScreen> createState() => _InvitationScreenState();
}

class _InvitationScreenState extends ConsumerState<InvitationScreen> {
  bool _busy = false;

  Future<void> _accept() async {
    setState(() => _busy = true);
    try {
      final trip = await ref
          .read(tripRepositoryProvider)
          .acceptInvitation(widget.token);
      ref.invalidate(tripsProvider);
      ref.invalidate(membersProvider(trip.id));
      ref.invalidate(invitationPreviewProvider(widget.token));
      if (!mounted) return;
      context.go('/trips/${trip.id}');
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
      ref.invalidate(invitationPreviewProvider(widget.token));
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('The invitation was not accepted. $error')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = ref.watch(invitationPreviewProvider(widget.token));
    return Scaffold(
      appBar: AppBar(title: const Text('Trip invitation')),
      body: preview.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(20),
          child: SkeletonList(count: 3, itemHeight: 88),
        ),
        error: (error, stack) => Padding(
          padding: const EdgeInsets.all(20),
          child: SafarEmpty(
            icon: Icons.mark_email_unread_outlined,
            title: 'This invitation cannot be opened',
            message: error is ApiException
                ? error.message
                : 'Check your connection and try again.',
            action: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FilledButton(
                  onPressed: () =>
                      ref.invalidate(invitationPreviewProvider(widget.token)),
                  child: const Text('Try again'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => context.go('/dashboard'),
                  child: const Text('Back to dashboard'),
                ),
              ],
            ),
          ),
        ),
        data: (preview) => _InvitationBody(
          preview: preview,
          busy: _busy,
          onAccept: _accept,
        ),
      ),
    );
  }
}

class _InvitationBody extends StatelessWidget {
  const _InvitationBody({
    required this.preview,
    required this.busy,
    required this.onAccept,
  });

  final InvitationPreview preview;
  final bool busy;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    final dates = preview.startDate != null && preview.endDate != null
        ? '${preview.startDate} → ${preview.endDate}'
        : null;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
      children: [
        const Eyebrow('Private by default · group approved'),
        const SizedBox(height: 8),
        Text(preview.tripName, style: context.texts.displaySmall),
        if (preview.destinationName != null) ...[
          const SizedBox(height: 6),
          Text(preview.destinationName!, style: context.texts.titleMedium),
        ],
        if (dates != null) ...[
          const SizedBox(height: 4),
          Text(dates, style: context.texts.bodySmall),
        ],
        const SizedBox(height: 16),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            StatusChip(
              preview.role == 'admin' ? 'Admin' : 'Member',
              tone: ChipTone.ember,
            ),
            StatusChip(switch (preview.scope) {
              'vote' => 'Vote only',
              'pulse' => 'Trip Pulse',
              'view' => 'View only',
              _ => 'Full plan',
            }),
            if (preview.emailBound)
              const StatusChip('Email bound', icon: Icons.alternate_email),
          ],
        ),
        const SizedBox(height: 18),
        if (preview.invitedBy != null)
          Text('Invited by ${preview.invitedBy}', style: context.texts.bodySmall),
        if (preview.expiresAt != null)
          Text(
            'Link expires ${preview.expiresAt!.split('T').first}',
            style: context.texts.bodySmall,
          ),
        const SizedBox(height: 24),
        if (preview.alreadyMember)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const InfoBanner(
                text: 'You are already part of this trip. Everything below is '
                    'shared with the group.',
                icon: Icons.check_circle_outline,
                tone: ChipTone.jade,
              ),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: () => context.go('/trips/${preview.tripId}'),
                child: const Text('Open trip'),
              ),
            ],
          )
        else if (preview.accepted)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const InfoBanner(
                text: 'This invitation has already been used. Ask a trip admin '
                    'for a new single-use link.',
                icon: Icons.link_off_rounded,
              ),
              const SizedBox(height: 14),
              OutlinedButton(
                onPressed: () => context.go('/dashboard'),
                child: const Text('Back to dashboard'),
              ),
            ],
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton(
                onPressed: busy ? null : onAccept,
                child: Text(busy ? 'Joining…' : 'Join ${preview.tripName}'),
              ),
              const SizedBox(height: 10),
              const InfoBanner(
                text: 'Joining shares the group plan with you. Your private '
                    'preferences and budget stay yours.',
                icon: Icons.lock_outline,
              ),
            ],
          ),
      ],
    );
  }
}
