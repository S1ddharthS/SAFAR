import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/social.dart';
import '../../core/providers.dart';
import '../../core/theme/safar_theme.dart';
import '../../core/widgets/safar_widgets.dart';

class ContributorsScreen extends ConsumerStatefulWidget {
  const ContributorsScreen({super.key, required this.tripId});

  final String tripId;

  @override
  ConsumerState<ContributorsScreen> createState() => _ContributorsScreenState();
}

class _ContributorsScreenState extends ConsumerState<ContributorsScreen> {
  bool _busy = false;

  Future<void> _register(String destinationName) async {
    final trip = ref.read(tripProvider(widget.tripId)).valueOrNull;
    final destinationId = trip?.destinationId;
    if (destinationId == null) {
      _snack('Set a destination for this trip before registering.');
      return;
    }
    final bio = TextEditingController();
    final expertise = TextEditingController();
    var acceptsRequests = true;
    final submitted = await showSafarSheet<bool>(
      context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SafarSheetHeader(
                title: 'Become a local contributor',
                subtitle:
                    'Opt in to answer ground questions about $destinationName. '
                    'Your answers are attributed and never presented as '
                    'verified facts.',
              ),
              TextField(
                controller: bio,
                maxLines: 2,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: 'Short bio (optional)',
                  hintText: 'I live near the old town and visit weekly.',
                ),
              ),
              TextField(
                controller: expertise,
                decoration: const InputDecoration(
                  labelText: 'Expertise (comma separated)',
                  hintText: 'markets, transport, step-free access',
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Accept ground requests'),
                subtitle: const Text(
                  'Turn off to keep your profile visible without answering '
                  'questions.',
                ),
                value: acceptsRequests,
                onChanged: (value) =>
                    setSheetState(() => acceptsRequests = value),
              ),
              const SizedBox(height: 8),
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
                      child: const Text('Register'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    final bioText = bio.text.trim();
    final expertiseText = expertise.text.trim();
    bio.dispose();
    expertise.dispose();
    if (submitted != true) return;
    setState(() => _busy = true);
    try {
      final result = await ref
          .read(discoveryRepositoryProvider)
          .upsertContributor(
            destinationId: destinationId,
            bio: bioText.isEmpty ? null : bioText,
            expertise: expertiseText.isEmpty
                ? const []
                : expertiseText
                    .split(',')
                    .map((entry) => entry.trim())
                    .where((entry) => entry.isNotEmpty)
                    .toList(),
            acceptsRequests: acceptsRequests,
          );
      ref.invalidate(contributorsProvider);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Contribution profile saved'),
          content: Text(
            result.note.isEmpty
                ? 'You can now answer ground requests for this destination.'
                : result.note,
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      );
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
    final trip = ref.watch(tripProvider(widget.tripId)).valueOrNull;
    final destinationName = trip?.destinationName ?? 'this destination';
    return Scaffold(
      appBar: AppBar(title: const Text('Local contributors')),
      body: AsyncView<List<Contributor>>(
        value: ref.watch(contributorsProvider),
        onRetry: () => ref.invalidate(contributorsProvider),
        skeleton: const SkeletonList(count: 3, itemHeight: 84),
        builder: (contributors) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 36),
          children: [
            const InfoBanner(
              text:
                  'Local contributors answer ground questions. They are '
                  'community members, not official guides, and their answers '
                  'are always attributed observations.',
              icon: Icons.people_outline_rounded,
            ),
            const SizedBox(height: 14),
            FilledButton.tonalIcon(
              onPressed: _busy ? null : () => _register(destinationName),
              icon: const Icon(Icons.person_add_alt_outlined, size: 18),
              label: Text('Become a contributor for $destinationName'),
            ),
            const SizedBox(height: 20),
            SectionHeader(
              eyebrow: 'Community',
              title: contributors.isEmpty
                  ? 'No contributors yet'
                  : 'People who know the ground',
            ),
            if (contributors.isEmpty)
              const SafarEmpty(
                icon: Icons.people_outline_rounded,
                title: 'Be the first',
                message:
                    'Register as a local contributor to help travellers with '
                    'real, recent observations.',
              )
            else
              for (final contributor in contributors)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SafarCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            SafarAvatar(
                              name: contributor.user?.displayName ??
                                  'A local',
                              size: 36,
                              imageUrl: contributor.user?.avatarUrl,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          contributor.user?.displayName ??
                                              'A local',
                                          style: context.texts.titleSmall,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (contributor.verified) ...[
                                        const SizedBox(width: 6),
                                        Icon(
                                          Icons.verified_outlined,
                                          size: 15,
                                          color: palette.jade,
                                        ),
                                      ],
                                    ],
                                  ),
                                  if (contributor.destination != null)
                                    Text(
                                      contributor.destination!.name,
                                      style: context.texts.labelSmall,
                                    ),
                                ],
                              ),
                            ),
                            StatusChip(
                              contributor.acceptsRequests
                                  ? 'Accepts questions'
                                  : 'Not accepting',
                              tone: contributor.acceptsRequests
                                  ? ChipTone.jade
                                  : ChipTone.neutral,
                            ),
                          ],
                        ),
                        if (contributor.bio != null &&
                            contributor.bio!.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            contributor.bio!,
                            style: context.texts.bodySmall,
                          ),
                        ],
                        if (contributor.expertise.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final skill in contributor.expertise.take(5))
                                StatusChip(skill),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
