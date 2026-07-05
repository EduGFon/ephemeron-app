import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../data/local/database.dart';
import '../../alarms/data/alarm_scheduler.dart';
import '../../alarms/domain/alarm_preset.dart';
import '../domain/habit_frequency.dart';
import '../domain/habit_metrics.dart';

const _uuid = Uuid();

class HabitRepository {
  HabitRepository(this._db, this._alarmScheduler);

  final AppDatabase _db;
  final AlarmScheduler _alarmScheduler;

  // ---------------------------------------------------------------------
  // Watches
  // ---------------------------------------------------------------------

  Stream<List<Habit>> watchHabits({bool includeArchived = false}) {
    final query = _db.select(_db.habits);
    if (!includeArchived) query.where((h) => h.isArchived.equals(false));
    query.orderBy([
      (h) => OrderingTerm.asc(h.section),
      (h) => OrderingTerm.asc(h.createdAt),
    ]);
    return query.watch();
  }

  Stream<List<HabitLog>> watchLogs(String habitId) {
    return (_db.select(
      _db.habitLogs,
    )..where((l) => l.habitId.equals(habitId))).watch();
  }

  // ---------------------------------------------------------------------
  // CRUD
  // ---------------------------------------------------------------------

  Future<Habit> createHabit({
    required String name,
    required String section,
    required HabitFrequency frequency,
    required String goalType, // 'binary' | 'amount'
    double? goalAmount,
    String? goalUnit,
    double logIncrement = 1,
    String goalDuration = 'forever',
    DateTime? startDate,
    int? reminderHour,
    int? reminderMinute,
    AlarmPreset? alarmPreset,
  }) async {
    final id = _uuid.v4();
    await _db
        .into(_db.habits)
        .insert(
          HabitsCompanion.insert(
            id: Value(id),
            name: name,
            section: Value(section),
            frequencyType: frequency.type.name,
            frequencyConfig: Value(frequency.encode()),
            goalType: Value(goalType),
            goalAmount: Value(goalAmount),
            goalUnit: Value(goalUnit),
            logIncrement: Value(logIncrement),
            goalDuration: Value(goalDuration),
            startDate: Value(startDate ?? DateTime.now()),
            reminderHour: Value(reminderHour),
            reminderMinute: Value(reminderMinute),
            alarmPreset: Value(alarmPreset?.name),
          ),
        );
    await _syncAlarms(id);
    return (_db.select(_db.habits)..where((h) => h.id.equals(id))).getSingle();
  }

  Future<void> updateHabit(
    String habitId, {
    String? name,
    String? section,
    HabitFrequency? frequency,
    String? goalType,
    Value<double?>? goalAmount,
    Value<String?>? goalUnit,
    double? logIncrement,
    String? goalDuration,
    Value<int?>? reminderHour,
    Value<int?>? reminderMinute,
    Value<AlarmPreset?>? alarmPreset,
  }) async {
    await (_db.update(_db.habits)..where((h) => h.id.equals(habitId))).write(
      HabitsCompanion(
        name: name != null ? Value(name) : const Value.absent(),
        section: section != null ? Value(section) : const Value.absent(),
        frequencyType: frequency != null
            ? Value(frequency.type.name)
            : const Value.absent(),
        frequencyConfig: frequency != null
            ? Value(frequency.encode())
            : const Value.absent(),
        goalType: goalType != null ? Value(goalType) : const Value.absent(),
        goalAmount: goalAmount ?? const Value.absent(),
        goalUnit: goalUnit ?? const Value.absent(),
        logIncrement: logIncrement != null
            ? Value(logIncrement)
            : const Value.absent(),
        goalDuration: goalDuration != null
            ? Value(goalDuration)
            : const Value.absent(),
        reminderHour: reminderHour ?? const Value.absent(),
        reminderMinute: reminderMinute ?? const Value.absent(),
        alarmPreset: alarmPreset != null
            ? Value(alarmPreset.value?.name)
            : const Value.absent(),
      ),
    );
    await _syncAlarms(habitId);
  }

  Future<void> archiveHabit(String habitId) async {
    final habit = await _getHabit(habitId);
    if (habit == null) return;
    await (_db.update(_db.habits)..where((h) => h.id.equals(habitId))).write(
      const HabitsCompanion(isArchived: Value(true)),
    );
    await _cancelAlarms(habit);
  }

  Future<void> deleteHabit(String habitId) async {
    final habit = await _getHabit(habitId);
    if (habit != null) await _cancelAlarms(habit);
    await (_db.delete(
      _db.habitLogs,
    )..where((l) => l.habitId.equals(habitId))).go();
    await (_db.delete(_db.habits)..where((h) => h.id.equals(habitId))).go();
  }

  // ---------------------------------------------------------------------
  // Logging
  // ---------------------------------------------------------------------

  /// Logs today's (or [date]'s) progress — a clean upsert thanks to the
  /// unique (habitId, date) constraint on HabitLogs.
  Future<void> logProgress(
    String habitId, {
    DateTime? date,
    double amount = 0,
    required bool isCompleted,
  }) async {
    final day = _normalizeDay(date ?? DateTime.now());
    await _db
        .into(_db.habitLogs)
        .insert(
          HabitLogsCompanion.insert(
            habitId: habitId,
            date: day,
            amount: Value(amount),
            isCompleted: Value(isCompleted),
          ),
          onConflict: DoUpdate(
            (old) => HabitLogsCompanion(
              habitId: Value(habitId),
              date: Value(day),
              amount: Value(amount),
              isCompleted: Value(isCompleted),
            ),
            target: [_db.habitLogs.habitId, _db.habitLogs.date],
          ),
        );
  }

  Future<void> toggleBinaryToday(String habitId) async {
    final today = _normalizeDay(DateTime.now());
    final existing =
        await (_db.select(_db.habitLogs)
              ..where((l) => l.habitId.equals(habitId) & l.date.equals(today)))
            .getSingleOrNull();
    await logProgress(habitId, isCompleted: !(existing?.isCompleted ?? false));
  }

  /// Adds the habit's configured `logIncrement` to today's running total
  /// — the quick one-tap log action, as opposed to [logProgress] which
  /// sets an exact amount (used for manual correction).
  Future<void> quickLogToday(String habitId) async {
    final habit = await _getHabit(habitId);
    if (habit == null) return;
    final today = _normalizeDay(DateTime.now());
    final existing =
        await (_db.select(_db.habitLogs)
              ..where((l) => l.habitId.equals(habitId) & l.date.equals(today)))
            .getSingleOrNull();
    final newAmount = (existing?.amount ?? 0) + habit.logIncrement;
    await logProgress(
      habitId,
      amount: newAmount,
      isCompleted: newAmount >= (habit.goalAmount ?? double.infinity),
    );
  }

  // ---------------------------------------------------------------------
  // Metrics
  // ---------------------------------------------------------------------

  Future<HabitMetrics> computeMetrics(Habit habit) async {
    final logs = await (_db.select(
      _db.habitLogs,
    )..where((l) => l.habitId.equals(habit.id))).get();
    final logsByDay = {for (final log in logs) _normalizeDay(log.date): log};
    final frequency = HabitFrequency.decode(habit.frequencyConfig);
    final today = _normalizeDay(DateTime.now());

    final last7 = <HabitDayStatus>[];
    for (var i = 6; i >= 0; i--) {
      final day = today.subtract(Duration(days: i));
      last7.add(_statusFor(day, today, habit, frequency, logsByDay));
    }

    final currentStreak = _computeStreak(habit, frequency, logsByDay, today);
    final longestStreak = _computeLongestStreak(
      habit,
      frequency,
      logsByDay,
      today,
    );

    return HabitMetrics(
      currentStreak: currentStreak,
      longestStreak: longestStreak,
      last7Days: last7,
    );
  }

  HabitDayStatus _statusFor(
    DateTime day,
    DateTime today,
    Habit habit,
    HabitFrequency frequency,
    Map<DateTime, HabitLog> logsByDay,
  ) {
    if (day.isAfter(today)) return HabitDayStatus.future;
    if (day.isBefore(_normalizeDay(habit.startDate))) {
      return HabitDayStatus.notDue;
    }
    if (frequency.type != HabitFrequencyType.weekly &&
        !frequency.isDueOn(day, habitStartDate: habit.startDate)) {
      return HabitDayStatus.notDue;
    }
    final log = logsByDay[day];
    return (log?.isCompleted ?? false)
        ? HabitDayStatus.completed
        : HabitDayStatus.missed;
  }

  /// Consecutive applicable days (walking backward from today) that were
  /// completed. Weekly-frequency habits count a whole week as one streak
  /// unit if the target count was hit, rather than day-by-day.
  int _computeStreak(
    Habit habit,
    HabitFrequency frequency,
    Map<DateTime, HabitLog> logsByDay,
    DateTime today,
  ) {
    if (frequency.type == HabitFrequencyType.weekly) {
      return _computeWeeklyStreak(habit, frequency, logsByDay, today);
    }

    var streak = 0;
    var day = today;
    final start = _normalizeDay(habit.startDate);
    while (!day.isBefore(start)) {
      if (frequency.isDueOn(day, habitStartDate: habit.startDate)) {
        final completed = logsByDay[day]?.isCompleted ?? false;
        if (!completed) {
          // Today not yet logged shouldn't break a streak still in
          // progress — only count it as a break once the day has fully
          // passed without completion.
          if (day == today) {
            day = day.subtract(const Duration(days: 1));
            continue;
          }
          break;
        }
        streak++;
      }
      day = day.subtract(const Duration(days: 1));
    }
    return streak;
  }

  int _computeWeeklyStreak(
    Habit habit,
    HabitFrequency frequency,
    Map<DateTime, HabitLog> logsByDay,
    DateTime today,
  ) {
    var streak = 0;
    var weekStart = today.subtract(Duration(days: today.weekday - 1)); // Monday
    while (!weekStart.isBefore(
      _normalizeDay(habit.startDate).subtract(const Duration(days: 7)),
    )) {
      var completions = 0;
      for (var i = 0; i < 7; i++) {
        final day = weekStart.add(Duration(days: i));
        if (day.isAfter(today)) continue;
        if (logsByDay[day]?.isCompleted ?? false) completions++;
      }
      if (completions >= (frequency.timesPerWeek ?? 1)) {
        streak++;
      } else if (weekStart != _mondayOf(today)) {
        // Current week not yet finished doesn't break the streak; a
        // fully-elapsed week that missed its target does.
        break;
      }
      weekStart = weekStart.subtract(const Duration(days: 7));
    }
    return streak;
  }

  int _computeLongestStreak(
    Habit habit,
    HabitFrequency frequency,
    Map<DateTime, HabitLog> logsByDay,
    DateTime today,
  ) {
    // Simple MVP approximation: longest run of consecutive completed
    // applicable days across all logged history. Weekly habits reuse the
    // current-streak figure rather than a full historical scan — a
    // reasonable simplification for a first metrics pass.
    if (frequency.type == HabitFrequencyType.weekly) {
      return _computeWeeklyStreak(habit, frequency, logsByDay, today);
    }
    if (logsByDay.isEmpty) return 0;
    final sortedDays = logsByDay.keys.toList()..sort();
    var longest = 0;
    var current = 0;
    DateTime? previous;
    for (final day in sortedDays) {
      if (!(logsByDay[day]?.isCompleted ?? false)) {
        current = 0;
        previous = day;
        continue;
      }
      if (previous != null && day.difference(previous).inDays == 1) {
        current++;
      } else {
        current = 1;
      }
      longest = current > longest ? current : longest;
      previous = day;
    }
    return longest;
  }

  DateTime _mondayOf(DateTime date) =>
      date.subtract(Duration(days: date.weekday - 1));
  DateTime _normalizeDay(DateTime d) => DateTime(d.year, d.month, d.day);

  // ---------------------------------------------------------------------
  // Alarm wiring
  // ---------------------------------------------------------------------

  Future<Habit?> _getHabit(String habitId) {
    return (_db.select(
      _db.habits,
    )..where((h) => h.id.equals(habitId))).getSingleOrNull();
  }

  Future<void> _cancelAlarms(Habit habit) async {
    final ids = _decodeAlarmIds(habit.scheduledAlarmIds);
    if (ids.isNotEmpty) await _alarmScheduler.cancelByIds(ids);
    await (_db.update(_db.habits)..where((h) => h.id.equals(habit.id))).write(
      const HabitsCompanion(scheduledAlarmIds: Value(null)),
    );
  }

  /// Recomputes this habit's alarms from scratch. Daily (with or without
  /// specific weekdays) gets genuine OS-recurring alarms — set once,
  /// fire forever, no further app involvement needed. Weekly and
  /// interval frequencies don't have a fixed weekday to peg a recurring
  /// alarm to, so they get a best-effort one-shot for the next occurrence
  /// only; see [refreshOneShotAlarms] for how those get kept current.
  Future<void> _syncAlarms(String habitId) async {
    final habit = await _getHabit(habitId);
    if (habit == null) return;

    final existingIds = _decodeAlarmIds(habit.scheduledAlarmIds);
    if (existingIds.isNotEmpty) await _alarmScheduler.cancelByIds(existingIds);

    if (habit.reminderHour == null ||
        habit.reminderMinute == null ||
        habit.alarmPreset == null) {
      await (_db.update(_db.habits)..where((h) => h.id.equals(habitId))).write(
        const HabitsCompanion(scheduledAlarmIds: Value(null)),
      );
      return;
    }

    final preset = AlarmPreset.values.byName(habit.alarmPreset!);
    final frequency = HabitFrequency.decode(habit.frequencyConfig);
    final newIds = <int>[];

    switch (frequency.type) {
      case HabitFrequencyType.daily:
        if (frequency.weekdays.isEmpty) {
          newIds.add(
            await _alarmScheduler.scheduleRecurring(
              entityId: habit.id,
              title: habit.name,
              body: '',
              hour: habit.reminderHour!,
              minute: habit.reminderMinute!,
              preset: preset,
            ),
          );
        } else {
          for (final weekday in frequency.weekdays) {
            newIds.add(
              await _alarmScheduler.scheduleRecurring(
                entityId: habit.id,
                title: habit.name,
                body: '',
                hour: habit.reminderHour!,
                minute: habit.reminderMinute!,
                weekday: weekday,
                preset: preset,
              ),
            );
          }
        }
      case HabitFrequencyType.weekly:
      case HabitFrequencyType.interval:
        newIds.add(
          await _alarmScheduler.scheduleOneShotAt(
            entityId: habit.id,
            title: habit.name,
            body: '',
            hour: habit.reminderHour!,
            minute: habit.reminderMinute!,
            preset: preset,
          ),
        );
    }

    await (_db.update(_db.habits)..where((h) => h.id.equals(habitId))).write(
      HabitsCompanion(scheduledAlarmIds: Value(jsonEncode(newIds))),
    );
  }

  /// Re-schedules the one-shot alarms for weekly/interval habits whose
  /// last-computed occurrence has already fired. Native recurring alarms
  /// (daily) don't need this — call from app startup/resume alongside
  /// them, not instead of.
  Future<void> refreshOneShotAlarms() async {
    final habits = await watchHabits().first;
    for (final habit in habits) {
      final frequency = HabitFrequency.decode(habit.frequencyConfig);
      final hasOneShot =
          frequency.type == HabitFrequencyType.weekly ||
          frequency.type == HabitFrequencyType.interval;
      if (hasOneShot && habit.alarmPreset != null) {
        await _syncAlarms(habit.id);
      }
    }
  }

  List<int> _decodeAlarmIds(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    return (jsonDecode(raw) as List<dynamic>).cast<int>();
  }
}
