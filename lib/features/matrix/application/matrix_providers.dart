import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/database.dart';
import '../../tasks/application/task_providers.dart';
import '../domain/matrix_quadrant.dart';

final matrixTasksProvider = Provider.family<List<Task>, MatrixQuadrant>((ref, quadrant) {
  final allTasksAsync = ref.watch(allPendingTasksProvider);
  final allTasks = allTasksAsync.value ?? [];
  
  final now = DateTime.now();
  final endOfTomorrow = DateTime(now.year, now.month, now.day).add(const Duration(days: 2));

  return allTasks.where((task) {
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
      // !isImportant && !isUrgent
      return quadrant == MatrixQuadrant.eliminate;
    }
  }).toList();
});
