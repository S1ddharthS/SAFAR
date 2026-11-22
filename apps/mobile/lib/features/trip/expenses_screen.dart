import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/expenses.dart';
import '../../core/models/trip.dart';
import '../../core/native/file_exporter.dart';
import '../../core/network/api_exception.dart';
import '../../core/providers.dart';
import '../../core/theme/safar_theme.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/safar_widgets.dart';
import '../auth/auth_controller.dart';

class ExpensesScreen extends ConsumerStatefulWidget {
  const ExpensesScreen({super.key, required this.tripId});

  final String tripId;

  @override
  ConsumerState<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends ConsumerState<ExpensesScreen> {
  bool _busy = false;

  Future<void> _exportCsv(Trip? trip) async {
    setState(() => _busy = true);
    try {
      final csv = await ref
          .read(expenseRepositoryProvider)
          .exportCsv(widget.tripId);
      if (!mounted) return;
      if (csv.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No expenses recorded to export.')),
        );
        return;
      }
      final tripName = trip?.name ?? 'trip';
      final safeName = FileExporter.sanitizeFilename(
        'expenses_${tripName.toLowerCase()}',
      );
      final filename = '$safeName.csv';

      final exporter = ref.read(fileExporterProvider);
      final result = await exporter.saveToCache(
        filename: filename,
        content: csv,
        mimeType: 'text/csv',
      );
      if (!mounted) return;
      setState(() => _busy = false);

      await showSafarSheet<void>(
        context,
        builder: (_) => ExportActionSheet(
          result: result,
          title: 'Expenses CSV ready',
          subtitle:
              'RFC 4180 compliant CSV formatted for spreadsheet software.',
          formatLabel: 'CSV Spreadsheet',
          formatIcon: Icons.table_chart_outlined,
          openActionLabel: 'Open in app',
          shareActionLabel: 'Share CSV',
          infoBannerText:
              'Shared expenses are visible to active trip members. Personal budget limits remain private.',
          fileExporter: exporter,
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not export expenses: $error')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refresh() async {
    ref.invalidate(expensesProvider(widget.tripId));
    ref.invalidate(balancesProvider(widget.tripId));
    try {
      await ref.read(expensesProvider(widget.tripId).future);
    } on Object {
      // AsyncView renders failures.
    }
  }

  Future<void> _addExpense(List<Member> members, Trip trip) async {
    final formKey = GlobalKey<FormState>();
    final title = TextEditingController();
    final amount = TextEditingController();
    final notes = TextEditingController();
    var category = 'food';
    String? paidBy = members.firstWhere(
      (member) => member.isSelf,
      orElse: () => members.isEmpty
          ? const Member(
              id: '',
              displayName: '',
              role: '',
              status: '',
              joinedAt: '',
              isSelf: false,
            )
          : members.first,
    ).user?.id;
    var incurredOn = isoDate(DateTime.now());

    final submitted = await showSafarSheet<bool>(
      context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SafarSheetHeader(
                  title: 'Add shared expense',
                  subtitle:
                      'Split equally across active members. Member budget limits are not shown or used.',
                ),
                TextFormField(
                  controller: title,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'What was it?'),
                  validator: (value) =>
                      (value == null || value.trim().length < 2)
                      ? 'Add a short title'
                      : null,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: amount,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Amount',
                          suffixText: trip.currency,
                        ),
                        validator: (value) {
                          final parsed = double.tryParse(
                            (value ?? '').replaceAll(',', '.'),
                          );
                          if (parsed == null || parsed <= 0) {
                            return 'Enter a positive amount';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: category,
                        decoration: const InputDecoration(
                          labelText: 'Category',
                        ),
                        items: const [
                          DropdownMenuItem(value: 'food', child: Text('Food')),
                          DropdownMenuItem(
                            value: 'transport',
                            child: Text('Transport'),
                          ),
                          DropdownMenuItem(value: 'stay', child: Text('Stay')),
                          DropdownMenuItem(
                            value: 'activity',
                            child: Text('Activity'),
                          ),
                          DropdownMenuItem(
                            value: 'shopping',
                            child: Text('Shopping'),
                          ),
                          DropdownMenuItem(value: 'other', child: Text('Other')),
                        ],
                        onChanged: (value) =>
                            setSheetState(() => category = value ?? 'food'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: paidBy,
                  decoration: const InputDecoration(labelText: 'Paid by'),
                  items: [
                    for (final member in members)
                      if (member.user != null)
                        DropdownMenuItem(
                          value: member.user!.id,
                          child: Text(
                            member.isSelf
                                ? '${member.displayName} (you)'
                                : member.displayName,
                          ),
                        ),
                  ],
                  onChanged: (value) => setSheetState(() => paidBy = value),
                ),
                const SizedBox(height: 12),
                InputDecorator(
                  decoration: const InputDecoration(labelText: 'Spent on'),
                  child: InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: sheetContext,
                        firstDate: DateTime.now().subtract(
                          const Duration(days: 365),
                        ),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                        initialDate: DateTime.now(),
                      );
                      if (picked != null) {
                        setSheetState(() => incurredOn = isoDate(picked));
                      }
                    },
                    child: Row(
                      children: [
                        Expanded(child: Text(formatDate(incurredOn))),
                        const Icon(Icons.date_range_outlined, size: 18),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: notes,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                  ),
                ),
                const SizedBox(height: 16),
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
                        onPressed: () {
                          if (formKey.currentState!.validate()) {
                            Navigator.of(sheetContext).pop(true);
                          }
                        },
                        child: const Text('Add expense'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final values = (
      title: title.text.trim(),
      amount: double.tryParse(amount.text.replaceAll(',', '.')) ?? 0,
      notes: notes.text.trim(),
      category: category,
      paidBy: paidBy,
      incurredOn: incurredOn,
    );
    title.dispose();
    amount.dispose();
    notes.dispose();
    if (submitted != true) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(expenseRepositoryProvider)
          .create(
            widget.tripId,
            title: values.title,
            amount: values.amount,
            category: values.category,
            paidBy: values.paidBy,
            incurredOn: values.incurredOn,
            notes: values.notes.isEmpty ? null : values.notes,
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

  Future<void> _delete(Expense expense) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this expense?'),
        content: Text('“${expense.title}” will be removed from shared totals.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: context.safar.rose),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(expenseRepositoryProvider)
          .delete(widget.tripId, expense.id);
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

  @override
  Widget build(BuildContext context) {
    final palette = context.safar;
    final expenses = ref.watch(expensesProvider(widget.tripId));
    final balances = ref.watch(balancesProvider(widget.tripId));
    final trip = ref.watch(tripProvider(widget.tripId)).valueOrNull;
    final members = ref.watch(membersProvider(widget.tripId)).valueOrNull ?? const [];
    final me = ref.watch(authControllerProvider).user;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back),
        ),
        title: const Text('Shared expenses'),
        actions: [
          IconButton(
            tooltip: 'Export CSV',
            onPressed: _busy ? null : () => _exportCsv(trip),
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_outlined),
          ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: trip == null || members.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _busy ? null : () => _addExpense(members, trip),
              icon: const Icon(Icons.add),
              label: const Text('Add expense'),
            ),
      body: SafeArea(
        child: AsyncView(
          value: expenses,
          onRetry: () => ref.invalidate(expensesProvider(widget.tripId)),
          builder: (data) {
            final currency = trip?.currency ?? 'EUR';
            final total = data.totals[currency] ??
                data.totals.values.fold<double>(0, (a, b) => a + b);
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 110),
                children: [
                  const Eyebrow('Money, shared fairly'),
                  const SizedBox(height: 8),
                  Text(
                    formatMoney(total, currency),
                    style: context.texts.displayMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Total shared across ${data.items.length} entries',
                    style: context.texts.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  balances.when(
                    data: (balance) {
                      if (data.items.isEmpty) {
                        return const SizedBox.shrink();
                      }
                      return SafarCard(
                        color: palette.jadeSoft.withValues(alpha: 0.55),
                        borderColor: palette.jade.withValues(alpha: 0.35),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Eyebrow('Settle up'),
                            const SizedBox(height: 8),
                            if (balance.settlements.isEmpty)
                              Text(
                                'Everyone is even.',
                                style: context.texts.titleSmall,
                              )
                            else
                              for (final settlement in balance.settlements)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '${settlement.fromName} → ${settlement.toName}',
                                          style: context.texts.bodyMedium,
                                        ),
                                      ),
                                      Text(
                                        formatMoney(
                                          settlement.amount,
                                          balance.currency,
                                        ),
                                        style: context.texts.titleSmall,
                                      ),
                                    ],
                                  ),
                                ),
                            const SizedBox(height: 4),
                            Text(
                              'Balances use equal splits by default. Member budget limits are private and never shown here.',
                              style: context.texts.labelSmall,
                            ),
                          ],
                        ),
                      );
                    },
                    loading: () => const SkeletonBox(height: 80, radius: 18),
                    error: (error, stack) => const SizedBox.shrink(),
                  ),
                  const SizedBox(height: 22),
                  const SectionHeader(eyebrow: 'Ledger', title: 'Expenses'),
                  if (data.items.isEmpty)
                    const SafarEmpty(
                      title: 'No shared expenses',
                      message:
                          'Add the first cost. SAFAR keeps budgets private and only shares the group ledger.',
                      icon: Icons.receipt_long_outlined,
                    )
                  else
                    for (final expense in data.items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: SafarCard(
                          padding: const EdgeInsets.all(14),
                          radius: 18,
                          child: Row(
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: palette.raised,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  _categoryIcon(expense.category),
                                  size: 18,
                                  color: palette.muted,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      expense.title,
                                      style: context.texts.titleSmall,
                                    ),
                                    Text(
                                      '${expense.payer?.displayName ?? 'Someone'} paid · ${formatDateShort(expense.incurredOn)}',
                                      style: context.texts.labelSmall,
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    formatMoney(expense.amount, expense.currency),
                                    style: context.texts.titleSmall,
                                  ),
                                  if (expense.participants.isNotEmpty)
                                    Text(
                                      '${expense.participants.length} shares',
                                      style: context.texts.labelSmall,
                                    ),
                                ],
                              ),
                              PopupMenuButton<String>(
                                tooltip: 'Expense options',
                                icon: Icon(
                                  Icons.more_vert,
                                  size: 17,
                                  color: palette.faint,
                                ),
                                onSelected: (value) {
                                  if (value == 'delete') _delete(expense);
                                },
                                itemBuilder: (context) => [
                                  if (expense.paidBy == me?.id)
                                    const PopupMenuItem(
                                      value: 'delete',
                                      child: Text('Delete'),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                  const SizedBox(height: 10),
                  InfoBanner(
                    text: balances.valueOrNull?.disclosure ??
                        'Shared expenses are visible to active trip members. Personal budgets remain private.',
                    icon: Icons.lock_outline,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  static IconData _categoryIcon(String category) {
    return switch (category) {
      'food' => Icons.restaurant_outlined,
      'transport' => Icons.directions_bus_outlined,
      'stay' => Icons.hotel_outlined,
      'activity' => Icons.local_activity_outlined,
      'shopping' => Icons.shopping_bag_outlined,
      _ => Icons.receipt_long_outlined,
    };
  }
}
