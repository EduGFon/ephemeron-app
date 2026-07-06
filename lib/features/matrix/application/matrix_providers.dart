import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/database.dart';
import '../../tasks/application/task_providers.dart';
import '../domain/matrix_quadrant.dart';

class ShowCompletedMatrixTasksNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;
}

final showCompletedMatrixTasksProvider = NotifierProvider<ShowCompletedMatrixTasksNotifier, bool>(() {
  return ShowCompletedMatrixTasksNotifier();
});

bool _isInQuadrant(Task task, MatrixQuadrant quadrant) {
  final now = DateTime.now();
  final endOfTomorrow = DateTime(now.year, now.month, now.day).add(const Duration(days: 2));

  // Priority: 0 (None), 1 (Low), 2 (Medium), 3 (High)
  final isImportant = task.priority >= 2;
  final isUrgent = task.dueDate != null && task.dueDate!.isBefore(endOfTomorrow);

  if (isImportant && isUrgent) {
    return quadrant == MatrixQuadrant.doFirst;
  } else if (isImportant && !isUrgent) {
    return quadrant == MatrixQuadrant.schedule;
  } else if (!isImportant && isUrgent) {
    return quadrant == MatrixQuadrant.delegate;
  } else {
    return quadrant == MatrixQuadrant.eliminate;
  }
}

final pendingMatrixTasksProvider = Provider.family<List<Task>, MatrixQuadrant>((ref, quadrant) {
  final allTasksAsync = ref.watch(allActiveTasksProvider);
  final allTasks = allTasksAsync.value ?? [];
  final sortOption = ref.watch(taskSortOptionProvider);

  final pending = allTasks.where((task) => !task.isCompleted && _isInQuadrant(task, quadrant)).toList();

  switch (sortOption) {
    case TaskSortOption.priority:
      pending.sort((a, b) {
        final pComp = b.priority.compareTo(a.priority);
        if (pComp != 0) return pComp;
        if (a.dueDate == null && b.dueDate == null) return a.createdAt.compareTo(b.createdAt);
        if (a.dueDate == null) return 1;
        if (b.dueDate == null) return -1;
        return a.dueDate!.compareTo(b.dueDate!);
      });
    case TaskSortOption.dueDate:
      pending.sort((a, b) {
        if (a.dueDate == null && b.dueDate == null) return b.priority.compareTo(a.priority);
        if (a.dueDate == null) return 1;
        if (b.dueDate == null) return -1;
        final dComp = a.dueDate!.compareTo(b.dueDate!);
        if (dComp != 0) return dComp;
        return b.priority.compareTo(a.priority);
      });
    case TaskSortOption.createdAt:
      pending.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    case TaskSortOption.custom:
      pending.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  }
  return pending;
});

final completedMatrixTasksProvider = Provider.family<List<Task>, MatrixQuadrant>((ref, quadrant) {
  final allTasksAsync = ref.watch(allActiveTasksProvider);
  final allTasks = allTasksAsync.value ?? [];

  final completed = allTasks.where((task) => task.isCompleted && _isInQuadrant(task, quadrant)).toList();

  completed.sort((a, b) {
    final ca = a.completedAt ?? a.updatedAt;
    final cb = b.completedAt ?? b.updatedAt;
    return cb.compareTo(ca);
  });
  return completed;
});
