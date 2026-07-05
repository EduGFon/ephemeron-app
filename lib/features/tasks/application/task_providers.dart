import 'package:flutter_riverpod/flutter_riverpod.dart';

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
