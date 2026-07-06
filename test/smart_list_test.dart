import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:ephemeron/data/local/database.dart';
import 'package:ephemeron/features/tasks/data/task_repository.dart';
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

  test('custom smart list filters by priority and due date', () async {
    final inbox = await db.into(db.lists).insertReturning(
          ListsCompanion.insert(
            name: 'Inbox',
            isInbox: const Value(true),
          ),
        );

    final smartList = await repository.createCustomSmartList(
      name: 'High Priority Today',
      minPriority: 2,
      dateFilter: 'today',
    );

    final today = DateTime.now();
    final tomorrow = today.add(const Duration(days: 1));

    final t1 = await repository.createTask(
      listId: inbox.id,
      title: 'Task 1',
      priority: 3,
      dueDate: today,
    );

    await repository.createTask(
      listId: inbox.id,
      title: 'Task 2',
      priority: 3,
      dueDate: tomorrow,
    );

    await repository.createTask(
      listId: inbox.id,
      title: 'Task 3',
      priority: 1,
      dueDate: today,
    );

    final tasks = await repository.watchTasksForCustomSmartList(smartList).first;

    expect(tasks.length, 1);
    expect(tasks.first.id, t1.id);
  });
}
