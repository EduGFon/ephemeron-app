import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'tables.dart';

part 'database.g.dart';

@DriftDatabase(
  tables: [
    Lists,
    Tags,
    Tasks,
    TaskTags,
    EventTags,
    Habits,
    HabitLogs,
    FocusSessions,
    Countdowns,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? connection]) : super(connection ?? _openConnection());

  /// Bump this and add a MigrationStrategy step whenever a table shape
  /// changes in a later build step (e.g. when Habits gets typed frequency
  /// columns instead of the opaque JSON blob in the skeleton).
  @override
  int get schemaVersion => 6;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await into(lists).insert(
            ListsCompanion.insert(
              name: 'Inbox',
              isInbox: const Value(true),
            ),
          );
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            // Step 3: soft-delete (Trash smart list) + alarm linkage.
            await m.addColumn(tasks, tasks.isDeleted);
            await m.addColumn(tasks, tasks.deletedAt);
            await m.addColumn(tasks, tasks.alarmPreset);
            await m.addColumn(tasks, tasks.reminderOffsetsMinutes);
            await m.addColumn(tasks, tasks.scheduledAlarmIds);
          }
          if (from < 3) {
            // Step 4: local tag layer for Calendar events.
            await m.createTable(eventTags);
          }
          if (from < 4) {
            // Step 6: Habits reminder time + alarm linkage, and a
            // uniqueness guarantee on HabitLogs (habitId, date) so
            // logging a day's progress can be a clean upsert.
            await m.addColumn(habits, habits.reminderHour);
            await m.addColumn(habits, habits.reminderMinute);
            await m.addColumn(habits, habits.alarmPreset);
            await m.addColumn(habits, habits.scheduledAlarmIds);
            await m.database.customStatement(
              'CREATE UNIQUE INDEX IF NOT EXISTS habit_logs_unique_day '
              'ON habit_logs (habit_id, date)',
            );
          }
          if (from < 5) {
            // Habit goal units became a selectable list instead of free
            // text, plus a per-log increment ("record count") so logging
            // progress is a quick tap instead of typing the full running
            // total each time.
            await m.addColumn(habits, habits.logIncrement);
          }
          if (from < 6) {
            // Step 8: Countdown alert bookkeeping.
            await m.addColumn(countdowns, countdowns.scheduledAlarmIds);
          }
        },
      );

  // drift_flutter's driftDatabase() picks the right backend per platform
  // automatically (sqlite3 native on Android/iOS/desktop, WASM+OPFS on
  // Web) — this is the piece that makes the same schema work across every
  // target without per-platform branching in app code.
  static QueryExecutor _openConnection() {
    return driftDatabase(name: 'ephemeron_db');
  }
}
