import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/monitoring.dart';
import '../../core/providers.dart';
import '../../core/theme/safar_theme.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/safar_widgets.dart';

const _optionLabels = {
  'yes': 'Yes, I support it',
  'no': 'No',
  'abstain': 'Abstain',
  'in': "I'll be there",
  'out': "I can't make it",
  'join_later': "I'll join later",
};

/// Public answer page reached through `/companion/{token}`. It intentionally
/// does not require an account: the token is the only credential.
class CompanionPublicScreen extends ConsumerStatefulWidget {
  const CompanionPublicScreen({super.key, required this.token});

  final String token;

  @override
  ConsumerState<CompanionPublicScreen> createState() =>
      _CompanionPublicScreenState();
}

class _CompanionPublicScreenState extends ConsumerState<CompanionPublicScreen> {
  late Future<CompanionContext> _future;
  final _comment = TextEditingController();
  String? _choice;
  bool _sending = false;
  String? _success;
  String? _error;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<CompanionContext> _load() =>
      ref.read(companionRepositoryProvider).publicView(widget.token);

  void _retry() {
    setState(() {
      _error = null;
      _success = null;
      _future = _load();
    });
  }

  Future<void> _submit() async {
    final choice = _choice;
    if (choice == null || _sending) return;
    final comment = _comment.text.trim();
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(companionRepositoryProvider)
          .respondPublic(
            widget.token,
            value: choice,
            comment: comment.isEmpty ? null : comment,
          );
      if (!mounted) return;
      setState(() {
        _success = result['message'] is String
            ? result['message'] as String
            : 'Thank you — your answer was recorded without an account.';
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.safar;
    return Scaffold(
      backgroundColor: palette.paper,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: FutureBuilder<CompanionContext>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
                    children: [
                      const _BrandRow(),
                      const SizedBox(height: 32),
                      SafarCard(
                        child: Column(
                          children: [
                            Icon(
                              Icons.link_off_rounded,
                              size: 34,
                              color: palette.ember,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'This link cannot be used',
                              textAlign: TextAlign.center,
                              style: context.texts.titleLarge,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${snapshot.error}. Links are single-use and '
                              'expire, so ask the trip organiser for a fresh one.',
                              textAlign: TextAlign.center,
                              style: context.texts.bodySmall,
                            ),
                            const SizedBox(height: 16),
                            FilledButton.tonal(
                              onPressed: _retry,
                              child: const Text('Try again'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                }
                final data = snapshot.data!;
                if (_success != null) {
                  return _SuccessView(message: _success!, disclosure: data.disclosure);
                }
                return _AnswerView(
                  data: data,
                  choice: _choice,
                  comment: _comment,
                  error: _error,
                  sending: _sending,
                  onChoose: (value) => setState(() => _choice = value),
                  onSubmit: _submit,
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _BrandRow extends StatelessWidget {
  const _BrandRow();

  @override
  Widget build(BuildContext context) {
    final palette = context.safar;
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: palette.ink,
            shape: BoxShape.circle,
          ),
          child: Text(
            'S',
            style: context.texts.titleSmall?.copyWith(color: palette.paper),
          ),
        ),
        const SizedBox(width: 10),
        Text('SAFAR', style: context.texts.titleSmall),
        const Spacer(),
        const StatusChip(
          'No account needed',
          tone: ChipTone.jade,
          icon: Icons.lock_outline,
        ),
      ],
    );
  }
}

class _AnswerView extends StatelessWidget {
  const _AnswerView({
    required this.data,
    required this.choice,
    required this.comment,
    required this.error,
    required this.sending,
    required this.onChoose,
    required this.onSubmit,
  });

  final CompanionContext data;
  final String? choice;
  final TextEditingController comment;
  final String? error;
  final bool sending;
  final ValueChanged<String> onChoose;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final palette = context.safar;
    final target = data.target;
    final meta = [
      if (target.day != null) formatDate(target.day),
      if (target.startTime != null) formatClock(target.startTime),
    ].where((part) => part.isNotEmpty).join(' · ');

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        const _BrandRow(),
        const SizedBox(height: 20),
        SafarCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  StatusChip(
                    data.purpose == 'vote' ? 'One decision' : 'One check-in',
                    tone: data.purpose == 'vote'
                        ? ChipTone.ember
                        : ChipTone.jade,
                  ),
                  Text(data.tripName, style: context.texts.labelSmall),
                ],
              ),
              if (data.destinationName.isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.place_outlined, size: 13, color: palette.faint),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        data.destinationName,
                        style: context.texts.labelSmall,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              Text(target.title, style: context.texts.headlineSmall),
              if (target.summary != null && target.summary!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  target.summary!,
                  style: context.texts.bodySmall?.copyWith(height: 1.5),
                ),
              ],
              if (meta.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(meta, style: context.texts.labelSmall),
              ],
              if (target.registeredVotes.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final entry in target.registeredVotes.entries)
                      StatusChip(
                        '${titleCase(entry.key)} · ${entry.value}',
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        SafarCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(data.question, style: context.texts.titleSmall),
              const SizedBox(height: 12),
              for (final option in data.options)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _OptionTile(
                    label: _optionLabels[option] ?? titleCase(option),
                    selected: choice == option,
                    onTap: () => onChoose(option),
                  ),
                ),
              const SizedBox(height: 6),
              TextField(
                controller: comment,
                maxLines: 3,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: 'Optional note',
                  hintText:
                      'Visible anonymously to the person who shared the link.',
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 4),
                Text(
                  error!,
                  style: context.texts.bodySmall?.copyWith(color: palette.rose),
                ),
              ],
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: choice == null || sending ? null : onSubmit,
                  icon: sending
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_outlined, size: 18),
                  label: Text(sending ? 'Sending…' : 'Send my answer'),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'This link can be answered once. Your name, email, IP address '
                'and device are not recorded.',
                style: context.texts.labelSmall,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.shield_outlined, size: 15, color: palette.jade),
            const SizedBox(width: 8),
            Expanded(
              child: Text(data.disclosure, style: context.texts.labelSmall),
            ),
          ],
        ),
      ],
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.safar;
    return SafarCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      radius: 16,
      onTap: onTap,
      color: selected ? palette.ink : null,
      borderColor: selected ? palette.ink : null,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: context.texts.bodyMedium?.copyWith(
                color: selected ? palette.paper : palette.ink,
              ),
            ),
          ),
          if (selected)
            Icon(Icons.check_circle, size: 18, color: palette.paper),
        ],
      ),
    );
  }
}

class _SuccessView extends StatelessWidget {
  const _SuccessView({required this.message, required this.disclosure});

  final String message;
  final String disclosure;

  @override
  Widget build(BuildContext context) {
    final palette = context.safar;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        const _BrandRow(),
        const SizedBox(height: 32),
        SafarCard(
          child: Column(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: palette.jadeSoft,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.check, size: 26, color: palette.jade),
              ),
              const SizedBox(height: 14),
              Text(
                'Answer recorded',
                textAlign: TextAlign.center,
                style: context.texts.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: context.texts.bodySmall,
              ),
              const SizedBox(height: 10),
              Text(
                'You can close this page. Nothing about you was stored with '
                'the answer.',
                textAlign: TextAlign.center,
                style: context.texts.labelSmall,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(disclosure, style: context.texts.labelSmall),
      ],
    );
  }
}
