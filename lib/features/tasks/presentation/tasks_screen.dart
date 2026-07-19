import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/theme_engine_provider.dart';
import '../../../core/theme/theme_palettes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/local/database.dart';
import '../application/task_providers.dart';
import '../../quick_add/application/quick_add_provider.dart';
import '../domain/task_sort_option.dart';
import 'package:ephemeron/presentation/widgets/glassmorphic_wrapper.dart';
import '../../../presentation/widgets/confirmation_dialog.dart';
import '../../../presentation/widgets/recurrence_delete_dialog.dart';
import '../domain/task_recurrence.dart';
import 'package:drift/drift.dart' show Value;
import 'package:ephemeron/core/widgets/app_loading_indicator.dart';

class TasksScreen extends ConsumerStatefulWidget {
  const TasksScreen({super.key});

  @override
  ConsumerState<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends ConsumerState<TasksScreen> {
  @override
  Widget build(BuildContext context) {
    final listsAsync = ref.watch(listsProvider);
    final customSmartListsAsync = ref.watch(customSmartListsProvider);
    final tagsAsync = ref.watch(allTagsProvider);
    final palette = ref.watch(themeEngineProvider);
    final sortOption = ref.watch(taskSortOptionProvider);
    final selectedListId = ref.watch(selectedListIdProvider);

    final lists = listsAsync.value ?? [];
    final customSmartLists = customSmartListsAsync.value ?? [];
    final tags = tagsAsync.value ?? [];

    final TaskList? defaultInbox = lists.isEmpty 
        ? null 
        : lists.firstWhere((l) => l.isInbox, orElse: () => lists.first);
    final defaultInboxId = defaultInbox?.id ?? '';
    final currentId = selectedListId ?? defaultInboxId;
    final currentListName = _getCurrentListName(lists, customSmartLists, currentId);

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Theme(
          data: Theme.of(context).copyWith(
            popupMenuTheme: PopupMenuThemeData(
              color: palette.surface.withValues(alpha: 0.95),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              textStyle: TextStyle(color: palette.text),
            ),
          ),
          child: PopupMenuButton<String>(
            onSelected: (id) {
              if (id == '__new__') {
                _createList(context, palette);
              } else if (id == '__new_smart__') {
                _createSmartList(context, palette, tags);
              } else {
                ref.read(selectedListIdProvider.notifier).state = id;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem<String>(
                enabled: false,
                child: Text('SMART LISTS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
              ),
              _buildSmartMenuItem('smart:today', 'Today', Icons.today_rounded, palette, currentId),
              _buildSmartMenuItem('smart:tomorrow', 'Tomorrow', Icons.wb_sunny_rounded, palette, currentId),
              _buildSmartMenuItem('smart:next7Days', 'Next 7 Days', Icons.calendar_month_rounded, palette, currentId),
              _buildSmartMenuItem('smart:completed', 'Completed', Icons.check_circle_outline_rounded, palette, currentId),
              _buildSmartMenuItem('smart:trash', 'Trash', Icons.delete_outline_rounded, palette, currentId),
              _buildSmartMenuItem('smart:wontDo', "Won't Do", Icons.block_rounded, palette, currentId),

              if (customSmartLists.isNotEmpty) ...[
                const PopupMenuDivider(),
                const PopupMenuItem<String>(
                  enabled: false,
                  child: Text('CUSTOM SMART LISTS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                ),
                for (final item in customSmartLists) ...[
                  (() {
                    final val = 'custom_smart:${item.id}';
                    final isSelected = val == currentId;
                    return PopupMenuItem<String>(
                      value: val,
                      child: Row(
                        children: [
                          Icon(Icons.filter_list_rounded, color: isSelected ? palette.primary : _parseColor(item.colorHex), size: 20),
                          const SizedBox(width: 8),
                          Text(
                            item.name,
                            style: TextStyle(
                              color: palette.text,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                          if (isSelected) ...[
                            const Spacer(),
                            Icon(Icons.check, color: palette.primary, size: 16),
                          ],
                        ],
                      ),
                    );
                  }()),
                ],
              ],

              const PopupMenuDivider(),
              const PopupMenuItem<String>(
                enabled: false,
                child: Text('LISTS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
              ),
              for (final list in lists) ...[
                (() {
                  final isSelected = list.id == currentId;
                  return PopupMenuItem<String>(
                    value: list.id,
                    child: Row(
                      children: [
                        Icon(
                          list.isInbox ? Icons.inbox_rounded : Icons.list_rounded,
                          color: isSelected ? palette.primary : (list.isInbox ? palette.primary.withValues(alpha: 0.5) : _parseColor(list.colorHex)),
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          list.name,
                          style: TextStyle(
                            color: palette.text,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        if (isSelected) ...[
                          const Spacer(),
                          Icon(Icons.check, color: palette.primary, size: 16),
                        ],
                      ],
                    ),
                  );
                }()),
              ],

              const PopupMenuDivider(),
              PopupMenuItem<String>(
                value: '__new__',
                child: Row(
                  children: [
                    Icon(Icons.add, color: palette.primary, size: 20),
                    const SizedBox(width: 8),
                    Text('New list...', style: TextStyle(color: palette.primary, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: '__new_smart__',
                child: Row(
                  children: [
                    Icon(Icons.filter_alt_outlined, color: palette.primary, size: 20),
                    const SizedBox(width: 8),
                    Text('New smart list...', style: TextStyle(color: palette.primary, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  currentListName,
                  style: TextStyle(color: palette.text, fontWeight: FontWeight.bold, fontSize: 24),
                ),
                Icon(Icons.keyboard_arrow_down, color: palette.text.withValues(alpha: 0.6)),
              ],
            ),
          ),
        ),
        actions: [
          if (currentId.startsWith('custom_smart:'))
            IconButton(
              icon: Icon(Icons.delete_sweep_outlined, color: Colors.redAccent.withValues(alpha: 0.8)),
              tooltip: 'Delete smart list',
              onPressed: () async {
                final confirm = await showConfirmationDialog(
                  context: context,
                  ref: ref,
                  title: 'Delete Smart List?',
                  content: 'Are you sure you want to delete this custom smart list?',
                  confirmLabel: 'Delete',
                  isDestructive: true,
                );
                if (confirm) {
                  final id = currentId.substring(13);
                  await ref.read(taskRepositoryProvider).deleteCustomSmartList(id);
                  ref.read(selectedListIdProvider.notifier).state = null; // Reset to default (Inbox)
                }
              },
            ),
          const SizedBox(width: 8),
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
          final currentId = selectedListId ?? lists.firstWhere((l) => l.isInbox, orElse: () => lists.first).id;
          return _TaskListView(listId: currentId, palette: palette);
        },
        loading: () => const Center(child: AppLoadingIndicator()),
        error: (error, _) => Center(
          child: Text('Could not load lists: $error', style: TextStyle(color: palette.text)),
        ),
      ),
    );
  }

  String _getCurrentListName(List<TaskList> lists, List<CustomSmartList> customSmartLists, String currentId) {
    if (currentId.startsWith('smart:')) {
      final typeStr = currentId.substring(6);
      return switch (typeStr) {
        'today' => 'Today',
        'tomorrow' => 'Tomorrow',
        'next7Days' => 'Next 7 Days',
        'completed' => 'Completed',
        'trash' => 'Trash',
        'wontDo' => "Won't Do",
        _ => typeStr,
      };
    }
    if (currentId.startsWith('custom_smart:')) {
      final id = currentId.substring(13);
      final CustomSmartList? customList = customSmartLists.isEmpty
          ? null
          : customSmartLists.firstWhere(
              (s) => s.id == id,
              orElse: () => null as dynamic,
            );
      return customList?.name ?? 'Smart List';
    }
    final TaskList? list = lists.isEmpty
        ? null
        : lists.firstWhere(
            (l) => l.id == currentId,
            orElse: () => null as dynamic,
          );
    return list?.name ?? 'Tasks';
  }

  PopupMenuItem<String> _buildSmartMenuItem(String value, String name, IconData icon, AppPalette palette, String currentId) {
    final isSelected = value == currentId;
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(icon, color: isSelected ? palette.primary : palette.text.withValues(alpha: 0.5), size: 20),
          const SizedBox(width: 8),
          Text(
            name,
            style: TextStyle(
              color: palette.text,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          if (isSelected) ...[
            const Spacer(),
            Icon(Icons.check, color: palette.primary, size: 16),
          ],
        ],
      ),
    );
  }

  Color _parseColor(String hex) {
    try {
      final c = hex.replaceAll('#', '');
      return Color(int.parse('FF$c', radix: 16));
    } catch (_) {
      return const Color(0xFF1B4B4A);
    }
  }

  Future<void> _createSmartList(BuildContext context, AppPalette palette, List<Tag> tags) async {
    final nameController = TextEditingController();
    String? selectedDateFilter;
    int? selectedMinPriority;
    String? selectedTagId;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: palette.surface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Text('New Smart List', style: TextStyle(color: palette.text, fontWeight: FontWeight.bold)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: nameController,
                      autofocus: true,
                      style: TextStyle(color: palette.text),
                      decoration: InputDecoration(
                        hintText: 'Smart list name',
                        hintStyle: TextStyle(color: palette.text.withValues(alpha: 0.5)),
                        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: palette.text.withValues(alpha: 0.2))),
                        focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: palette.primary)),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text('Date Filter', style: TextStyle(color: palette.text.withValues(alpha: 0.7), fontSize: 13, fontWeight: FontWeight.bold)),
                    DropdownButton<String?>(
                      value: selectedDateFilter,
                      dropdownColor: palette.surface,
                      style: TextStyle(color: palette.text),
                      isExpanded: true,
                      underline: Container(height: 1, color: palette.text.withValues(alpha: 0.2)),
                      items: const [
                        DropdownMenuItem(value: null, child: Text('Any Time')),
                        DropdownMenuItem(value: 'today', child: Text('Today')),
                        DropdownMenuItem(value: 'tomorrow', child: Text('Tomorrow')),
                        DropdownMenuItem(value: 'thisWeek', child: Text('This Week')),
                        DropdownMenuItem(value: 'next7Days', child: Text('Next 7 Days')),
                      ],
                      onChanged: (val) => setDialogState(() => selectedDateFilter = val),
                    ),
                    const SizedBox(height: 16),
                    Text('Priority Filter', style: TextStyle(color: palette.text.withValues(alpha: 0.7), fontSize: 13, fontWeight: FontWeight.bold)),
                    DropdownButton<int?>(
                      value: selectedMinPriority,
                      dropdownColor: palette.surface,
                      style: TextStyle(color: palette.text),
                      isExpanded: true,
                      underline: Container(height: 1, color: palette.text.withValues(alpha: 0.2)),
                      items: const [
                        DropdownMenuItem(value: null, child: Text('Any Priority')),
                        DropdownMenuItem(value: 3, child: Text('High Only')),
                        DropdownMenuItem(value: 2, child: Text('Medium & High')),
                      ],
                      onChanged: (val) => setDialogState(() => selectedMinPriority = val),
                    ),
                    const SizedBox(height: 16),
                    Text('Tag Filter', style: TextStyle(color: palette.text.withValues(alpha: 0.7), fontSize: 13, fontWeight: FontWeight.bold)),
                    DropdownButton<String?>(
                      value: selectedTagId,
                      dropdownColor: palette.surface,
                      style: TextStyle(color: palette.text),
                      isExpanded: true,
                      underline: Container(height: 1, color: palette.text.withValues(alpha: 0.2)),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('Any Tag')),
                        for (final tag in tags)
                          DropdownMenuItem(value: tag.id, child: Text('#${tag.name}')),
                      ],
                      onChanged: (val) => setDialogState(() => selectedTagId = val),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text('Cancel', style: TextStyle(color: palette.text.withValues(alpha: 0.6))),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: palette.primary,
                    foregroundColor: palette.background,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    if (nameController.text.trim().isEmpty) return;
                    Navigator.pop(context, true);
                  },
                  child: const Text('Create'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == true && nameController.text.trim().isNotEmpty && context.mounted) {
      final name = nameController.text.trim();
      final smartList = await ref.read(taskRepositoryProvider).createCustomSmartList(
        name: name,
        dateFilter: selectedDateFilter,
        minPriority: selectedMinPriority,
        tagId: selectedTagId,
      );
      ref.read(selectedListIdProvider.notifier).state = 'custom_smart:${smartList.id}';
    }
  }

  Future<void> _createList(BuildContext context, AppPalette palette) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: palette.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
    ref.read(selectedListIdProvider.notifier).state = list.id;
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
            final showDirectly = listId == 'smart:completed' || listId == 'smart:trash' || listId == 'smart:wontDo';

            if (showDirectly) {
              final tasksToShow = completedTasks.isNotEmpty ? completedTasks : pendingTasks;
              if (tasksToShow.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_outline, size: 64, color: palette.text.withValues(alpha: 0.1)),
                      const SizedBox(height: 16),
                      Text(
                        'No tasks found',
                        style: TextStyle(color: palette.text.withValues(alpha: 0.5), fontSize: 16),
                      ),
                    ],
                  ),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: tasksToShow.length,
                itemBuilder: (context, index) {
                  final task = tasksToShow[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: RepaintBoundary(child: _TaskTile(task: task, palette: palette)),
                  );
                },
              );
            }

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
                ),
              );
            }

            return CustomScrollView(
              slivers: [
                if (pendingTasks.isNotEmpty) ...[
                  // ── Drag and Drop Reorderable List ──
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    sliver: SliverReorderableList(
                      itemCount: pendingTasks.length,
                      onReorder: (oldIdx, newIdx) async { // ignore: deprecated_member_use
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
                        return ReorderableDelayedDragStartListener(
                          key: ValueKey(task.id),
                          index: index,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: RepaintBoundary(child: _TaskTile(task: task, palette: palette)),
                          ),
                        );
                      },
                    ),
                  ),
                ],
                if (completedTasks.isNotEmpty) ...[
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    sliver: SliverToBoxAdapter(
                      child: Theme(
                        data: Theme.of(context).copyWith(
                          dividerColor: Colors.transparent,
                          expansionTileTheme: ExpansionTileThemeData(
                            textColor: palette.primary,
                            iconColor: palette.primary,
                            collapsedIconColor: palette.text.withValues(alpha: 0.5),
                          ),
                        ),
                        child: Material(
                          color: Colors.transparent,
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
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
          loading: () => const Center(child: AppLoadingIndicator()),
          error: (error, _) => Center(child: Text('Could not load completed tasks: $error', style: TextStyle(color: palette.text))),
        );
      },
      loading: () => const Center(child: AppLoadingIndicator()),
      error: (error, _) => Center(child: Text('Could not load tasks: $error', style: TextStyle(color: palette.text))),
    );
  }
}

class _TaskTile extends ConsumerWidget {
  const _TaskTile({required this.task, required this.palette});

  final Task task;
  final AppPalette palette;

  Color _parseColor(String hex) {
    try {
      final c = hex.replaceAll('#', '');
      return Color(int.parse('FF$c', radix: 16));
    } catch (_) {
      return const Color(0xFF1B4B4A);
    }
  }

  String _formatDuration(int minutes) {
    if (minutes < 60) return '${minutes}m';
    final hours = minutes / 60.0;
    if (hours == hours.toInt()) {
      return '${hours.toInt()}h';
    }
    return '${hours.toStringAsFixed(1)}h';
  }

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

    final tagsAsync = ref.watch(taskTagsProvider(task.id));
    final tags = tagsAsync.value ?? [];

    Color borderColor = palette.text.withValues(alpha: 0.05);
    double borderWidth = 1.0;
    if (tags.isNotEmpty && !isLate) {
      borderColor = _parseColor(tags.first.colorHex);
      borderWidth = 2.0;
    }

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
      confirmDismiss: (direction) async {
        final recurrence = TaskRecurrence.decode(task.recurrenceRule);
        if (recurrence.isRecurring) {
          final choice = await showRecurrenceDeleteDialog(
            context: context,
            ref: ref,
            title: 'Delete Recurring Task?',
          );
          if (choice == null) return false;

          if (choice == RecurrenceDeleteType.onlyThis) {
            final nextDue = recurrence.nextOccurrence(task.dueDate!);
            if (nextDue != null) {
              await repo.updateTask(task.id, dueDate: Value(nextDue));
            }
            return false;
          } else {
            return true;
          }
        } else {
          return await showConfirmationDialog(
            context: context,
            ref: ref,
            title: 'Delete Task?',
            content: 'Are you sure you want to delete this task? It will be moved to Trash.',
            confirmLabel: 'Delete',
            isDestructive: true,
          );
        }
      },
      onDismissed: (_) => repo.softDeleteTask(task.id),
      child: Container(
        decoration: BoxDecoration(
          color: palette.surface.withValues(alpha: palette.isAmoled ? 1.0 : 0.6),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor, width: borderWidth),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: GlassmorphicWrapper(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Material(
              color: Colors.transparent,
              child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              leading: GestureDetector(
                onTap: () {
                  if (task.isWontDo) {
                    repo.toggleWontDo(task.id);
                  } else {
                    if (task.isCompleted) {
                      repo.uncompleteTask(task.id);
                    } else {
                      repo.completeTask(task.id);
                    }
                  }
                },
                child: task.isWontDo
                    ? Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.redAccent.withValues(alpha: 0.2),
                        ),
                        child: const Icon(Icons.block, size: 16, color: Colors.redAccent),
                      )
                    : Container(
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
                  color: task.isCompleted
                      ? palette.text.withValues(alpha: 0.4)
                      : task.isWontDo
                          ? palette.text.withValues(alpha: 0.45)
                          : palette.text,
                  fontWeight: FontWeight.w600,
                  decoration: (task.isCompleted || task.isWontDo) ? TextDecoration.lineThrough : null,
                  decorationColor: palette.text.withValues(alpha: 0.45),
                ),
              ),
              subtitle: (task.dueDate != null || task.durationMinutes != 30)
                  ? Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Row(
                        children: [
                          if (task.dueDate != null) ...[
                            Icon(
                              isLate ? Icons.warning_amber_rounded : Icons.calendar_today,
                              size: 12,
                              color: dueDateColor,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _formatDue(task.dueDate!, task.dueHasTime),
                              style: TextStyle(
                                color: dueDateColor,
                                fontSize: 12,
                                fontWeight: isLate ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                          ],
                          if (task.dueDate != null && task.durationMinutes != 30)
                            const SizedBox(width: 12),
                          if (task.durationMinutes != 30) ...[
                            Icon(Icons.hourglass_bottom_rounded, size: 12, color: palette.text.withValues(alpha: 0.5)),
                            const SizedBox(width: 4),
                            Text(
                              _formatDuration(task.durationMinutes),
                              style: TextStyle(color: palette.text.withValues(alpha: 0.5), fontSize: 12),
                            ),
                          ],
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
              onTap: () => ref.read(quickAddProvider.notifier).expand(task),
            ),
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
