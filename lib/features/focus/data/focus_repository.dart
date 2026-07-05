import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../data/local/database.dart';
import '../../habits/data/habit_repository.dart';
import '../../habits/domain/habit_goal_unit.dart';
import '../domain/focus_mode.dart';

const _uuid = Uuid();

/// Sessions under this length aren't stored at all — matches the
/// brainstorm's "focus sessions longer than 5min will be stored to show
/// focus distribution metrics" literally: short sessions don't get
/// persisted, not just excluded from metrics after the fact.
const minimumStoredDuration = Duration(minutes: 5);

class FocusRepository {
  FocusRepository(this._db, this._habitRepository);

  final AppDatabase _db;
  final HabitRepository _habitRepository;

  /// Returns the created session's id, or null if the session was too
  /// short to store (see [minimumStoredDuration]).
  Future<String?> endSession({
    required FocusMode mode,
    required DateTime startedAt,
    required DateTime endedAt,
    String? linkedTaskId,
    String? linkedHabitId,
    String? note,
  }) async {
    final duration = endedAt.difference(startedAt);
    if (duration < minimumStoredDuration) return null;

    final id = _uuid.v4();
    await _db
        .into(_db.focusSessions)
        .insert(
          FocusSessionsCompanion.insert(
            id: Value(id),
            mode: mode.name,
            linkedTaskId: Value(linkedTaskId),
            linkedHabitId: Value(linkedHabitId),
            startedAt: startedAt,
            endedAt: Value(endedAt),
            durationSeconds: Value(duration.inSeconds),
            note: Value(note),
          ),
        );

    if (linkedHabitId != null) {
      await _applyToHabitGoal(linkedHabitId, duration);
    }

    return id;
  }

  /// Focus time counts toward a habit's goal when the goal unit is
  /// time-based. Habits created via the curated unit dropdown (Step 6.1)
  /// match exactly via [HabitGoalUnit]; habits using the "Custom..."
  /// free-text fallback still get a best-effort substring match ("min"/
  /// "hour"/"hr") so older free-text units like "hrs" or "minutes" keep
  /// working. Anything else (pages, reps, ml, ...) can't be meaningfully
  /// derived from a duration, so the session still links to the habit
  /// for the record but doesn't move its goal progress.
  Future<void> _applyToHabitGoal(
    String habitId,
    Duration sessionDuration,
  ) async {
    final habit = await (_db.select(
      _db.habits,
    )..where((h) => h.id.equals(habitId))).getSingleOrNull();
    if (habit == null || habit.goalType != 'amount' || habit.goalUnit == null) {
      return;
    }

    final knownUnit = HabitGoalUnit.tryParse(habit.goalUnit);
    double? contributedAmount;
    if (knownUnit != null) {
      if (!knownUnit.isTimeBased) return;
      contributedAmount = knownUnit == HabitGoalUnit.hours
          ? sessionDuration.inSeconds / 3600
          : sessionDuration.inSeconds / 60;
    } else {
      final unit = habit.goalUnit!.toLowerCase();
      if (unit.contains('min')) {
        contributedAmount = sessionDuration.inSeconds / 60;
      } else if (unit.contains('hour') || unit.contains('hr')) {
        contributedAmount = sessionDuration.inSeconds / 3600;
      }
    }
    if (contributedAmount == null) return;

    final today = DateTime.now();
    final existing =
        await (_db.select(_db.habitLogs)..where(
              (l) =>
                  l.habitId.equals(habitId) &
                  l.date.equals(DateTime(today.year, today.month, today.day)),
            ))
            .getSingleOrNull();
    final newAmount = (existing?.amount ?? 0) + contributedAmount;
    await _habitRepository.logProgress(
      habitId,
      amount: newAmount,
      isCompleted: newAmount >= (habit.goalAmount ?? double.infinity),
    );
  }

  Future<void> addNote(String sessionId, String note) async {
    await (_db.update(_db.focusSessions)..where((s) => s.id.equals(sessionId)))
        .write(FocusSessionsCompanion(note: Value(note)));
  }

  // ---------------------------------------------------------------------
  // Metrics
  // ---------------------------------------------------------------------

  Future<Duration> totalFocusedBetween(DateTime start, DateTime end) async {
    final sessions =
        await (_db.select(_db.focusSessions)..where(
              (s) =>
                  s.startedAt.isBiggerOrEqualValue(start) &
                  s.startedAt.isSmallerThanValue(end),
            ))
            .get();
    final totalSeconds = sessions.fold<int>(
      0,
      (sum, s) => sum + s.durationSeconds,
    );
    return Duration(seconds: totalSeconds);
  }

  Future<Duration> totalFocusedToday() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    return totalFocusedBetween(start, start.add(const Duration(days: 1)));
  }

  Future<Duration> totalFocusedThisWeek() {
    final now = DateTime.now();
    final start = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - 1));
    return totalFocusedBetween(start, start.add(const Duration(days: 7)));
  }

  Future<Duration> totalFocusedThisMonth(DateTime month) {
    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 1);
    return totalFocusedBetween(start, end);
  }

  Future<Duration> totalFocusedThisYear(int year) {
    return totalFocusedBetween(DateTime(year, 1, 1), DateTime(year + 1, 1, 1));
  }

  Future<Duration> totalFocusedAllTime() async {
    final sessions = await _db.select(_db.focusSessions).get();
    final totalSeconds = sessions.fold<int>(
      0,
      (sum, s) => sum + s.durationSeconds,
    );
    return Duration(seconds: totalSeconds);
  }

  /// Per-day totals for [month] — the drill-down behind "clicking on it
  /// shows month view with each focus duration per day."
  Future<Map<DateTime, Duration>> dailyTotalsForMonth(DateTime month) async {
    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 1);
    final sessions =
        await (_db.select(_db.focusSessions)..where(
              (s) =>
                  s.startedAt.isBiggerOrEqualValue(start) &
                  s.startedAt.isSmallerThanValue(end),
            ))
            .get();

    final totals = <DateTime, Duration>{};
    for (final session in sessions) {
      final day = DateTime(
        session.startedAt.year,
        session.startedAt.month,
        session.startedAt.day,
      );
      totals[day] =
          (totals[day] ?? Duration.zero) +
          Duration(seconds: session.durationSeconds);
    }
    return totals;
  }
}
