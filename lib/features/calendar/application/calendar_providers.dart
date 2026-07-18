import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/database_provider.dart';
import '../../alarms/application/alarm_scheduler_provider.dart';
import '../../auth/google/google_auth_provider.dart';
import '../domain/calendar_event.dart';
import '../data/calendar_repository.dart';
import '../../tasks/application/task_providers.dart';
import '../../tasks/data/task_repository.dart';
import '../../habits/application/habit_providers.dart';
import '../../habits/domain/habit_frequency.dart';
import '../../../core/settings/shared_preferences_provider.dart';

class CalendarHourHeightNotifier extends Notifier<double> {
  @override
  double build() => 80.0;

  @override
  set state(double value) => super.state = value;
}

final calendarHourHeightProvider =
    NotifierProvider<CalendarHourHeightNotifier, double>(CalendarHourHeightNotifier.new);

final calendarRepositoryProvider = Provider<CalendarRepository>((ref) {
  return CalendarRepository(
    ref.watch(googleAuthRepositoryProvider),
    ref.watch(appDatabaseProvider),
    ref.watch(alarmSchedulerProvider),
  );
});

/// Keyed by the first-of-month, normalized to midnight — always compute
/// the key this way (see `_normalizeMonth` in CalendarScreen) so equal
/// months actually hit the same cache entry instead of refetching.
class CalendarEventOverridesNotifier extends Notifier<Map<String, CalendarEvent>> {
  @override
  Map<String, CalendarEvent> build() => const {};

  void updateEvent(CalendarEvent event) {
    state = {...state, event.id: event};
  }

  void removeOverride(String eventId) {
    if (state.containsKey(eventId)) {
      final newState = Map<String, CalendarEvent>.from(state);
      newState.remove(eventId);
      state = newState;
    }
  }
}

final calendarEventOverridesProvider =
    NotifierProvider<CalendarEventOverridesNotifier, Map<String, CalendarEvent>>(
  CalendarEventOverridesNotifier.new,
);

/// Keyed by the first-of-month, normalized to midnight — always compute
/// the key this way (see `_normalizeMonth` in CalendarScreen) so equal
/// months actually hit the same cache entry instead of refetching.
final monthEventsProvider =
    FutureProvider.family<List<CalendarEvent>, DateTime>((ref, month) async {
  // Invalidate and reload only when the underlying account ID changes.
  // This prevents the calendar from reloading on startup when the stream transitions
  // from AsyncLoading to AsyncData but the account ID is identical to the one
  // we synchronously restored from SharedPreferences.
  ref.watch(googleAccountProvider.select((v) {
    if (v.isLoading && !v.hasValue) {
      return ref.read(googleAuthRepositoryProvider).currentAccount?.id;
    }
    return v.value?.id;
  }));
  final overrides = ref.watch(calendarEventOverridesProvider);
  final repo = ref.watch(calendarRepositoryProvider);
  final start = DateTime(month.year, month.month, 1);
  final end = DateTime(month.year, month.month + 1, 1);

  // Fetch calendar events
  final events = await repo.listEvents(rangeStart: start, rangeEnd: end);

  // Fetch local tasks
  final entries = await ref.watch(calendarTasksProvider.future);

  // Group by task ID to avoid duplicates from tag color joins
  final map = <String, TaskCalendarEntry>{};
  for (final entry in entries) {
    if (!map.containsKey(entry.task.id)) {
      map[entry.task.id] = entry;
    }
  }

  // Filter tasks in range and convert to CalendarEvents
  final taskEvents = map.values.where((entry) {
    if (entry.task.dueDate == null) return false;
    final due = entry.task.dueDate!;
    return due.isAfter(start.subtract(const Duration(days: 1))) &&
           due.isBefore(end.add(const Duration(days: 1)));
  }).map((entry) {
    final t = entry.task;
    final start = t.dueDate!;
    final end = start.add(Duration(minutes: t.durationMinutes));

    // Show checkmark prefix if completed, empty box if not
    final prefix = t.isCompleted ? '✓ ' : '☐ ';

    return CalendarEvent(
      id: 'task:${t.id}',
      title: '$prefix${t.title}',
      description: t.description,
      start: start,
      end: end,
      isAllDay: !t.dueHasTime,
      colorId: 'task:${entry.tagColorHex ?? ''}',
    );
  }).toList();

  // Fetch local habits
  final habitsList = await ref.watch(calendarHabitsProvider.future);

  // Fetch habit logs
  final habitLogsList = await ref.watch(calendarHabitLogsProvider.future);

  final habitEvents = <CalendarEvent>[];
  for (final habit in habitsList) {
    if (habit.reminderHour != null && habit.reminderMinute != null) {
      final frequency = HabitFrequency.decode(habit.frequencyConfig);
      final logsForHabit = habitLogsList.where((l) => l.habitId == habit.id).toList();

      for (var day = start; day.isBefore(end); day = day.add(const Duration(days: 1))) {
        if (frequency.isDueOn(day, habitStartDate: habit.startDate)) {
          final dayStr = DateTime(day.year, day.month, day.day);
          final isCompleted = logsForHabit.any((l) {
            final logDay = DateTime(l.date.year, l.date.month, l.date.day);
            return logDay == dayStr && l.isCompleted;
          });

          final habitStart = DateTime(day.year, day.month, day.day, habit.reminderHour!, habit.reminderMinute!);
          final habitEnd = habitStart.add(const Duration(minutes: 30));

          final prefix = isCompleted ? '✓ ' : '☐ ';

          habitEvents.add(
            CalendarEvent(
              id: 'habit:${habit.id}:${day.toIso8601String().split('T')[0]}',
              title: '$prefix${habit.name}',
              description: 'Habit Goal: ${habit.goalType == 'binary' ? 'Binary' : '${habit.goalAmount} ${habit.goalUnit}'}',
              start: habitStart,
              end: habitEnd,
              isAllDay: false,
              colorId: 'habit:teal',
            ),
          );
        }
      }
    }
  }

  final allEvents = [...events, ...taskEvents, ...habitEvents];
  return allEvents.map((e) => overrides[e.id] ?? e).toList();
});

/// Derives a single day's events from whatever month is currently
/// loaded, rather than making a separate request — the common case of
/// tapping a day within the visible month should feel instant.
final dayEventsProvider =
    Provider.family<List<CalendarEvent>, DateTime>((ref, day) {
  final month = DateTime(day.year, day.month, 1);
  final monthEvents = ref.watch(monthEventsProvider(month)).value ?? const [];
  return monthEvents.where((e) {
    final sLocal = e.start.toLocal();
    final eventDay = DateTime(sLocal.year, sLocal.month, sLocal.day);
    final targetDay = DateTime(day.year, day.month, day.day);
    return eventDay == targetDay ||
        (e.isAllDay && !e.start.isAfter(targetDay) && e.end.isAfter(targetDay));
  }).toList();
});

class SelectedDayNotifier extends Notifier<DateTime> {
  @override
  DateTime build() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  void setDay(DateTime day) {
    state = day;
  }
}

final selectedDayProvider = NotifierProvider<SelectedDayNotifier, DateTime>(
  () => SelectedDayNotifier(),
);

class FocusedMonthNotifier extends Notifier<DateTime> {
  @override
  DateTime build() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, 1);
  }

  void setMonth(DateTime month) {
    state = month;
  }
}

final focusedMonthProvider = NotifierProvider<FocusedMonthNotifier, DateTime>(
  () => FocusedMonthNotifier(),
);

enum CalendarView {
  monthGrid,
  weekTimeline,
  fourDaysTimeline,
  threeDaysTimeline,
  dailyTimeline,
  compact,
}

class CalendarViewNotifier extends Notifier<CalendarView> {
  static const _prefKey = 'calendar.lastView';

  @override
  CalendarView build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final savedViewName = prefs.getString(_prefKey);
    if (savedViewName != null) {
      for (final v in CalendarView.values) {
        if (v.name == savedViewName) return v;
      }
    }
    return CalendarView.monthGrid;
  }

  void setView(CalendarView view) {
    state = view;
    ref.read(sharedPreferencesProvider).setString(_prefKey, view.name);
  }
}

final calendarViewProvider = NotifierProvider<CalendarViewNotifier, CalendarView>(
  () => CalendarViewNotifier(),
);
