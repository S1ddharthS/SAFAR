import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/discovery.dart';
import '../../core/models/social.dart';
import '../../core/providers.dart';
import '../../core/theme/safar_theme.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/safar_widgets.dart';

const _reportCategories = [
  'crowd',
  'queue',
  'parking',
  'closure',
  'accessibility',
  'price',
  'road',
  'quality',
];

class PlaceScreen extends ConsumerStatefulWidget {
  const PlaceScreen({
    super.key,
    required this.tripId,
    required this.activityId,
  });

  final String tripId;
  final String activityId;

  @override
  ConsumerState<PlaceScreen> createState() => _PlaceScreenState();
}

class _PlaceScreenState extends ConsumerState<PlaceScreen> {
  bool _busy = false;
  bool _checkBusy = false;
  ExpectationCheck? _expectation;

  PlaceRecord get _key =>
      (tripId: widget.tripId, activityId: widget.activityId);

  Future<void> _checkExpectation() async {
    final claim = TextEditingController();
    final submitted = await showSafarSheet<bool>(
      context,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SafarSheetHeader(
            title: 'Check an expectation',
            subtitle:
                'Type a claim you are about to plan around, for example '
                '“quiet on weekday mornings”. SAFAR compares it with catalog '
                'evidence and traveller reports — never with invented facts.',
          ),
          TextField(
            controller: claim,
            maxLines: 3,
            maxLength: 300,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Your expectation',
              hintText: 'It is closed on Mondays',
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
                  child: const Text('Check'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    final text = claim.text.trim();
    claim.dispose();
    if (submitted != true) return;
    if (text.length < 3) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Describe the expectation in a few words.')),
      );
      return;
    }
    setState(() => _checkBusy = true);
    try {
      final result = await ref
          .read(discoveryRepositoryProvider)
          .expectationCheck(widget.tripId, widget.activityId, text);
      if (!mounted) return;
      setState(() => _expectation = result);
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      if (mounted) setState(() => _checkBusy = false);
    }
  }

  Future<void> _addToTrip(PlaceDetail detail) async {
    final trip = ref.read(tripProvider(widget.tripId)).valueOrNull;
    if (trip == null) return;
    final days = tripDays(trip.startDate, trip.endDate);
    if (days.isEmpty) return;
    var selectedDay = days.first;
    final timeController = TextEditingController(text: '09:00');
    final submitted = await showSafarSheet<bool>(
      context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SafarSheetHeader(
              title: 'Add to itinerary',
              subtitle:
                  'You can move this item later. Nothing is confirmed until the group approves.',
            ),
            Text('Day', style: context.texts.labelMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final day in days)
                  ChoiceChip(
                    label: Text(formatDateShort(isoDate(day))),
                    selected: isoDate(selectedDay) == isoDate(day),
                    onSelected: (_) =>
                        setSheetState(() => selectedDay = day),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: timeController,
              keyboardType: TextInputType.datetime,
              decoration: const InputDecoration(
                labelText: 'Start time',
                hintText: '09:00',
              ),
            ),
            const SizedBox(height: 18),
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
                    onPressed: () =>
                        Navigator.of(sheetContext).pop(true),
                    child: const Text('Add item'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    final time = timeController.text.trim();
    timeController.dispose();
    if (submitted != true) return;
    if (!RegExp(r'^\d{2}:\d{2}$').hasMatch(time)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Use a 24-hour time such as 09:30.')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(itineraryRepositoryProvider)
          .addItem(
            widget.tripId,
            day: isoDate(selectedDay),
            title: detail.activity.name,
            startTime: time,
            activityId: detail.activity.id,
            notes: 'Added from Discover',
            costEstimate: detail.activity.priceEstimate,
          );
      ref.invalidate(itineraryProvider(widget.tripId));
      ref.invalidate(tripProvider(widget.tripId));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${detail.activity.name} added to ${formatDateShort(isoDate(selectedDay))}.',
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

  Future<void> _report() async {
    var category = 'crowd';
    var level = 'moderate';
    final note = TextEditingController();
    final submitted = await showSafarSheet<bool>(
      context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SafarSheetHeader(
              title: 'Report a condition',
              subtitle:
                  'Reports are attributed to you and shared with this trip. '
                  'They are not presented as verified fact.',
            ),
            DropdownButtonFormField<String>(
              initialValue: category,
              decoration: const InputDecoration(labelText: 'Category'),
              items: [
                for (final item in _reportCategories)
                  DropdownMenuItem(value: item, child: Text(titleCase(item))),
              ],
              onChanged: (value) =>
                  setSheetState(() => category = value ?? category),
            ),
            if (category == 'crowd') ...[
              const SizedBox(height: 14),
              Text('How busy is it?', style: context.texts.labelMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final option in const ['quiet', 'moderate', 'busy'])
                    ChoiceChip(
                      label: Text(titleCase(option)),
                      selected: level == option,
                      onSelected: (_) => setSheetState(() => level = option),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            TextField(
              controller: note,
              maxLines: 3,
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: 'What did you observe?',
                hintText: 'Keep it factual and useful to the next traveller.',
              ),
            ),
            const SizedBox(height: 6),
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
                    child: const Text('Share report'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    final text = note.text.trim();
    note.dispose();
    if (submitted != true) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(discoveryRepositoryProvider)
          .createPlaceReport(
            widget.tripId,
            activityId: widget.activityId,
            category: category,
            value: category == 'crowd' ? {'level': level} : {'note': text},
            note: text,
          );
      ref.invalidate(placeDetailProvider(_key));
      ref.invalidate(placeReportsProvider(_key));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Report shared. Thank you for keeping it factual.'),
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

  Future<void> _helpful(PlaceReportItem report) async {
    try {
      await ref
          .read(discoveryRepositoryProvider)
          .markReportHelpful(widget.tripId, report.id);
      ref.invalidate(placeReportsProvider(_key));
      ref.invalidate(placeDetailProvider(_key));
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.safar;
    final detail = ref.watch(placeDetailProvider(_key));
    final reports = ref.watch(placeReportsProvider(_key));

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back),
        ),
        title: const Text('Place evidence'),
      ),
      body: AsyncView(
        value: detail,
        onRetry: () => ref.invalidate(placeDetailProvider(_key)),
        skeleton: const SkeletonList(count: 3),
        builder: (data) {
          final activity = data.activity;
          final image = ref.read(apiClientProvider).mediaUrl(activity.imageUrl);
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(placeDetailProvider(_key));
              ref.invalidate(placeReportsProvider(_key));
              try {
                await ref.read(placeDetailProvider(_key).future);
              } on Object {
                // AsyncView surfaces the failure.
              }
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
              children: [
                SafarImage(url: image, height: 210, radius: 26),
                const SizedBox(height: 18),
                Eyebrow(activity.place?.name ?? 'Place'),
                const SizedBox(height: 8),
                Text(activity.name, style: context.texts.headlineLarge),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (activity.priceEstimate > 0)
                      StatusChip(
                        formatMoney(activity.priceEstimate, activity.currency),
                        tone: ChipTone.ember,
                      ),
                    if (activity.durationMinutes > 0)
                      StatusChip('${activity.durationMinutes} min'),
                    if (activity.indoor) const StatusChip('Indoor'),
                    if (activity.wheelchairAccessible == true)
                      const StatusChip('Step-free', tone: ChipTone.jade),
                    if (activity.fragile)
                      const StatusChip('Fragile place', tone: ChipTone.rose),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  activity.description,
                  style: context.texts.bodyMedium?.copyWith(height: 1.55),
                ),
                if (activity.place?.address != null) ...[
                  const SizedBox(height: 10),
                  Text(activity.place!.address!, style: context.texts.bodySmall),
                ],
                if (activity.place?.respectNote != null) ...[
                  const SizedBox(height: 14),
                  InfoBanner(
                    text: activity.place!.respectNote!,
                    icon: Icons.spa_outlined,
                    tone: ChipTone.jade,
                  ),
                ],
                const SizedBox(height: 14),
                SourceLabel(
                  source: data.catalogFreshness.label,
                  confidence: data.catalogFreshness.lastVerifiedAt == null
                      ? null
                      : 'verified ${formatDateShort(data.catalogFreshness.lastVerifiedAt)}',
                ),
                if (data.accessChain != null) ...[
                  const SizedBox(height: 24),
                  const SectionHeader(
                    eyebrow: 'Access chain',
                    title: 'Getting in, step by step',
                  ),
                  SafarCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final stage in data.accessChain!.stages)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  switch (stage.status) {
                                    'verified' => Icons.check_circle_outline,
                                    'barrier' => Icons.block_outlined,
                                    'reported' => Icons.record_voice_over_outlined,
                                    _ => Icons.help_outline,
                                  },
                                  size: 17,
                                  color: stage.status == 'barrier'
                                      ? palette.rose
                                      : stage.status == 'verified'
                                      ? palette.jade
                                      : palette.faint,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(stage.label, style: context.texts.titleSmall),
                                      if (stage.detail != null)
                                        Text(
                                          stage.detail!,
                                          style: context.texts.bodySmall,
                                        ),
                                    ],
                                  ),
                                ),
                                StatusChip(
                                  stage.status,
                                  tone: stage.status == 'barrier'
                                      ? ChipTone.rose
                                      : stage.status == 'verified'
                                      ? ChipTone.jade
                                      : ChipTone.neutral,
                                ),
                              ],
                            ),
                          ),
                        if (data.accessChain!.disclosure != null)
                          Text(
                            data.accessChain!.disclosure!,
                            style: context.texts.labelSmall,
                          ),
                      ],
                    ),
                  ),
                ],
                if (data.crowdForecast != null) ...[
                  const SizedBox(height: 24),
                  const SectionHeader(
                    eyebrow: 'Prediction',
                    title: 'Crowd forecast',
                  ),
                  _CrowdCard(forecast: data.crowdForecast!),
                ],
                const SizedBox(height: 24),
                const SectionHeader(
                  eyebrow: 'Reality check',
                  title: 'Expectation check',
                ),
                if (_expectation != null)
                  _ExpectationCard(
                    check: _expectation!,
                    busy: _checkBusy,
                    onCheckAnother: _checkExpectation,
                  )
                else
                  SafarCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Planning around a claim? Ask SAFAR to compare it '
                          'with catalog evidence and latest traveller reports '
                          'before you commit a day to it.',
                          style: context.texts.bodySmall,
                        ),
                        const SizedBox(height: 12),
                        FilledButton.tonalIcon(
                          onPressed: _checkBusy ? null : _checkExpectation,
                          icon: _checkBusy
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.fact_check_outlined, size: 18),
                          label: const Text('Check an expectation'),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    const Expanded(
                      child: SectionHeader(
                        eyebrow: 'Community',
                        title: 'Traveller reports',
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _busy ? null : _report,
                      icon: const Icon(Icons.add_comment_outlined, size: 17),
                      label: const Text('Report'),
                    ),
                  ],
                ),
                reports.when(
                  data: (items) {
                    if (items.isEmpty) {
                      return const InfoBanner(
                        text:
                            'No reports yet. Share what you observed so the next '
                            'traveller can plan with evidence.',
                        icon: Icons.record_voice_over_outlined,
                      );
                    }
                    return Column(
                      children: [
                        for (final report in items)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: SafarCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      StatusChip(report.category),
                                      const SizedBox(width: 6),
                                      StatusChip(
                                        report.provenance.toLowerCase(),
                                        tone: report.verified
                                            ? ChipTone.jade
                                            : ChipTone.neutral,
                                      ),
                                      const Spacer(),
                                      Text(
                                        timeAgo(report.observedAt),
                                        style: context.texts.labelSmall,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  if (report.note != null &&
                                      report.note!.isNotEmpty)
                                    Text(report.note!, style: context.texts.bodyMedium),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Text(
                                        report.isMine
                                            ? 'Your report'
                                            : report.reporter?.displayName ??
                                                  'A traveller',
                                        style: context.texts.labelSmall,
                                      ),
                                      const Spacer(),
                                      TextButton.icon(
                                        onPressed: () => _helpful(report),
                                        icon: const Icon(
                                          Icons.thumb_up_outlined,
                                          size: 15,
                                        ),
                                        label: Text('Helpful ${report.helpfulCount}'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                  loading: () => const SizedBox(
                    height: 80,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (error, stack) => SafarErrorView(
                    message: error.toString(),
                    onRetry: () =>
                        ref.invalidate(placeReportsProvider(_key)),
                  ),
                ),
                if (data.unknowns.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  InfoBanner(
                    text:
                        'Still unknown: ${data.unknowns.join(', ')}. '
                        '${data.evidenceDisclosure ?? ''}',
                    icon: Icons.help_outline,
                  ),
                ],
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: detail.when(
          data: (data) => FilledButton.icon(
            onPressed: _busy ? null : () => _addToTrip(data),
            icon: const Icon(Icons.add, size: 19),
            label: const Text('Add to itinerary'),
          ),
          loading: () => const SizedBox(height: 48),
          error: (error, stack) => OutlinedButton.icon(
            onPressed: () => ref.invalidate(placeDetailProvider(_key)),
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Retry place details'),
          ),
        ),
      ),
    );
  }
}

class _ExpectationCard extends StatelessWidget {
  const _ExpectationCard({
    required this.check,
    required this.busy,
    required this.onCheckAnother,
  });

  final ExpectationCheck check;
  final bool busy;
  final VoidCallback onCheckAnother;

  @override
  Widget build(BuildContext context) {
    final palette = context.safar;
    final (label, tone) = switch (check.verdict) {
      'supported' => ('Supported by evidence', ChipTone.jade),
      'mixed' => ('Mixed evidence', ChipTone.ember),
      'unsupported' => ('Not supported', ChipTone.rose),
      _ => ('Not enough evidence', ChipTone.neutral),
    };
    return SafarCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  '“${check.claim}”',
                  style: context.texts.titleSmall,
                ),
              ),
              const SizedBox(width: 8),
              StatusChip(label, tone: tone),
            ],
          ),
          if (check.evidence.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final item in check.evidence)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      item.status == 'VERIFIED'
                          ? Icons.verified_outlined
                          : item.status == 'REPORTED'
                          ? Icons.record_voice_over_outlined
                          : Icons.help_outline,
                      size: 16,
                      color: item.status == 'VERIFIED'
                          ? palette.jade
                          : palette.faint,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.item, style: context.texts.titleSmall),
                          Text(
                            '${titleCase(item.status)} · ${item.detail}',
                            style: context.texts.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
          if (check.recentReports.isNotEmpty) ...[
            const SizedBox(height: 4),
            const Eyebrow('Recent reports'),
            const SizedBox(height: 6),
            for (final report in check.recentReports)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '• ${titleCase(report.category)}: ${report.status} · '
                  '${report.reportsCount} report(s) · ${report.freshnessLabel}',
                  style: context.texts.labelSmall,
                ),
              ),
          ],
          if (check.limitations.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Limits: ${check.limitations.join(' ')}',
              style: context.texts.labelSmall,
            ),
          ],
          if (check.unknowns.isNotEmpty) ...[
            const SizedBox(height: 10),
            InfoBanner(
              text: 'Still unknown: ${check.unknowns.join(', ')}.',
              icon: Icons.help_outline,
            ),
          ],
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: busy ? null : onCheckAnother,
              icon: const Icon(Icons.refresh, size: 17),
              label: const Text('Check another claim'),
            ),
          ),
        ],
      ),
    );
  }
}

class _CrowdCard extends StatelessWidget {
  const _CrowdCard({required this.forecast});

  final CrowdForecast forecast;

  @override
  Widget build(BuildContext context) {
    final palette = context.safar;
    final predicted = forecast.predicted;
    final observed = forecast.observed;
    if (forecast.status != 'ok' || predicted == null) {
      return SafarCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (forecast.status == 'insufficient_data')
              const StatusChip('Insufficient data', tone: ChipTone.neutral)
            else
              const StatusChip('Not available', tone: ChipTone.neutral),
            const SizedBox(height: 10),
            Text(
              forecast.message ??
                  'Not enough recent reports to forecast crowds for this place.',
              style: context.texts.bodySmall,
            ),
            if (forecast.requiredReports != null) ...[
              const SizedBox(height: 8),
              Text(
                '${forecast.availableReports ?? 0} of ${forecast.requiredReports} reports available.',
                style: context.texts.labelSmall,
              ),
            ],
            if (forecast.disclosure != null) ...[
              const SizedBox(height: 8),
              Text(forecast.disclosure!, style: context.texts.labelSmall),
            ],
          ],
        ),
      );
    }

    final byWeekday = <int, List<CrowdPoint>>{};
    for (final point in predicted.forecasts) {
      byWeekday.putIfAbsent(point.weekday, () => []).add(point);
    }
    final weekdays = byWeekday.keys.toList()..sort();
    final all = predicted.forecasts;
    final maxLevel = all.fold<double>(
      1,
      (value, point) => point.expectedLevel > value ? point.expectedLevel : value,
    );
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    return SafarCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StatusChip(
                predicted.provenance.toLowerCase(),
                tone: ChipTone.ember,
                icon: Icons.auto_graph,
              ),
              const Spacer(),
              if (predicted.model != null)
                Text(predicted.model!, style: context.texts.labelSmall),
            ],
          ),
          const SizedBox(height: 12),
          for (final weekday in weekdays) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 34,
                  child: Text(
                    weekday >= 1 && weekday <= 7 ? names[weekday - 1] : '$weekday',
                    style: context.texts.labelSmall,
                  ),
                ),
                Expanded(
                  child: Row(
                    children: [
                      for (final point in byWeekday[weekday]!)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 1.5),
                            child: Tooltip(
                              message:
                                  '${titleCase(point.bucket)} · ${point.levelLabel ?? point.expectedLevel.toStringAsFixed(1)}',
                              child: Container(
                                height: 18,
                                decoration: BoxDecoration(
                                  color: palette.ember.withValues(
                                    alpha: 0.16 +
                                        0.7 *
                                            (point.expectedLevel / maxLevel)
                                                .clamp(0, 1),
                                  ),
                                  borderRadius: BorderRadius.circular(5),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  width: 44,
                  child: Text(
                    _meanLabel(byWeekday[weekday]!),
                    textAlign: TextAlign.right,
                    style: context.texts.labelSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
          ],
          const SizedBox(height: 6),
          Row(
            children: [
              Text('Less crowded', style: context.texts.labelSmall),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  height: 5,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(99),
                    gradient: LinearGradient(
                      colors: [
                        palette.ember.withValues(alpha: 0.16),
                        palette.ember,
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text('Busier', style: context.texts.labelSmall),
            ],
          ),
          if (predicted.note != null) ...[
            const SizedBox(height: 10),
            Text(predicted.note!, style: context.texts.labelSmall),
          ],
          if (observed != null) ...[
            const SizedBox(height: 14),
            Divider(color: palette.line),
            const SizedBox(height: 10),
            Row(
              children: [
                const StatusChip('Observed', tone: ChipTone.jade),
                const Spacer(),
                Text(
                  '${observed.reportsUsed} of ${observed.reportsSeen} reports used',
                  style: context.texts.labelSmall,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              observed.note ??
                  'Based on attributed traveller reports. Individual experience may vary.',
              style: context.texts.bodySmall,
            ),
          ],
          if (forecast.disclosure != null) ...[
            const SizedBox(height: 10),
            Text(forecast.disclosure!, style: context.texts.labelSmall),
          ],
        ],
      ),
    );
  }

  static String _meanLabel(List<CrowdPoint> points) {
    if (points.isEmpty) return '';
    final mean =
        points.fold<double>(0, (sum, point) => sum + point.expectedLevel) /
        points.length;
    return mean.toStringAsFixed(1);
  }
}
