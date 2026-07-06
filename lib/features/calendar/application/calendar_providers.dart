import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/database_provider.dart';
import '../../alarms/application/alarm_scheduler_provider.dart';
import '../../auth/google/google_auth_provider.dart';
import '../domain/calendar_event.dart';
import '../data/calendar_repository.dart';
import '../../tasks/application/task_providers.dart';
import '../../tasks/data/task_repository.dart';

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
final monthEventsProvider =
    FutureProvider.family<List<CalendarEvent>, DateTime>((ref, month) async {
  ref.watch(googleAccountProvider); // Invalidate and reload when login state changes
  final repo = ref.watch(calendarRepositoryProvider);
  final start = DateTime(month.year, month.month, 1);
  final end = DateTime(month.year, month.month + 1, 1);

  // Fetch calendar events
  final events = await repo.listEvents(rangeStart: start, rangeEnd: end);

  // Fetch local tasks
  final tasksAsync = ref.watch(calendarTasksProvider);
  final entries = tasksAsync.value ?? [];

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

  return [...events, ...taskEvents];
});

/// Derives a single day's events from whatever month is currently
/// loaded, rather than making a separate request — the common case of
/// tapping a day within the visible month should feel instant.
final dayEventsProvider =
    Provider.family<List<CalendarEvent>, DateTime>((ref, day) {
  final month = DateTime(day.year, day.month, 1);
  final monthEvents = ref.watch(monthEventsProvider(month)).value ?? const [];
  return monthEvents.where((e) {
    final eventDay = DateTime(e.start.year, e.start.month, e.start.day);
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
  @override
  CalendarView build() => CalendarView.monthGrid;

  void setView(CalendarView view) {
    state = view;
  }
}

final calendarViewProvider = NotifierProvider<CalendarViewNotifier, CalendarView>(
  () => CalendarViewNotifier(),
);
