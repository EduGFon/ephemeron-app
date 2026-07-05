import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/database.dart';
import '../../calendar/application/calendar_providers.dart';
import '../../calendar/data/calendar_repository.dart';
import '../../calendar/domain/calendar_event.dart';
import '../../tasks/application/task_providers.dart';
import '../../tasks/data/task_repository.dart';
import '../domain/quick_add_parser.dart';

enum QuickAddTarget { task, event }

Future<void> showQuickAddSheet(BuildContext context, {DateTime? initialDay}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (context, animation, secondaryAnimation) {
      return Center(
        child: SingleChildScrollView(
          child: Material(
            color: Colors.transparent,
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: QuickAddSheet(initialDay: initialDay),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curve = CurvedAnimation(parent: animation, curve: Curves.easeOutBack);
      return ScaleTransition(
        scale: curve,
        child: FadeTransition(
          opacity: animation,
          child: child,
        ),
      );
    },
  );
}

/// The single "+" entry point for Tasks, Calendar, and (once built)
/// Matrix — matches the brainstorm's "Create button on task related
/// sections (Lists, Calendar, Matrix)" behavior, where the same sheet
/// covers all three rather than each screen having its own disconnected
/// add flow. This intentionally does NOT yet cover the full rich
/// version from the brainstorm (audio recording, templates, attachments,
/// full-screen expand) — those are still open, scoped-out future work;
/// this step's job was specifically unifying Task/Event creation behind
/// one button and adding the shorthand parser.
class QuickAddSheet extends ConsumerStatefulWidget {
  const QuickAddSheet({this.initialDay, super.key});

  final DateTime? initialDay;

  @override
  ConsumerState<QuickAddSheet> createState() => _QuickAddSheetState();
}

class _QuickAddSheetState extends ConsumerState<QuickAddSheet> {
  final _titleController = TextEditingController();
  QuickAddTarget _target = QuickAddTarget.task;
  QuickAddParseResult _parsed = QuickAddParser.parse('');
  DateTime? _dueDate;
  bool _dueHasTime = false;
  bool _isSaving = false;

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  void _onTitleChanged(String value) {
    setState(() => _parsed = QuickAddParser.parse(value));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      constraints: const BoxConstraints(maxWidth: 500),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<QuickAddTarget>(
            segments: const [
              ButtonSegment(
                value: QuickAddTarget.task,
                label: Text('Task'),
                icon: Icon(Icons.checklist_outlined),
              ),
              ButtonSegment(
                value: QuickAddTarget.event,
                label: Text('Event'),
                icon: Icon(Icons.calendar_month_outlined),
              ),
            ],
            selected: {_target},
            onSelectionChanged: (selection) =>
                setState(() => _target = selection.first),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _titleController,
            autofocus: true,
            onChanged: _onTitleChanged,
            decoration: const InputDecoration(
              labelText: 'Title',
              hintText: 'take meds #health ~personal -p4',
            ),
            textCapitalization: TextCapitalization.sentences,
          ),
          if (_parsed.tagName != null ||
              _parsed.listName != null ||
              _parsed.priority != null) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                if (_parsed.tagName != null)
                  Chip(
                    avatar: const Icon(Icons.tag, size: 16),
                    label: Text(_parsed.tagName!),
                  ),
                if (_parsed.listName != null && _target == QuickAddTarget.task)
                  Chip(
                    avatar: const Icon(Icons.list, size: 16),
                    label: Text(_parsed.listName!),
                  ),
                if (_parsed.priority != null && _target == QuickAddTarget.task)
                  Chip(
                    avatar: const Icon(Icons.flag, size: 16),
                    label: Text(
                      ['None', 'Low', 'Medium', 'High'][_parsed.priority!],
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  _dueDate == null
                      ? (_target == QuickAddTarget.event
                            ? 'Today, all day'
                            : 'No due date')
                      : _formatDate(_dueDate!, _dueHasTime),
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              TextButton(onPressed: _pickDate, child: const Text('Set date')),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _isSaving || _parsed.cleanTitle.isEmpty ? null : _save,
            child: _isSaving
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    _target == QuickAddTarget.task ? 'Add task' : 'Add event',
                  ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime d, bool hasTime) {
    final date =
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    if (!hasTime) return date;
    return '$date ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? widget.initialDay ?? now,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365 * 5)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now),
    );
    setState(() {
      _dueHasTime = time != null;
      _dueDate = time == null
          ? date
          : DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      if (_target == QuickAddTarget.task) {
        await _saveTask();
      } else {
        await _saveEvent();
      }
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _saveTask() async {
    final repo = ref.read(taskRepositoryProvider);
    final listId = await _resolveListId(repo);

    final task = await repo.createTask(
      listId: listId,
      title: _parsed.cleanTitle,
      priority: _parsed.priority ?? 0,
      dueDate: _dueDate,
      dueHasTime: _dueHasTime,
    );

    if (_parsed.tagName != null) {
      final tagId = await _resolveTagId(_parsed.tagName!);
      await repo.assignTag(task.id, tagId);
    }
  }

  Future<void> _saveEvent() async {
    try {
      final repo = ref.read(calendarRepositoryProvider);
      final start =
          _dueDate ??
          DateTime(
            widget.initialDay?.year ?? DateTime.now().year,
            widget.initialDay?.month ?? DateTime.now().month,
            widget.initialDay?.day ?? DateTime.now().day,
          );
      final isAllDay = !_dueHasTime;

      final event = await repo.createEvent(
        CalendarEvent(
          id: '',
          title: _parsed.cleanTitle,
          start: start,
          end: isAllDay ? start : start.add(const Duration(hours: 1)),
          isAllDay: isAllDay,
        ),
      );

      if (_parsed.tagName != null) {
        final tagId = await _resolveTagId(_parsed.tagName!);
        await repo.assignTag(event.id, tagId);
      }

      ref.invalidate(monthEventsProvider(DateTime(start.year, start.month, 1)));
    } on CalendarNotConnectedException catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Connect Google Calendar in Settings to create events.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not create event: $error')),
        );
      }
    }
  }

  Future<String> _resolveListId(TaskRepository repo) async {
    final lists = await ref.read(listsProvider.future);
    if (_parsed.listName == null) {
      return lists.firstWhere((l) => l.isInbox, orElse: () => lists.first).id;
    }
    final match = _firstWhereOrNull<TaskList>(
      lists,
      (l) => l.name.toLowerCase() == _parsed.listName!.toLowerCase(),
    );
    if (match != null) return match.id;
    final created = await repo.createList(name: _parsed.listName!);
    return created.id;
  }

  /// Tags are a single shared table (see EventTags/TaskTags's doc
  /// comments) — either repository creating one writes to the same
  /// place, so this always goes through TaskRepository for simplicity
  /// regardless of which target (Task/Event) is being created.
  Future<String> _resolveTagId(String name) async {
    final tags = await ref.read(allTagsProvider.future);
    final match = _firstWhereOrNull<Tag>(
      tags,
      (t) => t.name.toLowerCase() == name.toLowerCase(),
    );
    if (match != null) return match.id;
    final created = await ref
        .read(taskRepositoryProvider)
        .createTag(name: name);
    return created.id;
  }

  T? _firstWhereOrNull<T>(Iterable<T> items, bool Function(T) test) {
    for (final item in items) {
      if (test(item)) return item;
    }
    return null;
  }
}
