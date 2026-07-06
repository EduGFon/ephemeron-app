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
    final sortOption = ref.watch(taskSortOptionProvider);

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
        actions: [
          // ── Hamburger Sort/Order Menu ──
          Theme(
            data: Theme.of(context).copyWith(
              popupMenuTheme: PopupMenuThemeData(
                color: palette.surface.withValues(alpha: 0.95),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                textStyle: TextStyle(color: palette.text),
              ),
            ),
            child: PopupMenuButton<TaskSortOption>(
              icon: Icon(Icons.menu, color: palette.text),
              tooltip: 'Sorting options',
              onSelected: (option) {
                ref.read(taskSortOptionProvider.notifier).setSortOption(option);
              },
              itemBuilder: (context) => [
                for (final opt in TaskSortOption.values)
                  PopupMenuItem(
                    value: opt,
                    child: Row(
                      children: [
                        Icon(
                          opt == sortOption ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                          color: opt == sortOption ? palette.primary : palette.text.withValues(alpha: 0.4),
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Text(opt.label, style: TextStyle(color: palette.text, fontSize: 14)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
        ],
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
    final pendingAsync = ref.watch(pendingTasksInListProvider(listId));
    final completedAsync = ref.watch(completedTasksInListProvider(listId));

    return pendingAsync.when(
      data: (pendingTasks) {
        return completedAsync.when(
          data: (completedTasks) {
            if (pendingTasks.isEmpty && completedTasks.isEmpty) {
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

            return ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                if (pendingTasks.isNotEmpty) ...[
                  // ── Drag and Drop Reorderable List ──
                  ReorderableListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: pendingTasks.length,
                    onReorder: (oldIdx, newIdx) async {
                      if (oldIdx < newIdx) {
                        newIdx -= 1;
                      }
                      final mutableList = List<Task>.from(pendingTasks);
                      final item = mutableList.removeAt(oldIdx);
                      mutableList.insert(newIdx, item);

                      // Update provider sort option to custom
                      ref.read(taskSortOptionProvider.notifier).setSortOption(TaskSortOption.custom);
                      
                      // Save custom sort order in database
                      final ids = mutableList.map((t) => t.id).toList();
                      await ref.read(taskRepositoryProvider).updateTaskSortOrders(ids);
                    },
                    itemBuilder: (context, index) {
                      final task = pendingTasks[index];
                      return Padding(
                        key: ValueKey(task.id),
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: _TaskTile(task: task, palette: palette),
                      );
                    },
                  ),
                ],
                if (completedTasks.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  // ── Expandable Completed Section ──
                  Theme(
                    data: Theme.of(context).copyWith(
                      dividerColor: Colors.transparent,
                      expansionTileTheme: ExpansionTileThemeData(
                        textColor: palette.primary,
                        iconColor: palette.primary,
                        collapsedIconColor: palette.text.withValues(alpha: 0.5),
                      ),
                    ),
                    child: ExpansionTile(
                      title: Text(
                        'Completed (${completedTasks.length})',
                        style: TextStyle(
                          color: palette.text.withValues(alpha: 0.6),
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      childrenPadding: EdgeInsets.zero,
                      children: [
                        for (final task in completedTasks)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: _TaskTile(task: task, palette: palette),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            );
          },
          loading: () => Center(child: CircularProgressIndicator(color: palette.primary)),
          error: (error, _) => Center(child: Text('Could not load completed tasks: $error', style: TextStyle(color: palette.text))),
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

    final isLate = !task.isCompleted && task.dueDate != null && task.dueDate!.isBefore(DateTime.now());
    final dueDateColor = isLate ? Colors.redAccent : palette.text.withValues(alpha: 0.5);

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
                          Icon(
                            isLate ? Icons.warning_amber_rounded : Icons.calendar_today,
                            size: 12,
                            color: dueDateColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _formatDue(task.dueDate!, task.dueHasTime) + (isLate ? ' (Overdue)' : ''),
                            style: TextStyle(
                              color: dueDateColor,
                              fontSize: 12,
                              fontWeight: isLate ? FontWeight.bold : FontWeight.normal,
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
