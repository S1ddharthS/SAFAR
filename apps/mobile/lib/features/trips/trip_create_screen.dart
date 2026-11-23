import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/discovery.dart';
import '../../core/network/api_exception.dart';
import '../../core/providers.dart';
import '../../core/theme/safar_theme.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/safar_widgets.dart';

class TripCreateScreen extends ConsumerStatefulWidget {
  const TripCreateScreen({super.key});

  @override
  ConsumerState<TripCreateScreen> createState() => _TripCreateScreenState();
}

class _TripCreateScreenState extends ConsumerState<TripCreateScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _customDestination = TextEditingController();
  final _description = TextEditingController();
  final _budget = TextEditingController();
  final _dates = TextEditingController();
  String? _destinationId;
  bool _custom = false;
  DateTimeRange _range = DateTimeRange(
    start: DateTime.now().add(const Duration(days: 30)),
    end: DateTime.now().add(const Duration(days: 34)),
  );
  int _groupSize = 4;
  String _currency = 'EUR';
  String _tripType = 'group';
  bool _busy = false;
  String? _error;

  bool get _isSolo => _tripType == 'solo';

  String get _dateLabel =>
      '${formatDate(isoDate(_range.start))} → ${formatDate(isoDate(_range.end))}';

  @override
  void initState() {
    super.initState();
    _dates.text = _dateLabel;
  }

  @override
  void dispose() {
    _name.dispose();
    _customDestination.dispose();
    _description.dispose();
    _budget.dispose();
    _dates.dispose();
    super.dispose();
  }

  Future<void> _pickDates() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
      initialDateRange: _range,
      helpText: 'Trip dates',
    );
    if (picked != null) {
      setState(() {
        _range = picked;
        _dates.text = _dateLabel;
      });
    }
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    if (!_custom && _destinationId == null) {
      setState(() => _error = 'Choose a destination or enter your own.');
      return;
    }
    setState(() => _busy = true);
    try {
      final budget = double.tryParse(_budget.text.replaceAll(',', '.'));
      final trip = await ref
          .read(tripRepositoryProvider)
          .create(
            name: _name.text.trim(),
            startDate: isoDate(_range.start),
            endDate: isoDate(_range.end),
            destinationId: _custom ? null : _destinationId,
            destinationName:
                _custom ? _customDestination.text.trim() : null,
            description: _description.text.trim(),
            groupSize: _isSolo ? 1 : _groupSize,
            budgetTotal: budget != null && budget > 0 ? budget : null,
            currency: _currency,
            tripType: _tripType,
          );
      ref.invalidate(tripsProvider);
      if (!mounted) return;
      context.go('/trips/${trip.id}');
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.safar;
    final destinations = ref.watch(destinationsProvider);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => context.pop(),
          icon: const Icon(Icons.close),
        ),
        title: const Text('New trip'),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              const Eyebrow('Set the frame'),
              const SizedBox(height: 8),
              Text('A trip starts\nwith a shape.', style: context.texts.displaySmall),
              const SizedBox(height: 8),
              Text(
                'Only the essentials. The group adds constraints later, privately.',
                style: context.texts.bodySmall,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: palette.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: palette.line),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => setState(() {
                          _tripType = 'group';
                          if (_groupSize == 1) _groupSize = 4;
                        }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: !_isSolo ? palette.emberSoft : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.groups_outlined,
                                size: 18,
                                color: !_isSolo ? palette.ember : palette.faint,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Group Journey',
                                style: TextStyle(
                                  fontWeight: !_isSolo ? FontWeight.w600 : FontWeight.normal,
                                  color: !_isSolo ? palette.ember : palette.faint,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => setState(() {
                          _tripType = 'solo';
                          _groupSize = 1;
                        }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: _isSolo ? palette.emberSoft : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.person_outline,
                                size: 18,
                                color: _isSolo ? palette.ember : palette.faint,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Solo Journey',
                                style: TextStyle(
                                  fontWeight: _isSolo ? FontWeight.w600 : FontWeight.normal,
                                  color: _isSolo ? palette.ember : palette.faint,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (_error != null) ...[
                InfoBanner(
                  text: _error!,
                  icon: Icons.error_outline,
                  tone: ChipTone.rose,
                ),
                const SizedBox(height: 16),
              ],
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Trip name',
                  hintText: 'Autumn in the Douro',
                ),
                validator: (value) =>
                    (value == null || value.trim().length < 2)
                    ? 'Give the trip a name'
                    : null,
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Destination',
                      style: context.texts.labelMedium,
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      _custom = !_custom;
                      if (_custom) _destinationId = null;
                    }),
                    child: Text(_custom ? 'Use catalog' : 'Enter my own'),
                  ),
                ],
              ),
              if (_custom)
                TextFormField(
                  controller: _customDestination,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    hintText: 'City or region',
                  ),
                  validator: (value) =>
                      (value == null || value.trim().length < 2)
                      ? 'Name the destination'
                      : null,
                )
              else
                destinations.when(
                  data: (items) => DropdownButtonFormField<String>(
                    initialValue: _destinationId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      hintText: 'Choose a destination',
                    ),
                    items: [
                      for (final Destination destination in items)
                        DropdownMenuItem(
                          value: destination.id,
                          child: Text(
                            '${destination.name}, ${destination.country}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) => setState(() => _destinationId = value),
                  ),
                  loading: () => const SkeletonBox(height: 52, radius: 16),
                  error: (error, stack) => SafarErrorView(
                    message: error.toString(),
                    onRetry: () => ref.invalidate(destinationsProvider),
                  ),
                ),
              const SizedBox(height: 14),
              GestureDetector(
                onTap: _pickDates,
                child: AbsorbPointer(
                  child: TextFormField(
                    readOnly: true,
                    controller: _dates,
                    decoration: const InputDecoration(
                      labelText: 'Dates',
                      suffixIcon: Icon(Icons.date_range_outlined, size: 20),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '${_range.duration.inDays + 1} days',
                  style: context.texts.labelSmall,
                ),
              ),
              const SizedBox(height: 16),
              if (_isSolo)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                  decoration: BoxDecoration(
                    color: palette.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: palette.line),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.person_outline, size: 20, color: palette.ember),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Solo Traveller (1 person)', style: context.texts.titleSmall),
                            Text(
                              'No invitations needed. Solo Safety Centre will be enabled.',
                              style: context.texts.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Travellers', style: context.texts.labelMedium),
                          const SizedBox(height: 6),
                          Text(
                            'Approximate group size',
                            style: context.texts.labelSmall,
                          ),
                        ],
                      ),
                    ),
                    IconButton.filledTonal(
                      onPressed: _groupSize > 2
                          ? () => setState(() => _groupSize -= 1)
                          : null,
                      icon: const Icon(Icons.remove, size: 18),
                      tooltip: 'Fewer travellers',
                    ),
                    SizedBox(
                      width: 44,
                      child: Text(
                        '$_groupSize',
                        textAlign: TextAlign.center,
                        style: context.texts.titleLarge,
                      ),
                    ),
                    IconButton.filledTonal(
                      onPressed: _groupSize < 30
                          ? () => setState(() => _groupSize += 1)
                          : null,
                      icon: const Icon(Icons.add, size: 18),
                      tooltip: 'More travellers',
                    ),
                  ],
                ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _budget,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: _isSolo
                            ? 'Personal budget (optional)'
                            : 'Group budget (optional)',
                        hintText: _isSolo
                            ? 'Estimated personal spend'
                            : 'Total, not per person',
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) return null;
                        final parsed = double.tryParse(
                          value.replaceAll(',', '.'),
                        );
                        if (parsed == null || parsed <= 0) {
                          return 'Enter a positive amount';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 114,
                    child: DropdownButtonFormField<String>(
                      initialValue: _currency,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Currency'),
                      items: const [
                        DropdownMenuItem(value: 'EUR', child: Text('EUR')),
                        DropdownMenuItem(value: 'USD', child: Text('USD')),
                        DropdownMenuItem(value: 'GBP', child: Text('GBP')),
                        DropdownMenuItem(value: 'INR', child: Text('INR')),
                        DropdownMenuItem(value: 'JPY', child: Text('JPY')),
                      ],
                      onChanged: (value) =>
                          setState(() => _currency = value ?? 'EUR'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _description,
                maxLines: 3,
                maxLength: 400,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: _isSolo
                      ? 'Personal notes (optional)'
                      : 'A note for the group (optional)',
                  hintText: _isSolo
                      ? 'What are you aiming to experience?'
                      : 'What kind of journey is this?',
                ),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(_isSolo ? 'Create solo trip' : 'Create trip'),
              ),
              const SizedBox(height: 10),
              Text(
                'Trips are private by default. Invitations are explicit and '
                'member budgets never appear in shared views.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.5,
                  color: palette.faint,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
