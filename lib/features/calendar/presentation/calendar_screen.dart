import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/settings/app_settings_provider.dart';
import '../../../core/theme/theme_engine_provider.dart';
import '../../../core/theme/theme_palettes.dart';
import '../../settings/presentation/settings_screen.dart';
import '../application/calendar_providers.dart';
import '../data/calendar_repository.dart';
import '../domain/calendar_event.dart';
import 'calendar_daily_timeline_view.dart';
import 'calendar_month_grid_view.dart';
import 'calendar_multi_day_timeline_view.dart';
import 'event_form_sheet.dart';
import '../../tasks/presentation/task_form_sheet.dart';
import '../../tasks/application/task_providers.dart';
import '../../habits/presentation/habit_form_sheet.dart';
import '../../habits/application/habit_providers.dart';
import 'package:ephemeron/presentation/widgets/glassmorphic_wrapper.dart';
import '../../tasks/domain/task_recurrence.dart';
import '../../../presentation/widgets/recurrence_delete_dialog.dart';
import '../../sync/application/sync_service.dart';
import '../../auth/google/google_auth_provider.dart';
import '../../../presentation/widgets/confirmation_dialog.dart';
import 'package:drift/drift.dart' show Value;
import 'package:ephemeron/core/widgets/app_loading_indicator.dart';

class CalendarFormatNotifier extends Notifier<CalendarFormat> {
  @override
  CalendarFormat build() => CalendarFormat.month;

  void setFormat(CalendarFormat format) {
    state = format;
  }
}

final calendarFormatProvider = NotifierProvider<CalendarFormatNotifier, CalendarFormat>(
  () => CalendarFormatNotifier(),
);

class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  static const _initialPage = 10000;
  late final PageController _monthPageController;
  late final PageController _multiDayPageController;
  late final PageController _dailyPageController;
  late final DateTime _anchorDate;

  @override
  void initState() {
    super.initState();
    _requestCalendarPermission();
    final now = DateTime.now();
    _anchorDate = DateTime(now.year, now.month, now.day);
    _monthPageController = PageController(initialPage: _initialPage);
    _multiDayPageController = PageController(initialPage: _initialPage);
    _dailyPageController = PageController(initialPage: _initialPage);
  }

  @override
  void dispose() {
    _monthPageController.dispose();
    _multiDayPageController.dispose();
    _dailyPageController.dispose();
    super.dispose();
  }

  Future<void> _requestCalendarPermission() async {
    // Permission.calendarFullAccess is supported on Android & iOS.
    // Check if the system supports it or if it's already granted.
    try {
      if (await Permission.calendarFullAccess.isDenied) {
        await Permission.calendarFullAccess.request();
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final palette = ref.watch(themeEngineProvider);
    final focusedMonth = ref.watch(focusedMonthProvider);
    final selectedDay = ref.watch(selectedDayProvider);
    final calendarFormat = ref.watch(calendarFormatProvider);
    final settings = ref.watch(appSettingsProvider);
    final calendarView = ref.watch(calendarViewProvider);
    final monthEventsAsync = ref.watch(monthEventsProvider(focusedMonth));

    final syncState = ref.watch(syncServiceProvider);
    final account = ref.watch(googleAccountProvider).value;
    final hasUnsynced = ref.watch(hasUnsyncedChangesProvider).value ?? false;
    final Color titleColor;
    if (account == null) {
      titleColor = palette.text;
    } else if (hasUnsynced) {
      titleColor = Colors.grey;
    } else {
      titleColor = palette.primary;
    }

    // Sync month PageController if changed externally
    final monthDiff = (focusedMonth.year - _anchorDate.year) * 12 + (focusedMonth.month - _anchorDate.month);
    final targetMonthPage = _initialPage + monthDiff;
    if (_monthPageController.hasClients && _monthPageController.page?.round() != targetMonthPage) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_monthPageController.hasClients && _monthPageController.page?.round() != targetMonthPage) {
          _monthPageController.jumpToPage(targetMonthPage);
        }
      });
    }

    // Sync daily PageController if changed externally
    final dayDiff = selectedDay.difference(_anchorDate).inDays;
    final targetDailyPage = _initialPage + dayDiff;
    if (_dailyPageController.hasClients && _dailyPageController.page?.round() != targetDailyPage) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_dailyPageController.hasClients && _dailyPageController.page?.round() != targetDailyPage) {
          _dailyPageController.jumpToPage(targetDailyPage);
        }
      });
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          ref.read(calendarViewProvider.notifier).setView(CalendarView.monthGrid);
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: GestureDetector(
          onTap: () {
            ref.read(syncServiceProvider.notifier).sync();
          },
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Calendar',
                  style: TextStyle(
                    color: titleColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (syncState.isSyncing) ...[
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: titleColor,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          PopupMenuButton<CalendarView>(
            tooltip: 'Change view',
            icon: Icon(Icons.view_module, color: palette.primary),
            onSelected: (view) => ref.read(calendarViewProvider.notifier).setView(view),
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: CalendarView.monthGrid,
                child: Text('Month Grid View'),
              ),
              const PopupMenuItem(
                value: CalendarView.weekTimeline,
                child: Text('Week View'),
              ),
              const PopupMenuItem(
                value: CalendarView.fourDaysTimeline,
                child: Text('4 Days View'),
              ),
              const PopupMenuItem(
                value: CalendarView.threeDaysTimeline,
                child: Text('3 Days View'),
              ),
              const PopupMenuItem(
                value: CalendarView.dailyTimeline,
                child: Text('Daily Timeline'),
              ),
              const PopupMenuItem(
                value: CalendarView.compact,
                child: Text('Compact picker'),
              ),
            ],
          ),
          IconButton(
            tooltip: 'Settings',
            icon: Icon(Icons.settings_outlined, color: palette.primary),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: calendarView == CalendarView.monthGrid
          ? Column(
              children: [
                // Month switcher row for the grid view
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: Icon(Icons.chevron_left, color: palette.text),
                        onPressed: () {
                          ref.read(focusedMonthProvider.notifier).setMonth(DateTime(
                            focusedMonth.year,
                            focusedMonth.month - 1,
                            1,
                          ));
                        },
                      ),
                      Text(
                        _formatMonthYear(focusedMonth),
                        style: TextStyle(
                          color: palette.text,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.chevron_right, color: palette.text),
                        onPressed: () {
                          ref.read(focusedMonthProvider.notifier).setMonth(DateTime(
                            focusedMonth.year,
                            focusedMonth.month + 1,
                            1,
                          ));
                        },
                      ),
                    ],
                  ),
                ),
                // Grid view taking full height
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: palette.surface.withValues(alpha: palette.isAmoled ? 1.0 : 0.5),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: palette.text.withValues(alpha: 0.1), width: 1),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: GlassmorphicWrapper(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: PageView.builder(
                          controller: _monthPageController,
                          onPageChanged: (index) {
                            final diff = index - _initialPage;
                            final targetMonth = DateTime(_anchorDate.year, _anchorDate.month + diff, 1);
                            if (targetMonth != ref.read(focusedMonthProvider)) {
                              ref.read(focusedMonthProvider.notifier).setMonth(targetMonth);
                            }
                          },
                          itemBuilder: (context, index) {
                            final diff = index - _initialPage;
                            final targetMonth = DateTime(_anchorDate.year, _anchorDate.month + diff, 1);
                            return Consumer(
                              builder: (context, ref, _) {
                                final monthAsync = ref.watch(monthEventsProvider(targetMonth));
                                final events = monthAsync.value ?? [];
                                return CalendarMonthGridView(
                                  focusedMonth: targetMonth,
                                  selectedDay: selectedDay,
                                  events: events,
                                  startDayOfWeek: settings.calendarStartDay,
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            )
          : calendarView == CalendarView.weekTimeline ||
                  calendarView == CalendarView.fourDaysTimeline ||
                  calendarView == CalendarView.threeDaysTimeline
              ? Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: palette.surface.withValues(alpha: palette.isAmoled ? 1.0 : 0.5),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: palette.text.withValues(alpha: 0.1), width: 1),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: GlassmorphicWrapper(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: PageView.builder(
                        controller: _multiDayPageController,
                        onPageChanged: (index) {
                          final daysCount = calendarView == CalendarView.weekTimeline
                              ? 7
                              : calendarView == CalendarView.fourDaysTimeline
                                  ? 4
                                  : 3;
                          final dayDiff = (index - _initialPage) * daysCount;
                          final targetDay = _anchorDate.add(Duration(days: dayDiff));
                          ref.read(selectedDayProvider.notifier).setDay(targetDay);
                          if (targetDay.month != focusedMonth.month || targetDay.year != focusedMonth.year) {
                            ref.read(focusedMonthProvider.notifier).setMonth(DateTime(targetDay.year, targetDay.month, 1));
                          }
                        },
                        itemBuilder: (context, index) {
                          final daysCount = calendarView == CalendarView.weekTimeline
                              ? 7
                              : calendarView == CalendarView.fourDaysTimeline
                                  ? 4
                                  : 3;
                          final dayDiff = (index - _initialPage) * daysCount;
                          final targetDay = _anchorDate.add(Duration(days: dayDiff));
                          final targetMonth = DateTime(targetDay.year, targetDay.month, 1);
                          return Consumer(
                            builder: (context, ref, _) {
                              final monthAsync = ref.watch(monthEventsProvider(targetMonth));
                              final events = monthAsync.value ?? [];
                              return CalendarMultiDayTimelineView(
                                selectedDay: targetDay,
                                events: events,
                                daysCount: daysCount,
                                startDayOfWeek: settings.calendarStartDay,
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ),
                )
              : calendarView == CalendarView.dailyTimeline
                  ? Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: palette.surface.withValues(alpha: palette.isAmoled ? 1.0 : 0.5),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: palette.text.withValues(alpha: 0.1), width: 1),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: GlassmorphicWrapper(
                          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                          child: PageView.builder(
                            controller: _dailyPageController,
                            onPageChanged: (index) {
                              final dayDiff = index - _initialPage;
                              final targetDay = _anchorDate.add(Duration(days: dayDiff));
                              ref.read(selectedDayProvider.notifier).setDay(targetDay);
                              if (targetDay.month != focusedMonth.month || targetDay.year != focusedMonth.year) {
                                ref.read(focusedMonthProvider.notifier).setMonth(DateTime(targetDay.year, targetDay.month, 1));
                              }
                            },
                            itemBuilder: (context, index) {
                              final dayDiff = index - _initialPage;
                              final targetDay = _anchorDate.add(Duration(days: dayDiff));
                              final targetMonth = DateTime(targetDay.year, targetDay.month, 1);
                              return Consumer(
                                builder: (context, ref, _) {
                                  final monthAsync = ref.watch(monthEventsProvider(targetMonth));
                                  final events = monthAsync.value ?? [];
                                  return CalendarDailyTimelineView(
                                    selectedDay: targetDay,
                                    events: events,
                                  );
                                },
                              );
                            },
                          ),
                        ),
                      ),
                    )
                  : Column(
              children: [
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: palette.surface.withValues(alpha: palette.isAmoled ? 1.0 : 0.5),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: palette.text.withValues(alpha: 0.1), width: 1),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: GlassmorphicWrapper(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: TableCalendar<CalendarEvent>(
                          firstDay: DateTime.utc(2015, 1, 1),
                          lastDay: DateTime.utc(2035, 12, 31),
                          focusedDay: focusedMonth,
                          calendarFormat: calendarFormat,
                          availableCalendarFormats: const {
                            CalendarFormat.month: 'Month',
                            CalendarFormat.twoWeeks: '2 Weeks',
                            CalendarFormat.week: 'Week',
                          },
                          startingDayOfWeek: _startingDay(settings.calendarStartDay),
                          selectedDayPredicate: (day) => isSameDay(day, selectedDay),
                          eventLoader: (day) => ref.read(dayEventsProvider(day)),
                          onDaySelected: (selected, focused) {
                            ref.read(selectedDayProvider.notifier).setDay(DateTime(
                              selected.year,
                              selected.month,
                              selected.day,
                            ));
                            final normalizedFocused = DateTime(
                              focused.year,
                              focused.month,
                              1,
                            );
                            if (normalizedFocused != focusedMonth) {
                              ref.read(focusedMonthProvider.notifier).setMonth(normalizedFocused);
                            }
                          },
                          onPageChanged: (focused) {
                            ref.read(focusedMonthProvider.notifier).setMonth(DateTime(
                              focused.year,
                              focused.month,
                              1,
                            ));
                          },
                          onFormatChanged: (format) {
                            if (calendarFormat != format) {
                              ref.read(calendarFormatProvider.notifier).setFormat(format);
                            }
                          },
                          calendarStyle: CalendarStyle(
                            markerDecoration: BoxDecoration(color: palette.primary, shape: BoxShape.circle),
                            selectedDecoration: BoxDecoration(color: palette.primary, shape: BoxShape.circle),
                            todayDecoration: BoxDecoration(color: palette.primary.withValues(alpha: 0.3), shape: BoxShape.circle),
                            defaultTextStyle: TextStyle(color: palette.text),
                            weekendTextStyle: TextStyle(color: palette.text.withValues(alpha: 0.6)),
                            outsideTextStyle: TextStyle(color: palette.text.withValues(alpha: 0.3)),
                          ),
                          headerStyle: HeaderStyle(
                            titleTextStyle: TextStyle(color: palette.text, fontSize: 18, fontWeight: FontWeight.bold),
                            formatButtonTextStyle: TextStyle(color: palette.background, fontSize: 12),
                            formatButtonDecoration: BoxDecoration(
                              color: palette.text,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            leftChevronIcon: Icon(Icons.chevron_left, color: palette.text),
                            rightChevronIcon: Icon(Icons.chevron_right, color: palette.text),
                          ),
                          daysOfWeekStyle: DaysOfWeekStyle(
                            weekdayStyle: TextStyle(color: palette.text.withValues(alpha: 0.7)),
                            weekendStyle: TextStyle(color: palette.text.withValues(alpha: 0.5)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: _DayAgenda(
                    day: selectedDay,
                    monthEventsAsync: monthEventsAsync,
                    palette: palette,
                  ),
                ),
              ],
            ),
        ),
      ),
    );
  }

  String _formatMonthYear(DateTime date) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return '${months[date.month - 1]} ${date.year}';
  }

  static StartingDayOfWeek _startingDay(int isoDay) {
    return switch (isoDay) {
      1 => StartingDayOfWeek.monday,
      2 => StartingDayOfWeek.tuesday,
      3 => StartingDayOfWeek.wednesday,
      4 => StartingDayOfWeek.thursday,
      5 => StartingDayOfWeek.friday,
      6 => StartingDayOfWeek.saturday,
      _ => StartingDayOfWeek.sunday,
    };
  }
}

class _DayAgenda extends ConsumerWidget {
  const _DayAgenda({required this.day, required this.monthEventsAsync, required this.palette});

  final DateTime day;
  final AsyncValue<List<CalendarEvent>> monthEventsAsync;
  final AppPalette palette;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return monthEventsAsync.when(
      data: (_) {
        final events = ref.watch(dayEventsProvider(day));
        if (events.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.event_busy, size: 64, color: palette.text.withValues(alpha: 0.1)),
                const SizedBox(height: 16),
                Text(
                  'No events for this day',
                  style: TextStyle(color: palette.text.withValues(alpha: 0.5), fontSize: 16),
                ),
              ],
            ),
          );
        }
        final sorted = [...events]..sort((a, b) => a.start.compareTo(b.start));
        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          itemCount: sorted.length,
          itemBuilder: (context, index) => Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: _EventTile(event: sorted[index], palette: palette),
          ),
        );
      },
      loading: () => const Center(child: AppLoadingIndicator()),
      error: (error, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            error is CalendarNotConnectedException
                ? 'Connect Google Calendar in Settings to see your events.'
                : 'Could not load events: $error',
            textAlign: TextAlign.center,
            style: TextStyle(color: palette.text),
          ),
        ),
      ),
    );
  }
}

class _EventTile extends ConsumerWidget {
  const _EventTile({required this.event, required this.palette});

  final CalendarEvent event;
  final AppPalette palette;

  Color _getTileColor(String? colorId, AppPalette palette) {
    if (colorId != null) {
      if (colorId.startsWith('task:')) {
        final hex = colorId.substring(5);
        if (hex.isNotEmpty) {
          try {
            final c = hex.replaceAll('#', '');
            return Color(int.parse('FF$c', radix: 16));
          } catch (_) {}
        }
        return palette.primary;
      }
      if (colorId.startsWith('habit:')) {
        return palette.secondary;
      }
      final match = GoogleEventColor.options.firstWhere(
        (c) => c.id == colorId,
        orElse: () => GoogleEventColor.options[6],
      );
      return Color(match.hex);
    }
    return Color(GoogleEventColor.options[6].hex);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventColor = _getTileColor(event.colorId, palette);

    return Container(
      decoration: BoxDecoration(
        color: palette.surface.withValues(alpha: palette.isAmoled ? 1.0 : 0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.text.withValues(alpha: 0.05)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: GlassmorphicWrapper(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: Container(
              width: 12,
              height: 40,
              decoration: BoxDecoration(
                color: eventColor,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            title: Text(event.title, style: TextStyle(color: palette.text, fontWeight: FontWeight.bold)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(
                  event.isAllDay
                      ? 'All day'
                      : '${_formatTime(event.start)} – ${_formatTime(event.end)}'
                            '${event.location != null ? ' · ${event.location}' : ''}',
                  style: TextStyle(color: palette.text.withValues(alpha: 0.6)),
                ),
                if (event.tags.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 4,
                    children: event.tags.map((tag) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: eventColor.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(tag, style: TextStyle(color: eventColor, fontSize: 10, fontWeight: FontWeight.bold)),
                    )).toList(),
                  ),
                ],
              ],
            ),
            onTap: () async {
              if (event.id.startsWith('task:')) {
                final taskId = event.id.substring(5);
                final task = await ref.read(taskRepositoryProvider).getTask(taskId);
                if (task != null && context.mounted) {
                  showTaskFormSheet(context, listId: task.listId, existingTask: task); // ignore: unawaited_futures
                }
              } else if (event.id.startsWith('habit:')) {
                final habitId = event.id.split(':')[1];
                final habit = await ref.read(habitRepositoryProvider).getHabit(habitId);
                if (habit != null && context.mounted) {
                  showHabitFormSheet(context, existingHabit: habit); // ignore: unawaited_futures
                }
              } else {
                showEventFormSheet( // ignore: unawaited_futures
                  context,
                  initialDay: event.start,
                  existingEvent: event,
                );
              }
            },
            onLongPress: () => _confirmDelete(context, ref),
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final localDt = dt.toLocal();
    return '${localDt.hour.toString().padLeft(2, '0')}:${localDt.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final isTask = event.id.startsWith('task:');
    final isHabit = event.id.startsWith('habit:');

    if (isTask) {
      final taskId = event.id.substring(5);
      final task = await ref.read(taskRepositoryProvider).getTask(taskId);
      if (task != null) {
        final recurrence = TaskRecurrence.decode(task.recurrenceRule);
        if (recurrence.isRecurring) {
          final choice = await showRecurrenceDeleteDialog(
            context: context, // ignore: use_build_context_synchronously
            ref: ref,
            title: 'Delete Recurring Task?',
          );
          if (choice == null) return;
          if (choice == RecurrenceDeleteType.onlyThis) {
            final nextDue = recurrence.nextOccurrence(task.dueDate!);
            if (nextDue != null) {
              await ref.read(taskRepositoryProvider).updateTask(taskId, dueDate: Value(nextDue));
            }
          } else {
            await ref.read(taskRepositoryProvider).softDeleteTask(taskId);
          }
        } else {
          final confirmed = await showConfirmationDialog(
            context: context, // ignore: use_build_context_synchronously
            ref: ref,
            title: 'Delete Task?',
            content: 'Are you sure you want to delete this task? It will be moved to Trash.',
            confirmLabel: 'Delete',
            isDestructive: true,
          );
          if (confirmed) {
            await ref.read(taskRepositoryProvider).softDeleteTask(taskId);
          }
        }
      }
    } else if (isHabit) {
      final confirmed = await showConfirmationDialog(
        context: context,
        ref: ref,
        title: 'Delete Habit?',
        content: 'Are you sure you want to delete this habit?',
        confirmLabel: 'Delete',
        isDestructive: true,
      );
      if (confirmed) {
        final habitId = event.id.split(':')[1];
        await ref.read(habitRepositoryProvider).deleteHabit(habitId);
      }
    } else {
      final isRecurringEvent = event.recurringEventId != null || (event.recurrence != null && event.recurrence!.isNotEmpty);
      if (isRecurringEvent) {
        final choice = await showRecurrenceDeleteDialog(
          context: context,
          ref: ref,
          title: 'Delete Recurring Event?',
        );
        if (choice == null) return;

        if (choice == RecurrenceDeleteType.onlyThis) {
          await ref.read(calendarRepositoryProvider).deleteEvent(event.id, calendarId: event.calendarId);
        } else if (choice == RecurrenceDeleteType.all) {
          await ref.read(calendarRepositoryProvider).deleteEvent(event.recurringEventId ?? event.id, calendarId: event.calendarId);
        } else if (choice == RecurrenceDeleteType.thisAndAllAfter) {
          await ref.read(calendarRepositoryProvider).deleteThisAndFutureEvents(event);
        }
        ref.invalidate(
          monthEventsProvider(DateTime(event.start.year, event.start.month, 1)),
        );
      } else {
        final confirmed = await showConfirmationDialog(
          context: context,
          ref: ref,
          title: 'Delete Event?',
          content: 'Are you sure you want to permanently delete this event?',
          confirmLabel: 'Delete',
          isDestructive: true,
        );
        if (confirmed) {
          await ref.read(calendarRepositoryProvider).deleteEvent(event.id, calendarId: event.calendarId);
          ref.invalidate(
            monthEventsProvider(DateTime(event.start.year, event.start.month, 1)),
          );
        }
      }
    }
  }
}
