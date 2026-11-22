import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/common.dart';
import '../../core/network/api_exception.dart';
import '../../core/providers.dart';
import '../../core/theme/safar_theme.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/safar_widgets.dart';
import '../auth/auth_controller.dart';

class JourneyDnaScreen extends ConsumerWidget {
  const JourneyDnaScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Journey DNA')),
      body: SafeArea(
        top: false,
        child: AsyncView(
          value: me,
          onRetry: () => ref.invalidate(meProvider),
          builder: (data) => _DnaEditor(
            key: ValueKey('${data.dna.updatedAt}-${data.dna.scores.hashCode}'),
            dna: data.dna,
            onSaved: () {
              ref.invalidate(meProvider);
              ref.read(authControllerProvider.notifier).reload();
            },
          ),
        ),
      ),
    );
  }
}

class _DnaEditor extends ConsumerStatefulWidget {
  const _DnaEditor({super.key, required this.dna, required this.onSaved});

  final Dna dna;
  final VoidCallback onSaved;

  @override
  ConsumerState<_DnaEditor> createState() => _DnaEditorState();
}

class _DnaEditorState extends ConsumerState<_DnaEditor> {
  late final Map<String, double> _scores = {
    ...widget.dna.scores.map((key, value) => MapEntry(key, value.clamp(0, 10))),
  };
  late final List<String> _dimensions = widget.dna.dimensions.isEmpty
      ? _scores.keys.toList()
      : widget.dna.dimensions;
  bool _busy = false;
  bool _dirty = false;
  String? _error;

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(userRepositoryProvider).updateDna({
        for (final entry in _scores.entries) entry.key: entry.value.round(),
      });
      if (!mounted) return;
      setState(() => _dirty = false);
      widget.onSaved();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Journey DNA updated.')),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _reset() {
    setState(() {
      _scores
        ..clear()
        ..addAll(
          widget.dna.scores.map(
            (key, value) => MapEntry(key, value.clamp(0, 10)),
          ),
        );
      _dirty = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.safar;
    final sorted = _scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        const Eyebrow('Editable, never a label'),
        const SizedBox(height: 8),
        Text('Journey DNA', style: context.texts.headlineLarge),
        const SizedBox(height: 8),
        Text(
          widget.dna.note ??
              'These dimensions describe how you tend to travel. Change them whenever they stop '
                  'feeling true — SAFAR uses them as signals, not verdicts.',
          style: context.texts.bodySmall?.copyWith(height: 1.5),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            StatusChip(
              widget.dna.source ?? 'default',
              tone: ChipTone.jade,
              icon: Icons.auto_awesome,
            ),
            if (widget.dna.updatedAt != null) ...[
              const SizedBox(width: 8),
              Text(
                'Updated ${timeAgo(widget.dna.updatedAt)}',
                style: context.texts.labelSmall,
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        if (sorted.isNotEmpty)
          SafarCard(
            color: palette.raised,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Eyebrow('Current shape'),
                const SizedBox(height: 10),
                for (final entry in sorted.take(3))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 110,
                          child: Text(
                            titleCase(entry.key),
                            style: context.texts.bodySmall,
                          ),
                        ),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(99),
                            child: LinearProgressIndicator(
                              value: (entry.value / 10).clamp(0, 1),
                              minHeight: 6,
                              backgroundColor: palette.line,
                              color: palette.ember,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          entry.value.toStringAsFixed(1),
                          style: context.texts.labelSmall,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 20),
        const SectionHeader(eyebrow: 'Dimensions', title: 'Tune each signal'),
        if (_dimensions.isEmpty)
          const SafarEmpty(
            icon: Icons.fingerprint,
            title: 'No dimensions yet',
            message:
                'Add interests to your profile and SAFAR will propose starting signals.',
          )
        else
          for (final dimension in _dimensions)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: SafarCard(
                padding: const EdgeInsets.fromLTRB(15, 12, 15, 8),
                radius: 18,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            titleCase(dimension),
                            style: context.texts.titleSmall,
                          ),
                        ),
                        Text(
                          (_scores[dimension] ?? 5).toStringAsFixed(0),
                          style: context.texts.titleSmall?.copyWith(
                            color: palette.ember,
                          ),
                        ),
                      ],
                    ),
                    Slider(
                      value: (_scores[dimension] ?? 5).clamp(0, 10),
                      min: 0,
                      max: 10,
                      divisions: 10,
                      onChanged: _busy
                          ? null
                          : (value) => setState(() {
                              _scores[dimension] = value;
                              _dirty = true;
                            }),
                    ),
                  ],
                ),
              ),
            ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          InfoBanner(text: _error!, tone: ChipTone.rose),
        ],
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _busy || !_dirty ? null : _reset,
                child: const Text('Reset'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: _busy || !_dirty ? null : _save,
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save DNA'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        const InfoBanner(
          icon: Icons.lock_outline,
          text:
              'Journey DNA is used to personalise suggestions. It is not shared with other members, '
              'and you can clear or change it at any time.',
        ),
      ],
    );
  }
}
