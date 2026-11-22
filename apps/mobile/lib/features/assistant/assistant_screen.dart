import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/assistant.dart';
import '../../core/network/api_exception.dart';
import '../../core/providers.dart';
import '../../core/theme/safar_theme.dart';
import '../../core/widgets/safar_widgets.dart';

class AssistantScreen extends ConsumerStatefulWidget {
  const AssistantScreen({super.key, this.tripId, this.tripName});

  final String? tripId;
  final String? tripName;

  @override
  ConsumerState<AssistantScreen> createState() => _AssistantScreenState();
}

sealed class _Entry {
  const _Entry();
}

class _UserEntry extends _Entry {
  const _UserEntry(this.text);

  final String text;
}

class _AnswerEntry extends _Entry {
  const _AnswerEntry(this.answer);

  final AssistantAnswer answer;
}

class _AssistantScreenState extends ConsumerState<AssistantScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<_Entry> _entries = [];
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty || _busy) return;
    setState(() {
      _entries.add(_UserEntry(text));
      _busy = true;
      _error = null;
    });
    _input.clear();
    _scrollToEnd();
    try {
      final repo = ref.read(assistantRepositoryProvider);
      final answer = widget.tripId == null
          ? await repo.chat(message: text)
          : await repo.tripChat(widget.tripId!, message: text);
      if (!mounted) return;
      setState(() => _entries.add(_AnswerEntry(answer)));
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _scrollToEnd();
      }
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent + 200,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _openAction(SuggestedAction action) {
    final href = action.href;
    if (href != null && href.startsWith('/')) {
      context.push(href);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${action.label} is not available in this view.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.safar;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Ask SAFAR'),
            Text(
              widget.tripName == null
                  ? 'Grounded in SAFAR data'
                  : 'Trip context · ${widget.tripName}',
              style: context.texts.labelSmall,
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Clear conversation',
            onPressed: _entries.isEmpty
                ? null
                : () => setState(() => _entries.clear()),
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                children: [
                  if (_entries.isEmpty) _IntroCard(tripName: widget.tripName, onAsk: _send),
                  for (final entry in _entries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: switch (entry) {
                        _UserEntry(:final text) => _UserBubble(text: text),
                        _AnswerEntry(:final answer) => _AnswerView(
                          answer: answer,
                          onAction: _openAction,
                        ),
                      },
                    ),
                  if (_busy)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: SafarCard(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        radius: 18,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'Reading the trip…',
                              style: context.texts.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (_error != null)
                    InfoBanner(text: _error!, tone: ChipTone.rose),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              decoration: BoxDecoration(
                color: palette.surface,
                border: Border(top: BorderSide(color: palette.line)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        hintText: 'Ask about this trip…',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: 'Send',
                    onPressed: _busy ? null : () => _send(),
                    icon: const Icon(Icons.arrow_upward, size: 20),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IntroCard extends StatelessWidget {
  const _IntroCard({required this.tripName, required this.onAsk});

  final String? tripName;
  final ValueChanged<String> onAsk;

  @override
  Widget build(BuildContext context) {
    final suggestions = tripName == null
        ? const [
            'What can SAFAR help me with?',
            'How does the Group Experience Engine work?',
            'How is my Journey DNA used?',
          ]
        : [
            'What should we do tomorrow in $tripName?',
            'Summarise the open votes',
            'What does the plan cost so far?',
            'Which activities are protected in the itinerary?',
          ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Eyebrow('Travel assistant'),
        const SizedBox(height: 8),
        Text(
          tripName == null
              ? 'Answers with receipts.'
              : 'Ask about $tripName.',
          style: context.texts.headlineLarge,
        ),
        const SizedBox(height: 8),
        Text(
          'SAFAR answers from your trips, the catalog and approved group decisions. '
          'It labels sources, estimates and limits, and never invents travel facts.',
          style: context.texts.bodySmall?.copyWith(height: 1.5),
        ),
        const SizedBox(height: 16),
        const InfoBanner(
          icon: Icons.verified_outlined,
          tone: ChipTone.jade,
          text:
              'Answers are grounded in SAFAR records. Estimates and community reports remain '
              'labelled and are never presented as verified facts.',
        ),
        const SizedBox(height: 18),
        const Eyebrow('Try asking'),
        const SizedBox(height: 8),
        for (final suggestion in suggestions)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SafarCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              radius: 16,
              onTap: () => onAsk(suggestion),
              child: Row(
                children: [
                  Icon(
                    Icons.chat_bubble_outline,
                    size: 16,
                    color: context.safar.ember,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(suggestion, style: context.texts.bodyMedium),
                  ),
                  Icon(
                    Icons.arrow_outward,
                    size: 15,
                    color: context.safar.faint,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.safar;
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: palette.ink,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
              bottomLeft: Radius.circular(20),
              bottomRight: Radius.circular(6),
            ),
          ),
          child: Text(
            text,
            style: context.texts.bodyMedium?.copyWith(color: palette.surface),
          ),
        ),
      ),
    );
  }
}

class _AnswerView extends StatelessWidget {
  const _AnswerView({required this.answer, required this.onAction});

  final AssistantAnswer answer;
  final ValueChanged<SuggestedAction> onAction;

  @override
  Widget build(BuildContext context) {
    final palette = context.safar;
    final language = answer.language;
    final contextInfo = answer.context;
    return SafarCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: palette.emberSoft,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  Icons.auto_awesome,
                  size: 15,
                  color: palette.ember,
                ),
              ),
              const SizedBox(width: 9),
              const Expanded(child: Eyebrow('SAFAR')),
              SourceLabel(
                source: answer.grounding,
                confidence: language == null
                    ? null
                    : '${language.name}${language.source == 'user' ? ' · chosen' : ''}',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            answer.answer,
            style: context.texts.bodyMedium?.copyWith(height: 1.55),
          ),
          if (answer.requiresApproval) ...[
            const SizedBox(height: 12),
            const InfoBanner(
              tone: ChipTone.ember,
              icon: Icons.how_to_vote_outlined,
              text:
                  'This answer suggests a change. Nothing is applied until the group votes and approves it.',
            ),
          ],
          if (answer.citations.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Eyebrow('Sources'),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final citation in answer.citations)
                  Tooltip(
                    message: [
                      citation.type,
                      if (citation.provenance != null) citation.provenance!,
                    ].join(' · '),
                    child: StatusChip(
                      citation.label,
                      tone: ChipTone.neutral,
                      icon: Icons.article_outlined,
                    ),
                  ),
              ],
            ),
          ],
          if (answer.limitations.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final limitation in answer.limitations)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 13, color: palette.faint),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(limitation, style: context.texts.labelSmall),
                    ),
                  ],
                ),
              ),
          ],
          if (contextInfo != null &&
              (contextInfo.destination != null ||
                  contextInfo.missing.isNotEmpty)) ...[
            const SizedBox(height: 10),
            Text(
              [
                if (contextInfo.destination != null) contextInfo.destination!,
                if (contextInfo.startDate.isNotEmpty)
                  '${contextInfo.startDate} → ${contextInfo.endDate}',
                if (contextInfo.groupSize > 0)
                  '${contextInfo.groupSize} travellers',
                if (contextInfo.missing.isNotEmpty)
                  'missing: ${contextInfo.missing.join(', ')}',
              ].join(' · '),
              style: context.texts.labelSmall,
            ),
          ],
          if (answer.mutation != 'none') ...[
            const SizedBox(height: 6),
            Text(
              'Requested change: ${answer.mutation.replaceAll('_', ' ')}',
              style: context.texts.labelSmall,
            ),
          ],
          if (answer.suggestedActions.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final action in answer.suggestedActions)
                  OutlinedButton(
                    onPressed: () => onAction(action),
                    child: Text(action.label),
                  ),
              ],
            ),
          ],
          if (answer.attribution != null || answer.generatedBy != null) ...[
            const SizedBox(height: 10),
            SourceLabel(
              source: answer.generatedBy ?? answer.attribution,
              confidence: answer.attribution,
            ),
          ],
        ],
      ),
    );
  }
}
