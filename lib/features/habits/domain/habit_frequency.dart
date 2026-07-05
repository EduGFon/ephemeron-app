import 'dart:convert';

enum HabitFrequencyType { daily, weekly, interval }

/// Matches the brainstorm's three frequency modes:
///  - daily: every day, or every day except specific weekdays are excluded
///    (weekdays empty = every day; non-empty = only those weekdays)
///  - weekly: a target count per week (timesPerWeek), not tied to
///    specific days — any [timesPerWeek] days in a Mon-Sun week satisfy it
///  - interval: every N days counted from [startDate], regardless of
///    calendar week boundaries
class HabitFrequency {
  const HabitFrequency.daily({this.weekdays = const []})
    : type = HabitFrequencyType.daily,
      timesPerWeek = null,
      intervalDays = null;
  const HabitFrequency.weekly({required this.timesPerWeek})
    : type = HabitFrequencyType.weekly,
      weekdays = const [],
      intervalDays = null;
  const HabitFrequency.interval({required this.intervalDays})
    : type = HabitFrequencyType.interval,
      weekdays = const [],
      timesPerWeek = null;

  final HabitFrequencyType type;

  /// Daily-with-specific-weekdays only. ISO weekday numbers (1=Mon..7=Sun).
  final List<int> weekdays;

  /// Weekly only — target completions per Mon-Sun week.
  final int? timesPerWeek;

  /// Interval only — every N days from the habit's start date.
  final int? intervalDays;

  String encode() => jsonEncode({
    'type': type.name,
    'weekdays': weekdays,
    'timesPerWeek': timesPerWeek,
    'intervalDays': intervalDays,
  });

  static HabitFrequency decode(String? raw) {
    if (raw == null || raw.isEmpty) return const HabitFrequency.daily();
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final type = HabitFrequencyType.values.byName(map['type'] as String);
      switch (type) {
        case HabitFrequencyType.daily:
          return HabitFrequency.daily(
            weekdays: (map['weekdays'] as List<dynamic>? ?? []).cast<int>(),
          );
        case HabitFrequencyType.weekly:
          return HabitFrequency.weekly(
            timesPerWeek: map['timesPerWeek'] as int? ?? 1,
          );
        case HabitFrequencyType.interval:
          return HabitFrequency.interval(
            intervalDays: map['intervalDays'] as int? ?? 1,
          );
      }
    } catch (_) {
      return const HabitFrequency.daily();
    }
  }

  /// Whether [date] is a day this habit is expected on. For [weekly],
  /// every day is technically "eligible" (the target is a weekly count,
  /// not specific days) — callers doing streak/today logic should treat
  /// weekly habits specially rather than relying on this alone; see
  /// HabitRepository's streak calculation.
  bool isDueOn(DateTime date, {required DateTime habitStartDate}) {
    switch (type) {
      case HabitFrequencyType.daily:
        return weekdays.isEmpty || weekdays.contains(date.weekday);
      case HabitFrequencyType.weekly:
        return true;
      case HabitFrequencyType.interval:
        final start = DateTime(
          habitStartDate.year,
          habitStartDate.month,
          habitStartDate.day,
        );
        final day = DateTime(date.year, date.month, date.day);
        if (day.isBefore(start)) return false;
        final daysSinceStart = day.difference(start).inDays;
        return daysSinceStart % (intervalDays ?? 1) == 0;
    }
  }
}
