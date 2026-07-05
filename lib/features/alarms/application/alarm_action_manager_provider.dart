import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../habits/application/habit_providers.dart';
import '../../tasks/application/task_providers.dart';
import '../data/alarm_scheduler.dart';
import 'alarm_scheduler_provider.dart';

/// Provider that listens to notification tap/action events (like tapping "Mark done")
/// while the application process is running (foreground or active background),
/// applying the completion to the respective Task or Habit in the database.
final alarmActionManagerProvider = Provider<void>((ref) {
  final scheduler = ref.watch(alarmSchedulerProvider);
  final taskRepo = ref.watch(taskRepositoryProvider);
  final habitRepo = ref.watch(habitRepositoryProvider);

  final subscription = scheduler.actionEvents.listen((event) async {
    if (event.type == AlarmActionType.done) {
      // 1. Try to complete as a Task
      await taskRepo.completeTask(event.entityId);

      // 2. Try to log as a completed Habit
      final habit = await habitRepo.getHabit(event.entityId);
      if (habit != null) {
        await habitRepo.logProgress(
          event.entityId,
          amount: habit.goalAmount ?? 1,
          isCompleted: true,
        );
      }
    }
  });

  ref.onDispose(subscription.cancel);
});
