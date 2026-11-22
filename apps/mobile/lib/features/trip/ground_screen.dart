import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/monitoring.dart';
import '../../core/providers.dart';
import '../../core/theme/safar_theme.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/safar_widgets.dart';

class GroundScreen extends ConsumerStatefulWidget {
  const GroundScreen({super.key, required this.tripId});

  final String tripId;

  @override
  ConsumerState<GroundScreen> createState() => _GroundScreenState();
}

class _GroundScreenState extends ConsumerState<GroundScreen> {
  bool _busy = false;

  Future<void> _ask() async {
    final question = TextEditingController();
    final submitted = await showSafarSheet<bool>(
      context,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SafarSheetHeader(
            title: 'Ask someone on the ground',
            subtitle:
                'Opted-in local contributors for this destination can answer. '
                'Answers are attributed observations, never verified facts.',
          ),
          TextField(
            controller: question,
            maxLines: 3,
            maxLength: 1000,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Your question',
              hintText: 'Is the west entrance open in the evening?',
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
                  child: const Text('Send question'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    final text = question.text.trim();
    question.dispose();
    if (submitted != true) return;
    if (text.length < 5) {
      _snack('Ask a slightly more specific question.');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(tripRepositoryProvider)
          .createGroundRequest(widget.tripId, question: text);
      ref.invalidate(groundRequestsProvider(widget.tripId));
      _snack('Question sent to local contributors.');
    } on Object catch (error) {
      _snack(error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _respond(GroundRequestItem request) async {
    final observation = TextEditingController();
    var confidence = 0.6;
    final submitted = await showSafarSheet<bool>(
      context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SafarSheetHeader(
              title: 'Share what you observed',
              subtitle:
                  'Only opted-in local contributors can answer. Keep it '
                  'factual and recent.',
            ),
            TextField(
              controller: observation,
              maxLines: 3,
              maxLength: 2000,
              decoration: const InputDecoration(
                labelText: 'Observation',
                hintText: 'The west entrance closes at 19:00 in November.',
              ),
            ),
            const SizedBox(height: 8),
            Text('How sure are you?', style: context.texts.labelMedium),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                for (final (value, label) in const [
                  (0.3, 'Low'),
                  (0.6, 'Medium'),
                  (0.9, 'High'),
                ])
                  ChoiceChip(
                    label: Text(label),
                    selected: confidence == value,
                    onSelected: (_) =>
                        setSheetState(() => confidence = value),
                  ),
              ],
            ),
            const SizedBox(height: 14),
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
                    child: const Text('Share'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    final text = observation.text.trim();
    observation.dispose();
    if (submitted != true) return;
    if (text.length < 5) {
      _snack('Describe the observation in a few words.');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(tripRepositoryProvider)
          .respondToGroundRequest(
            widget.tripId,
            request.id,
            observation: text,
            confidence: confidence,
          );
      ref.invalidate(groundRequestsProvider(widget.tripId));
      _snack('Observation shared with this trip.');
    } on Object catch (error) {
      _snack(
        'Could not respond: ${error.toString()}\n'
        'Only opted-in local contributors for this destination can answer.',
      );
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
    final requests = ref.watch(groundRequestsProvider(widget.tripId));
    final itinerary = ref.watch(itineraryProvider(widget.tripId)).valueOrNull;
    final activityTitles = {
      for (final item in itinerary?.items ?? const [])
        if (item.activityId != null) item.activityId!: item.title,
    };
    return Scaffold(
      appBar: AppBar(title: const Text('Ground requests')),
      body: AsyncView<List<GroundRequestItem>>(
        value: requests,
        onRetry: () => ref.invalidate(groundRequestsProvider(widget.tripId)),
        skeleton: const SkeletonList(count: 2, itemHeight: 96),
        builder: (items) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 36),
          children: [
            const InfoBanner(
              text:
                  'Ground questions go to opted-in local contributors. Answers '
                  'are attributed observations, clearly separate from verified '
                  'catalog facts.',
              icon: Icons.terrain_outlined,
            ),
            const SizedBox(height: 16),
            SectionHeader(
              eyebrow: 'Local intel',
              title: items.isEmpty ? 'No questions yet' : 'Open questions',
            ),
            if (items.isEmpty)
              SafarEmpty(
                icon: Icons.question_answer_outlined,
                title: 'Ask what the catalog cannot tell you',
                message:
                    'Opening quirks, queues and access details — ask someone '
                    'on the ground. Answers never replace verified facts.',
                action: FilledButton.icon(
                  onPressed: _busy ? null : _ask,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Ask a question'),
                ),
              )
            else ...[
              for (final request in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SafarCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                request.question,
                                style: context.texts.titleSmall,
                              ),
                            ),
                            StatusChip(
                              request.status,
                              tone: request.status == 'open'
                                  ? ChipTone.ember
                                  : ChipTone.jade,
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          [
                            'Asked ${timeAgo(request.createdAt)}',
                            if (request.activityId != null &&
                                activityTitles[request.activityId] != null)
                              'about ${activityTitles[request.activityId]}',
                          ].join(' · '),
                          style: context.texts.labelSmall,
                        ),
                        if (request.responses.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Text(
                              'No answers yet. A local contributor may pick '
                              'this up.',
                              style: context.texts.bodySmall,
                            ),
                          )
                        else ...[
                          const SizedBox(height: 10),
                          for (final response in request.responses)
                            Container(
                              width: double.infinity,
                              margin: const EdgeInsets.only(bottom: 6),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: palette.raised,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    response.observation,
                                    style: context.texts.bodySmall,
                                  ),
                                  const SizedBox(height: 6),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      StatusChip(
                                        response.provenance,
                                        tone: response.verified
                                            ? ChipTone.jade
                                            : ChipTone.neutral,
                                      ),
                                      Text(
                                        '${(response.confidence * 100).round()}% confidence',
                                        style: context.texts.labelSmall,
                                      ),
                                      Text(
                                        timeAgo(response.observedAt),
                                        style: context.texts.labelSmall,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                        ],
                        const SizedBox(height: 6),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: _busy ? null : () => _respond(request),
                            icon: const Icon(
                              Icons.record_voice_over_outlined,
                              size: 17,
                            ),
                            label: const Text('I can answer'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 6),
              OutlinedButton.icon(
                onPressed: _busy ? null : _ask,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Ask a question'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
