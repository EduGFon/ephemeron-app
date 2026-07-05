import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

    return Scaffold(
      appBar: AppBar(
        title: listsAsync.when(
          data: (lists) {
            final current = _currentList(lists);
            return PopupMenuButton<String>(
              onSelected: (id) {
                if (id == '__new__') {
                  _createList(context);
                } else {
                  setState(() => _selectedListId = id);
                }
              },
              itemBuilder: (context) => [
                for (final list in lists)
                  PopupMenuItem(value: list.id, child: Text(list.name)),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: '__new__',
                  child: Text('New list...'),
                ),
              ],
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(current?.name ?? 'Tasks'),
                  const Icon(Icons.arrow_drop_down),
                ],
              ),
            );
          },
          loading: () => const Text('Tasks'),
          error: (_, __) => const Text('Tasks'),
        ),
      ),
      // No per-screen FAB — Step 5 moved task/event creation to a single
      // global "+" in AppShell, shown on this and the Calendar/Matrix
      // sections. Editing an existing task still opens the fuller
      // TaskFormSheet directly via _TaskTile.onTap below, since the
      // quick-add sheet is create-only.
      body: listsAsync.when(
        data: (lists) {
          final current = _currentList(lists);
          if (current == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return _TaskListView(listId: current.id);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            Center(child: Text('Could not load lists: $error')),
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

  Future<void> _createList(BuildContext context) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New list'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
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
  const _TaskListView({required this.listId});

  final String listId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsync = ref.watch(tasksInListProvider(listId));

    return tasksAsync.when(
      data: (tasks) {
        if (tasks.isEmpty) {
          return Center(
            child: Text(
              'No tasks yet',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          );
        }
        return ListView.builder(
          itemCount: tasks.length,
          itemBuilder: (context, index) => _TaskTile(task: tasks[index]),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('Could not load tasks: $error')),
    );
  }
}

class _TaskTile extends ConsumerWidget {
  const _TaskTile({required this.task});

  final Task task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(taskRepositoryProvider);
    final priorityColor = switch (task.priority) {
      3 => AppColors.priorityHigh,
      2 => AppColors.priorityMedium,
      1 => AppColors.priorityLow,
      _ => AppColors.priorityNone,
    };

    return Dismissible(
      key: ValueKey(task.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Theme.of(context).colorScheme.error,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      onDismissed: (_) => repo.softDeleteTask(task.id),
      child: ListTile(
        leading: Checkbox(
          value: task.isCompleted,
          onChanged: (checked) {
            if (checked == true) {
              repo.completeTask(task.id);
            } else {
              repo.uncompleteTask(task.id);
            }
          },
        ),
        title: Text(
          task.title,
          style: task.isCompleted
              ? const TextStyle(decoration: TextDecoration.lineThrough)
              : null,
        ),
        subtitle: task.dueDate != null
            ? Text(_formatDue(task.dueDate!, task.dueHasTime))
            : null,
        leadingAndTrailingTextStyle: TextStyle(color: priorityColor),
        trailing: IconButton(
          icon: Icon(task.isPinned ? Icons.push_pin : Icons.push_pin_outlined),
          onPressed: () => repo.togglePin(task.id),
        ),
        onTap: () =>
            showTaskFormSheet(context, listId: task.listId, existingTask: task),
      ),
    );
  }

  String _formatDue(DateTime due, bool hasTime) {
    final date =
        '${due.year}-${due.month.toString().padLeft(2, '0')}-'
        '${due.day.toString().padLeft(2, '0')}';
    if (!hasTime) return date;
    return '$date ${due.hour.toString().padLeft(2, '0')}:'
        '${due.minute.toString().padLeft(2, '0')}';
  }
}
