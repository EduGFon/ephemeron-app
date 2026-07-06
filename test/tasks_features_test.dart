import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:ephemeron/data/local/database.dart';
import 'package:ephemeron/features/tasks/data/task_repository.dart';
import 'package:ephemeron/features/tasks/domain/task_recurrence.dart';
import 'package:ephemeron/features/alarms/data/alarm_scheduler.dart';
import 'package:ephemeron/features/alarms/domain/alarm_preset.dart';
import 'package:ephemeron/features/alarms/domain/reminder_offset.dart';

class FakeAlarmScheduler extends Fake implements AlarmScheduler {
  @override
  Future<List<int>> scheduleAlarmsForOffsets({
    required String entityId,
    required String title,
    required String body,
    required DateTime dueAt,
    required List<ReminderOffset> offsets,
    required AlarmPreset preset,
  }) async {
    return [];
  }

  @override
  Future<void> cancelByIds(List<int> ids) async {}
}

void main() {
  late AppDatabase db;
  late TaskRepository repository;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repository = TaskRepository(db, FakeAlarmScheduler(), null);
  });

  tearDown(() async {
    await db.close();
  });

  group('Tasks Advanced Features Tests', () {
    test('task duration defaults to 30m and can be customized', () async {
      final inbox = await db.into(db.lists).insertReturning(
            ListsCompanion.insert(
              name: 'Inbox',
              isInbox: const Value(true),
            ),
          );

      // Default duration
      final t1 = await repository.createTask(
        listId: inbox.id,
        title: 'Task 1',
      );
      expect(t1.durationMinutes, 30);

      // Customized duration
      final t2 = await repository.createTask(
        listId: inbox.id,
        title: 'Task 2',
        durationMinutes: 120,
      );
      expect(t2.durationMinutes, 120);

      // Can update duration
      await repository.updateTask(t1.id, durationMinutes: 45);
      final t1Updated = await (db.select(db.tasks)..where((t) => t.id.equals(t1.id))).getSingle();
      expect(t1Updated.durationMinutes, 45);
    });

    test('subtasks relationship and watchSubtasks', () async {
      final inbox = await db.into(db.lists).insertReturning(
            ListsCompanion.insert(
              name: 'Inbox',
              isInbox: const Value(true),
            ),
          );

      final parent = await repository.createTask(
        listId: inbox.id,
        title: 'Parent Task',
      );

      final sub1 = await repository.createTask(
        listId: inbox.id,
        title: 'Subtask 1',
        parentTaskId: parent.id,
      );

      final sub2 = await repository.createTask(
        listId: inbox.id,
        title: 'Subtask 2',
        parentTaskId: parent.id,
      );

      final subtasks = await repository.watchSubtasks(parent.id).first;
      expect(subtasks.length, 2);
      expect(subtasks.any((s) => s.id == sub1.id), true);
      expect(subtasks.any((s) => s.id == sub2.id), true);
    });

    test('won\'t do status toggle and CRUD', () async {
      final inbox = await db.into(db.lists).insertReturning(
            ListsCompanion.insert(
              name: 'Inbox',
              isInbox: const Value(true),
            ),
          );

      final task = await repository.createTask(
        listId: inbox.id,
        title: 'Task',
        isWontDo: true,
      );
      expect(task.isWontDo, true);

      await repository.toggleWontDo(task.id);
      final taskUpdated = await (db.select(db.tasks)..where((t) => t.id.equals(task.id))).getSingle();
      expect(taskUpdated.isWontDo, false);
    });

    test('weekly recurrence on custom weekdays calculation', () async {
      final inputDate = DateTime(2026, 7, 6, 10, 0); // Monday, July 6, 2026
      
      // Repeating every Tue (2) and Thu (4)
      final recurrence = TaskRecurrence(
        type: RecurrenceType.weekly,
        weekdays: const [2, 4],
      );

      // Next after Monday should be Tuesday (July 7)
      final next1 = recurrence.nextOccurrence(inputDate);
      expect(next1, DateTime(2026, 7, 7, 10, 0));

      // Next after Tuesday should be Thursday (July 9)
      final next2 = recurrence.nextOccurrence(next1!);
      expect(next2, DateTime(2026, 7, 9, 10, 0));
    });

    test('watchTasksForCalendar fetches scheduled active tasks with tag color joins', () async {
      final inbox = await db.into(db.lists).insertReturning(
            ListsCompanion.insert(
              name: 'Inbox',
              isInbox: const Value(true),
            ),
          );

      final tag = await db.into(db.tags).insertReturning(
            TagsCompanion.insert(
              name: 'Urgent',
              colorHex: const Value('#E67C73'),
            ),
          );

      final task = await repository.createTask(
        listId: inbox.id,
        title: 'Calendar Task',
        dueDate: DateTime(2026, 7, 6, 12, 0),
      );

      await db.into(db.taskTags).insert(
            TaskTagsCompanion.insert(
              taskId: task.id,
              tagId: tag.id,
            ),
          );

      final calendarTasks = await repository.watchTasksForCalendar().first;
      expect(calendarTasks.length, 1);
      expect(calendarTasks[0].task.id, task.id);
      expect(calendarTasks[0].tagColorHex, '#E67C73');
    });
  });
}
