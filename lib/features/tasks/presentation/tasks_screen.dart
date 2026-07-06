import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/theme/theme_engine_provider.dart';
import '../../../core/theme/theme_palettes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/local/database.dart';
import '../application/task_providers.dart';
import 'task_form_sheet.dart';

class TasksScreen extends ConsumerStatefulWidget {
  const TasksScreen({super.key});

  @override
  ConsumerState<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends ConsumerState<TasksScreen> {
  String? _selectedListId;

  @override
  Widget build(BuildContext context) {
    final listsAsync = ref.watch(listsProvider);
    final palette = ref.watch(themeEngineProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: listsAsync.when(
          data: (lists) {
            final current = _currentList(lists);
            return Theme(
              data: Theme.of(context).copyWith(
                popupMenuTheme: PopupMenuThemeData(
                  color: palette.surface.withValues(alpha: 0.9),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  textStyle: TextStyle(color: palette.text),
                ),
              ),
              child: PopupMenuButton<String>(
                onSelected: (id) {
                  if (id == '__new__') {
                    _createList(context, palette);
                  } else {
                    setState(() => _selectedListId = id);
                  }
                },
                itemBuilder: (context) => [
                  for (final list in lists)
                    PopupMenuItem(
                      value: list.id,
                      child: Text(list.name, style: TextStyle(color: palette.text)),
                    ),
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: '__new__',
                    child: Row(
                      children: [
                        Icon(Icons.add, color: palette.primary, size: 20),
                        const SizedBox(width: 8),
                        Text('New list...', style: TextStyle(color: palette.primary, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ],
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      current?.name ?? 'Tasks',
                      style: TextStyle(color: palette.text, fontWeight: FontWeight.bold, fontSize: 24),
                    ),
                    Icon(Icons.keyboard_arrow_down, color: palette.text.withValues(alpha: 0.6)),
                  ],
                ),
              ),
            );
          },
          loading: () => Text('Tasks', style: TextStyle(color: palette.text, fontWeight: FontWeight.bold, fontSize: 24)),
          error: (_, __) => Text('Tasks', style: TextStyle(color: palette.text, fontWeight: FontWeight.bold, fontSize: 24)),
        ),
      ),
      body: listsAsync.when(
        data: (lists) {
          final current = _currentList(lists);
          if (current == null) {
            return Center(child: CircularProgressIndicator(color: palette.primary));
          }
          return _TaskListView(listId: current.id, palette: palette);
        },
        loading: () => Center(child: CircularProgressIndicator(color: palette.primary)),
        error: (error, _) => Center(
          child: Text('Could not load lists: $error', style: TextStyle(color: palette.text)),
        ),
      ),
    );
  }

  TaskList? _currentList(List<TaskList> lists) {
    if (lists.isEmpty) return null;
    if (_selectedListId == null) {
      return lists.firstWhere((l) => l.isInbox, orElse: () => lists.first);
    }
    return lists.firstWhere(
      (l) => l.id == _selectedListId,
      orElse: () => lists.first,
    );
  }

  Future<void> _createList(BuildContext context, AppPalette palette) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: palette.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('New list', style: TextStyle(color: palette.text, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: palette.text),
          decoration: InputDecoration(
            hintText: 'List name',
            hintStyle: TextStyle(color: palette.text.withValues(alpha: 0.5)),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: palette.text.withValues(alpha: 0.2))),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: palette.primary)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: palette.text.withValues(alpha: 0.6))),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: palette.primary,
              foregroundColor: palette.background,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !context.mounted) return;
    final list = await ref.read(taskRepositoryProvider).createList(name: name);
    setState(() => _selectedListId = list.id);
  }
}

class _TaskListView extends ConsumerWidget {
  const _TaskListView({required this.listId, required this.palette});

  final String listId;
  final AppPalette palette;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsync = ref.watch(tasksInListProvider(listId));

    return tasksAsync.when(
      data: (tasks) {
        if (tasks.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle_outline, size: 64, color: palette.text.withValues(alpha: 0.1)),
                const SizedBox(height: 16),
                Text(
                  'No tasks yet',
                  style: TextStyle(color: palette.text.withValues(alpha: 0.5), fontSize: 16),
                ),
              ],
            ).animate().fadeIn(),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          itemCount: tasks.length,
          itemBuilder: (context, index) => Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: _TaskTile(task: tasks[index], palette: palette).animate().fadeIn(delay: (index * 40).ms).slideX(begin: 0.1),
          ),
        );
      },
      loading: () => Center(child: CircularProgressIndicator(color: palette.primary)),
      error: (error, _) => Center(child: Text('Could not load tasks: $error', style: TextStyle(color: palette.text))),
    );
  }
}

class _TaskTile extends ConsumerWidget {
  const _TaskTile({required this.task, required this.palette});

  final Task task;
  final AppPalette palette;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(taskRepositoryProvider);
    final priorityColor = switch (task.priority) {
      3 => AppColors.priorityHigh,
      2 => AppColors.priorityMedium,
      1 => AppColors.priorityLow,
      _ => palette.text.withValues(alpha: 0.2),
    };

    return Dismissible(
      key: ValueKey(task.id),
      direction: DismissDirection.endToStart,
      background: Container(
        decoration: BoxDecoration(
          color: Colors.red.shade900,
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      onDismissed: (_) => repo.softDeleteTask(task.id),
      child: Container(
        decoration: BoxDecoration(
          color: palette.surface.withValues(alpha: palette.isAmoled ? 1.0 : 0.6),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: palette.text.withValues(alpha: 0.05)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              leading: GestureDetector(
                onTap: () {
                  if (task.isCompleted) {
                    repo.uncompleteTask(task.id);
                  } else {
                    repo.completeTask(task.id);
                  }
                },
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: task.isCompleted ? palette.text.withValues(alpha: 0.3) : priorityColor,
                      width: 2,
                    ),
                    color: task.isCompleted ? palette.text.withValues(alpha: 0.3) : Colors.transparent,
                  ),
                  child: task.isCompleted
                      ? Icon(Icons.check, size: 16, color: palette.background)
                      : null,
                ),
              ),
              title: Text(
                task.title,
                style: TextStyle(
                  color: task.isCompleted ? palette.text.withValues(alpha: 0.4) : palette.text,
                  fontWeight: FontWeight.w600,
                  decoration: task.isCompleted ? TextDecoration.lineThrough : null,
                  decorationColor: palette.text.withValues(alpha: 0.4),
                ),
              ),
              subtitle: task.dueDate != null
                  ? Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Row(
                        children: [
                          Icon(Icons.calendar_today, size: 12, color: palette.text.withValues(alpha: 0.5)),
                          const SizedBox(width: 4),
                          Text(
                            _formatDue(task.dueDate!, task.dueHasTime),
                            style: TextStyle(
                              color: palette.text.withValues(alpha: 0.5),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    )
                  : null,
              trailing: IconButton(
                icon: Icon(
                  task.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                  color: task.isPinned ? palette.primary : palette.text.withValues(alpha: 0.3),
                  size: 20,
                ),
                onPressed: () => repo.togglePin(task.id),
              ),
              onTap: () => showTaskFormSheet(context, listId: task.listId, existingTask: task),
            ),
          ),
        ),
      ),
    );
  }

  String _formatDue(DateTime due, bool hasTime) {
    final localDue = due.toLocal();
    final date =
        '${localDue.year}-${localDue.month.toString().padLeft(2, '0')}-'
        '${localDue.day.toString().padLeft(2, '0')}';
    if (!hasTime) return date;
    return '$date ${localDue.hour.toString().padLeft(2, '0')}:'
        '${localDue.minute.toString().padLeft(2, '0')}';
  }
}
