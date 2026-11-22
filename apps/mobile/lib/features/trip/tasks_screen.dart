import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/trip.dart';
import '../../core/providers.dart';
import '../../core/theme/safar_theme.dart';
import '../../core/widgets/safar_widgets.dart';

class TasksScreen extends ConsumerStatefulWidget {
  const TasksScreen({super.key, required this.tripId});

  final String tripId;

  @override
  ConsumerState<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends ConsumerState<TasksScreen> {
  final Set<String> _busy = {};
  bool _creating = false;

  String get _tripId => widget.tripId;

  List<({String id, String name})> _people(List<Member> members) => [
    for (final member in members)
      if (member.user != null) (id: member.user!.id, name: member.displayName),
  ];

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _addTask(List<({String id, String name})> people) async {
    final title = TextEditingController();
    final details = TextEditingController();
    var assignee = '';
    final submitted = await showSafarSheet<bool>(
      context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SafarSheetHeader(
              title: 'Add a task',
              subtitle:
                  'Anyone can add a task. The assignee, an owner or an admin '
                  'can update it later.',
            ),
            TextField(
              controller: title,
              maxLength: 160,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Title',
                hintText: 'Book the museum tickets',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: details,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Details (optional)',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: assignee,
              decoration: const InputDecoration(labelText: 'Assign to'),
              items: [
                const DropdownMenuItem(value: '', child: Text('Unassigned')),
                for (final person in people)
                  DropdownMenuItem(
                    value: person.id,
                    child: Text(
                      person.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) =>
                  setSheetState(() => assignee = value ?? ''),
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
                    onPressed: () => Navigator.of(sheetContext).pop(true),
                    child: const Text('Add task'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    final text = title.text.trim();
    final description = details.text.trim();
    title.dispose();
    details.dispose();
    if (submitted != true) return;
    if (text.length < 2) {
      _notify('Give the task a title of at least 2 characters.');
      return;
    }
    setState(() => _creating = true);
    try {
      await ref
          .read(tripRepositoryProvider)
          .createTask(
            _tripId,
            title: text,
            description: description.isEmpty ? null : description,
            assigneeId: assignee.isEmpty ? null : assignee,
          );
      ref.invalidate(tasksProvider(_tripId));
      ref.invalidate(taskSummaryProvider(_tripId));
      _notify('Task added. It is shared with the trip.');
    } on Object catch (error) {
      _notify(error.toString());
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _update(
    TaskItem task, {
    String? status,
    String? assigneeId,
    bool unassign = false,
  }) async {
    if (_busy.contains(task.id)) return;
    setState(() => _busy.add(task.id));
    try {
      await ref
          .read(tripRepositoryProvider)
          .updateTask(
            _tripId,
            task.id,
            status: status,
            assigneeId: assigneeId,
            unassign: unassign,
          );
      ref.invalidate(tasksProvider(_tripId));
      ref.invalidate(taskSummaryProvider(_tripId));
    } on Object catch (error) {
      _notify(error.toString());
    } finally {
      if (mounted) setState(() => _busy.remove(task.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tasks = ref.watch(tasksProvider(_tripId));
    final summary = ref.watch(taskSummaryProvider(_tripId));
    final members = ref.watch(membersProvider(_tripId)).valueOrNull ?? const [];
    final people = _people(members);
    final names = {for (final person in people) person.id: person.name};

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back),
        ),
        title: const Text('Tasks'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(tasksProvider(_tripId));
          ref.invalidate(taskSummaryProvider(_tripId));
          try {
            await ref.read(tasksProvider(_tripId).future);
          } on Object {
            // The list surfaces the failure inline.
          }
        },
        child: AsyncView<List<TaskItem>>(
          value: tasks,
          onRetry: () => ref.invalidate(tasksProvider(_tripId)),
          builder: (items) {
            final open = items.where((task) => !task.done).toList();
            final done = items.where((task) => task.done).toList();
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                const Eyebrow('Planner load'),
                const SizedBox(height: 8),
                Text('Share the planning work', style: context.texts.displaySmall),
                const SizedBox(height: 8),
                Text(
                  'Tasks keep the invisible work visible so one person does '
                  'not carry the whole plan.',
                  style: context.texts.bodySmall,
                ),
                const SizedBox(height: 16),
                _LoadCard(summary: summary.valueOrNull),
                const SizedBox(height: 12),
                SafarCard(
                  padding: const EdgeInsets.all(14),
                  radius: 18,
                  onTap: _creating ? null : () => _addTask(people),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: context.safar.emberSoft,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.add_task_outlined,
                          size: 19,
                          color: context.safar.ember,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Add a task', style: context.texts.titleSmall),
                            Text(
                              'Assign an owner so the load is visible.',
                              style: context.texts.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      if (_creating)
                        const SizedBox(
                          width: 17,
                          height: 17,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        Icon(
                          Icons.chevron_right,
                          size: 18,
                          color: context.safar.faint,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                SectionHeader(
                  eyebrow: 'Open',
                  title: '${open.length} waiting',
                ),
                if (open.isEmpty)
                  Text(
                    'Nothing open. Every current task is done.',
                    style: context.texts.bodySmall,
                  )
                else
                  for (final task in open)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _TaskRow(
                        task: task,
                        assignee: task.assigneeId == null
                            ? 'Unassigned'
                            : names[task.assigneeId] ?? 'A member',
                        busy: _busy.contains(task.id),
                        people: people,
                        onToggle: () => _update(task, status: 'done'),
                        onAssign: (value) => _update(
                          task,
                          assigneeId: value.isEmpty ? null : value,
                          unassign: value.isEmpty,
                        ),
                      ),
                    ),
                const SizedBox(height: 18),
                SectionHeader(
                  eyebrow: 'Done',
                  title: '${done.length} completed',
                ),
                if (done.isEmpty)
                  Text(
                    'Nothing completed yet.',
                    style: context.texts.bodySmall,
                  )
                else
                  for (final task in done)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _TaskRow(
                        task: task,
                        assignee: task.assigneeId == null
                            ? 'Unassigned'
                            : names[task.assigneeId] ?? 'A member',
                        busy: _busy.contains(task.id),
                        people: people,
                        onToggle: () => _update(task, status: 'open'),
                        onAssign: null,
                      ),
                    ),
                const SizedBox(height: 16),
                const InfoBanner(
                  text:
                      'Anyone can add a task. Only the assignee, an owner or an '
                      'admin can update it. Load counts come from open tasks '
                      'and are a nudge, not a score.',
                  icon: Icons.balance_outlined,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _LoadCard extends StatelessWidget {
  const _LoadCard({required this.summary});

  final TaskSummary? summary;

  @override
  Widget build(BuildContext context) {
    final data = summary;
    return SafarCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            eyebrow: 'Counts from the API',
            title: 'Load balance',
          ),
          if (data == null)
            Text('Counting…', style: context.texts.bodySmall)
          else ...[
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                StatusChip('${data.open} open', tone: ChipTone.ember),
                StatusChip('${data.done} done', tone: ChipTone.jade),
                StatusChip('${data.total} total'),
                if (data.unassigned != null && data.unassigned!.open > 0)
                  StatusChip(
                    '${data.unassigned!.open} unassigned',
                    tone: ChipTone.rose,
                  ),
              ],
            ),
            if (data.load.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final entry in data.load)
                    StatusChip(
                      '${entry.key == 'unassigned' ? 'Unassigned' : entry.displayName} · ${entry.open}',
                      tone: entry.open >= 3 ? ChipTone.ember : ChipTone.neutral,
                    ),
                ],
              ),
            ],
            if (data.disclosure != null && data.disclosure!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(data.disclosure!, style: context.texts.labelSmall),
            ],
          ],
        ],
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({
    required this.task,
    required this.assignee,
    required this.busy,
    required this.people,
    required this.onToggle,
    required this.onAssign,
  });

  final TaskItem task;
  final String assignee;
  final bool busy;
  final List<({String id, String name})> people;
  final VoidCallback onToggle;
  final ValueChanged<String>? onAssign;

  @override
  Widget build(BuildContext context) {
    final palette = context.safar;
    final done = task.done;
    return SafarCard(
      padding: const EdgeInsets.fromLTRB(8, 10, 14, 10),
      radius: 18,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconButton(
            tooltip: done ? 'Reopen task' : 'Mark done',
            onPressed: busy ? null : onToggle,
            icon: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    done
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color: done ? palette.jade : palette.faint,
                  ),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title,
                  style: context.texts.titleSmall?.copyWith(
                    color: done ? palette.muted : null,
                    decoration: done ? TextDecoration.lineThrough : null,
                  ),
                ),
                if (task.description != null &&
                    task.description!.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    task.description!,
                    style: context.texts.bodySmall?.copyWith(height: 1.45),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.person_outline, size: 13, color: palette.faint),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        assignee,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.texts.labelSmall,
                      ),
                    ),
                    if (!done && onAssign != null)
                      PopupMenuButton<String>(
                        tooltip: 'Reassign',
                        onSelected: onAssign,
                        itemBuilder: (menuContext) => [
                          const PopupMenuItem(
                            value: '',
                            child: Text('Unassigned'),
                          ),
                          for (final person in people)
                            PopupMenuItem(
                              value: person.id,
                              child: Text(person.name),
                            ),
                        ],
                        child: Row(
                          children: [
                            Text(
                              'Reassign',
                              style: context.texts.labelSmall
                                  ?.copyWith(color: palette.ember),
                            ),
                            Icon(
                              Icons.arrow_drop_down,
                              size: 16,
                              color: palette.ember,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
