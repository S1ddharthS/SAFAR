import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/social.dart';
import '../../core/providers.dart';
import '../../core/theme/safar_theme.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/safar_widgets.dart';

Future<bool> _confirmLeaveCircle(BuildContext context, String name) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Leave $name?'),
      content: const Text(
        'You will stop seeing this circle\'s posts. You can join again later.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Stay'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Leave'),
        ),
      ],
    ),
  );
  return confirmed == true;
}

class CirclesScreen extends ConsumerStatefulWidget {
  const CirclesScreen({super.key, required this.tripId});

  final String tripId;

  @override
  ConsumerState<CirclesScreen> createState() => _CirclesScreenState();
}

class _CirclesScreenState extends ConsumerState<CirclesScreen> {
  bool _busy = false;

  Future<void> _toggle(Circle circle) async {
    if (circle.joined) {
      final confirmed = await _confirmLeaveCircle(context, circle.name);
      if (!confirmed || !mounted) return;
    }
    setState(() => _busy = true);
    try {
      final repository = ref.read(discoveryRepositoryProvider);
      if (circle.joined) {
        await repository.leaveCircle(circle.id);
      } else {
        await repository.joinCircle(circle.id);
      }
      ref.invalidate(circlesProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            circle.joined
                ? 'Left ${circle.name}.'
                : 'Joined ${circle.name}.',
          ),
        ),
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
    return Scaffold(
      appBar: AppBar(title: const Text('Travel circles')),
      body: AsyncView<List<Circle>>(
        value: ref.watch(circlesProvider),
        onRetry: () => ref.invalidate(circlesProvider),
        skeleton: const SkeletonList(count: 3, itemHeight: 92),
        builder: (circles) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 36),
          children: [
            const InfoBanner(
              text:
                  'Circles are interest communities, separate from your trip. '
                  'Join to read and post; your trip stays private.',
              icon: Icons.groups_outlined,
            ),
            const SizedBox(height: 16),
            if (circles.isEmpty)
              const SafarEmpty(
                icon: Icons.groups_outlined,
                title: 'No circles yet',
                message: 'Interest circles appear here as they are created.',
              )
            else
              for (final circle in circles)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SafarCard(
                    onTap: () => context.push(
                      '/trips/${widget.tripId}/circles/${circle.id}',
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                circle.name,
                                style: context.texts.titleSmall,
                              ),
                            ),
                            if (circle.joined)
                              const StatusChip('Joined', tone: ChipTone.jade),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(circle.description, style: context.texts.bodySmall),
                        if (circle.interests.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final interest in circle.interests.take(4))
                                StatusChip(interest),
                            ],
                          ),
                        ],
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              '${circle.memberCount} member'
                              '${circle.memberCount == 1 ? '' : 's'}',
                              style: context.texts.labelSmall,
                            ),
                            TextButton(
                              onPressed: _busy ? null : () => _toggle(circle),
                              child: Text(
                                circle.joined ? 'Leave' : 'Join',
                              ),
                            ),
                          ],
                        ),
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

class CircleDetailScreen extends ConsumerStatefulWidget {
  const CircleDetailScreen({
    super.key,
    required this.tripId,
    required this.circleId,
  });

  final String tripId;
  final String circleId;

  @override
  ConsumerState<CircleDetailScreen> createState() => _CircleDetailScreenState();
}

class _CircleDetailScreenState extends ConsumerState<CircleDetailScreen> {
  bool _busy = false;

  Future<void> _toggle(CircleDetail circle) async {
    if (circle.joined) {
      final confirmed = await _confirmLeaveCircle(context, circle.name);
      if (!confirmed || !mounted) return;
    }
    setState(() => _busy = true);
    try {
      final repository = ref.read(discoveryRepositoryProvider);
      if (circle.joined) {
        await repository.leaveCircle(circle.id);
      } else {
        await repository.joinCircle(circle.id);
      }
      ref.invalidate(circleProvider(widget.circleId));
      ref.invalidate(circlesProvider);
    } on Object catch (error) {
      _snack(error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _post(CircleDetail circle) async {
    final title = TextEditingController();
    final body = TextEditingController();
    final submitted = await showSafarSheet<bool>(
      context,
      builder: (sheetContext) => SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SafarSheetHeader(
              title: 'Post to ${circle.name}',
              subtitle:
                  'Posts are public to circle members. Do not share private '
                  'trip details, budgets or member preferences.',
            ),
            TextField(
              controller: title,
              maxLength: 160,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            TextField(
              controller: body,
              maxLines: 5,
              maxLength: 4000,
              decoration: const InputDecoration(labelText: 'Body'),
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
                    child: const Text('Post'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    final postTitle = title.text.trim();
    final postBody = body.text.trim();
    title.dispose();
    body.dispose();
    if (submitted != true) return;
    if (postTitle.length < 2 || postBody.length < 2) {
      _snack('A post needs a title and a body.');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(discoveryRepositoryProvider).postToCircle(
            circle.id,
            title: postTitle,
            body: postBody,
          );
      ref.invalidate(circleProvider(widget.circleId));
      _snack('Posted to ${circle.name}.');
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
    return Scaffold(
      appBar: AppBar(title: const Text('Circle')),
      body: AsyncView<CircleDetail>(
        value: ref.watch(circleProvider(widget.circleId)),
        onRetry: () => ref.invalidate(circleProvider(widget.circleId)),
        skeleton: const SkeletonList(count: 3, itemHeight: 88),
        builder: (circle) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 36),
          children: [
            Text(circle.name, style: context.texts.displaySmall),
            const SizedBox(height: 6),
            Text(circle.description, style: context.texts.bodySmall),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                StatusChip('${circle.memberCount} members'),
                for (final interest in circle.interests) StatusChip(interest),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: circle.joined
                      ? OutlinedButton(
                          onPressed: _busy ? null : () => _toggle(circle),
                          child: const Text('Leave circle'),
                        )
                      : FilledButton(
                          onPressed: _busy ? null : () => _toggle(circle),
                          child: const Text('Join to post'),
                        ),
                ),
                if (circle.joined) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: _busy ? null : () => _post(circle),
                      icon: const Icon(Icons.edit_outlined, size: 17),
                      label: const Text('New post'),
                    ),
                  ),
                ],
              ],
            ),
            if (!circle.joined) ...[
              const SizedBox(height: 10),
              const InfoBanner(
                text: 'Join this circle to read discussions and publish a post.',
                icon: Icons.lock_outline,
              ),
            ],
            const SizedBox(height: 20),
            SectionHeader(
              eyebrow: 'Discussion',
              title: circle.posts.isEmpty ? 'No posts yet' : 'Latest posts',
            ),
            if (circle.posts.isEmpty)
              const SafarEmpty(
                icon: Icons.forum_outlined,
                title: 'Start the conversation',
                message:
                    'Share an idea, a question or a small discovery with the '
                    'circle.',
              )
            else
              for (final post in circle.posts)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SafarCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(post.title, style: context.texts.titleSmall),
                        const SizedBox(height: 4),
                        Text(post.body, style: context.texts.bodySmall),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Text(
                              post.author?.displayName ?? 'A traveller',
                              style: context.texts.labelSmall,
                            ),
                            const SizedBox(width: 6),
                            const Icon(Icons.circle, size: 4),
                            const SizedBox(width: 6),
                            Text(
                              timeAgo(post.createdAt),
                              style: context.texts.labelSmall,
                            ),
                            const Spacer(),
                            if (post.activityId != null)
                              Icon(
                                Icons.place_outlined,
                                size: 14,
                                color: palette.faint,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            if (circle.members.isNotEmpty) ...[
              const SizedBox(height: 18),
              const Eyebrow('Members'),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final member in circle.members)
                    StatusChip(member.displayName),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
