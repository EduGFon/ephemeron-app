import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/theme_engine_provider.dart';
import '../../../core/theme/theme_palettes.dart';
import '../../../data/local/database.dart';
import '../../tasks/application/task_providers.dart';
import '../../tasks/presentation/task_form_sheet.dart';
import '../application/matrix_providers.dart';
import '../domain/matrix_quadrant.dart';
import 'package:ephemeron/presentation/widgets/glassmorphic_wrapper.dart';
import 'package:ephemeron/core/widgets/app_loading_indicator.dart';

class MatrixScreen extends ConsumerWidget {
  const MatrixScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = ref.watch(themeEngineProvider);
    final sortOption = ref.watch(taskSortOptionProvider);
    final isLoaded = ref.watch(allActiveTasksProvider).hasValue;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Eisenhower Matrix', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
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
              icon: Icon(Icons.more_vert, color: palette.text),
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
      body: !isLoaded
          ? const Center(child: AppLoadingIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(child: _QuadrantWidget(quadrant: MatrixQuadrant.doFirst, palette: palette)),
                        const SizedBox(width: 16),
                        Expanded(child: _QuadrantWidget(quadrant: MatrixQuadrant.schedule, palette: palette)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(child: _QuadrantWidget(quadrant: MatrixQuadrant.delegate, palette: palette)),
                        const SizedBox(width: 16),
                        Expanded(child: _QuadrantWidget(quadrant: MatrixQuadrant.eliminate, palette: palette)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _QuadrantWidget extends ConsumerStatefulWidget {
  const _QuadrantWidget({required this.quadrant, required this.palette});

  final MatrixQuadrant quadrant;
  final AppPalette palette;

  @override
  ConsumerState<_QuadrantWidget> createState() => _QuadrantWidgetState();
}

class _QuadrantWidgetState extends ConsumerState<_QuadrantWidget> {
  @override
  Widget build(BuildContext context) {
    final pendingTasks = ref.watch(pendingMatrixTasksProvider(widget.quadrant));
    final completedTasks = ref.watch(completedMatrixTasksProvider(widget.quadrant));
    final color = widget.quadrant.color;
    final totalCount = pendingTasks.length + completedTasks.length;

    return Container(
      decoration: BoxDecoration(
        color: widget.palette.surface.withValues(alpha: widget.palette.isAmoled ? 1.0 : 0.5),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: color.withValues(alpha: 0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: GlassmorphicWrapper(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        widget.quadrant.label,
                        style: TextStyle(
                          color: color,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$totalCount',
                        style: TextStyle(color: color, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  widget.quadrant.description,
                  style: TextStyle(color: widget.palette.text.withValues(alpha: 0.6), fontSize: 12),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: (pendingTasks.isEmpty && completedTasks.isEmpty)
                      ? Center(
                          child: Icon(
                            Icons.task_alt,
                            color: color.withValues(alpha: 0.2),
                            size: 48,
                          ),
                        )
                      : ListView(
                          physics: const BouncingScrollPhysics(),
                          children: [
                            if (pendingTasks.isNotEmpty)
                              ReorderableListView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                buildDefaultDragHandles: false,
                                itemCount: pendingTasks.length,
                                onReorder: (oldIdx, newIdx) async { // ignore: deprecated_member_use
                                  if (oldIdx < newIdx) {
                                    newIdx -= 1;
                                  }
                                  final mutableList = List<Task>.from(pendingTasks);
                                  final item = mutableList.removeAt(oldIdx);
                                  mutableList.insert(newIdx, item);

                                  ref.read(taskSortOptionProvider.notifier).setSortOption(TaskSortOption.custom);
                                  
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
                                      child: _buildTaskRow(context, ref, task),
                                    ),
                                  );
                                },
                              ),
                            if (completedTasks.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Theme(
                                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                                child: ExpansionTile(
                                  title: Text(
                                    'Completed (${completedTasks.length})',
                                    style: TextStyle(
                                      color: widget.palette.text.withValues(alpha: 0.5),
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  trailing: const SizedBox.shrink(),
                                  tilePadding: EdgeInsets.zero,
                                  childrenPadding: EdgeInsets.zero,
                                  children: [
                                    for (final task in completedTasks)
                                      Padding(
                                        padding: const EdgeInsets.only(bottom: 8.0),
                                        child: _buildTaskRow(context, ref, task),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTaskRow(BuildContext context, WidgetRef ref, Task task) {
    final color = widget.quadrant.color;
    final isLate = !task.isCompleted && task.dueDate != null && task.dueDate!.isBefore(DateTime.now());
    final titleColor = isLate ? Colors.redAccent : (task.isCompleted ? widget.palette.text.withValues(alpha: 0.5) : widget.palette.text);
    final dueDateColor = isLate ? Colors.redAccent : widget.palette.text.withValues(alpha: 0.5);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () {
            final repo = ref.read(taskRepositoryProvider);
            if (task.isCompleted) {
              repo.uncompleteTask(task.id);
            } else {
              repo.completeTask(task.id);
            }
          },
          child: Container(
            width: 16,
            height: 16,
            margin: const EdgeInsets.only(top: 1, right: 8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: task.isCompleted ? widget.palette.text.withValues(alpha: 0.5) : (isLate ? Colors.redAccent : color.withValues(alpha: 0.8)), 
                width: 1.5,
              ),
              color: task.isCompleted ? widget.palette.text.withValues(alpha: 0.5) : Colors.transparent,
            ),
            child: task.isCompleted 
                ? Icon(Icons.check, size: 10, color: widget.palette.background)
                : null,
          ),
        ),
        Expanded(
          child: GestureDetector(
            onTap: () => showTaskFormSheet(
              context,
              listId: task.listId,
              existingTask: task,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  task.title,
                  style: TextStyle(
                    color: titleColor,
                    fontSize: 13,
                    fontWeight: isLate ? FontWeight.bold : FontWeight.normal,
                    decoration: task.isCompleted ? TextDecoration.lineThrough : null,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (task.dueDate != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2.0),
                    child: Row(
                      children: [
                        Icon(
                          isLate ? Icons.warning_amber_rounded : Icons.calendar_today,
                          size: 10,
                          color: dueDateColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _formatDue(task.dueDate!, task.dueHasTime),
                          style: TextStyle(
                            color: dueDateColor,
                            fontSize: 10,
                            fontWeight: isLate ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
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
