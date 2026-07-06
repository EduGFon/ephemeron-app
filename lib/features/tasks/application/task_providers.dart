import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../data/local/database.dart';
import '../../../data/local/database_provider.dart';
import '../../alarms/application/alarm_scheduler_provider.dart';
import '../../auth/google/google_auth_provider.dart';
import '../domain/smart_list_type.dart';
import '../data/google_tasks_mirror.dart';
import '../data/task_repository.dart';

/// Null whenever no Google account is connected — TaskRepository treats
/// that exactly like "the mirror push failed," so nothing else needs to
/// branch on connection state separately.
final googleTasksMirrorProvider = Provider<GoogleTasksMirror?>((ref) {
  final account = ref.watch(googleAccountProvider).value;
  if (account == null) return null;
  return GoogleTasksMirror(ref.watch(googleAuthRepositoryProvider));
});

final taskRepositoryProvider = Provider<TaskRepository>((ref) {
  return TaskRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(alarmSchedulerProvider),
    ref.watch(googleTasksMirrorProvider),
  );
});

final listsProvider = StreamProvider<List<TaskList>>((ref) {
  return ref.watch(taskRepositoryProvider).watchLists();
});

final tasksInListProvider = StreamProvider.family<List<Task>, String>((
  ref,
  listId,
) {
  return ref.watch(taskRepositoryProvider).watchTasksInList(listId);
});

final customSmartListsProvider = StreamProvider<List<CustomSmartList>>((ref) {
  return ref.watch(taskRepositoryProvider).watchCustomSmartLists();
});

final customSmartListByIdProvider = StreamProvider.family<CustomSmartList?, String>((ref, id) {
  return ref.watch(taskRepositoryProvider).watchCustomSmartListById(id);
});

final tasksForListProvider = StreamProvider.family<List<Task>, String>((ref, listId) {
  final repo = ref.watch(taskRepositoryProvider);
  if (listId.startsWith('smart:')) {
    final typeStr = listId.substring(6);
    final type = SmartListType.values.firstWhere((e) => e.name == typeStr);
    return repo.watchSmartList(type);
  } else if (listId.startsWith('custom_smart:')) {
    final id = listId.substring(13);
    final smartListAsync = ref.watch(customSmartListByIdProvider(id));
    return smartListAsync.when(
      data: (smartList) {
        if (smartList == null) return Stream.value(<Task>[]);
        return repo.watchTasksForCustomSmartList(smartList);
      },
      loading: () => const Stream<List<Task>>.empty(),
      error: (err, stack) => Stream<List<Task>>.error(err, stack),
    );
  } else {
    return repo.watchTasksInList(listId);
  }
});

final allPendingTasksProvider = StreamProvider<List<Task>>((ref) {
  return ref.watch(taskRepositoryProvider).watchAllPendingTasks();
});

final allActiveTasksProvider = StreamProvider<List<Task>>((ref) {
  return ref.watch(taskRepositoryProvider).watchAllActiveTasks();
});

final subtasksProvider = StreamProvider.family<List<Task>, String>((
  ref,
  parentTaskId,
) {
  return ref.watch(taskRepositoryProvider).watchSubtasks(parentTaskId);
});

final smartListProvider = StreamProvider.family<List<Task>, SmartListType>((
  ref,
  type,
) {
  return ref.watch(taskRepositoryProvider).watchSmartList(type);
});

final allTagsProvider = StreamProvider<List<Tag>>((ref) {
  return ref.watch(taskRepositoryProvider).watchAllTags();
});

final taskTagsProvider = StreamProvider.family<List<Tag>, String>((
  ref,
  taskId,
) {
  return ref.watch(taskRepositoryProvider).watchTagsForTask(taskId);
});

enum TaskSortOption {
  priority,
  dueDate,
  createdAt,
  custom;

  String get label {
    switch (this) {
      case TaskSortOption.priority: return 'Priority';
      case TaskSortOption.dueDate: return 'Due Date';
      case TaskSortOption.createdAt: return 'Creation Date';
      case TaskSortOption.custom: return 'Custom Order';
    }
  }
}

class TaskSortOptionNotifier extends Notifier<TaskSortOption> {
  @override
  TaskSortOption build() => TaskSortOption.priority;

  void setSortOption(TaskSortOption option) {
    state = option;
  }
}

final taskSortOptionProvider = NotifierProvider<TaskSortOptionNotifier, TaskSortOption>(() {
  return TaskSortOptionNotifier();
});

final pendingTasksInListProvider = Provider.family<AsyncValue<List<Task>>, String>((ref, listId) {
  final tasksAsync = ref.watch(tasksForListProvider(listId));
  final sortOption = ref.watch(taskSortOptionProvider);

  return tasksAsync.whenData((tasks) {
    final pending = tasks.where((t) => !t.isCompleted).toList();
    
    switch (sortOption) {
      case TaskSortOption.priority:
        pending.sort((a, b) {
          final pComp = b.priority.compareTo(a.priority); // high first
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
        pending.sort((a, b) => b.createdAt.compareTo(a.createdAt)); // newest first
      case TaskSortOption.custom:
        pending.sort((a, b) => a.sortOrder.compareTo(b.sortOrder)); // ascending sortOrder
    }
    return pending;
  });
});

final completedTasksInListProvider = Provider.family<AsyncValue<List<Task>>, String>((ref, listId) {
  final tasksAsync = ref.watch(tasksForListProvider(listId));
  return tasksAsync.whenData((tasks) {
    final completed = tasks.where((t) => t.isCompleted).toList();
    completed.sort((a, b) {
      final ca = a.completedAt ?? a.updatedAt;
      final cb = b.completedAt ?? b.updatedAt;
      return cb.compareTo(ca); // last completed comes first
    });
    return completed;
  });
});

final selectedListIdProvider = StateProvider<String?>((ref) => null);

