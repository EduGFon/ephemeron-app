import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../core/settings/app_settings_provider.dart';
import '../../../core/theme/theme_engine_provider.dart';
import '../../../core/theme/theme_palettes.dart';
import '../../settings/presentation/settings_screen.dart';
import '../application/calendar_providers.dart';
import '../data/calendar_repository.dart';
import '../domain/calendar_event.dart';
import 'calendar_daily_timeline_view.dart';
import 'calendar_month_grid_view.dart';
import 'event_form_sheet.dart';

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

class CalendarScreen extends ConsumerWidget {
  const CalendarScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = ref.watch(themeEngineProvider);
    final focusedMonth = ref.watch(focusedMonthProvider);
    final selectedDay = ref.watch(selectedDayProvider);
    final calendarFormat = ref.watch(calendarFormatProvider);
    final settings = ref.watch(appSettingsProvider);
    final monthEventsAsync = ref.watch(monthEventsProvider(focusedMonth));
    final calendarView = ref.watch(calendarViewProvider);

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
        title: Text('Calendar', style: TextStyle(color: palette.text, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Sync now',
            icon: monthEventsAsync.isLoading
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: palette.primary),
                  )
                : Icon(Icons.sync, color: palette.primary),
            onPressed: monthEventsAsync.isLoading
                ? null
                : () => ref.invalidate(monthEventsProvider(focusedMonth)),
          ),
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
              // Will navigate to Calendar settings / sync settings in Phase 4
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
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: monthEventsAsync.when(
                          data: (events) => CalendarMonthGridView(
                            focusedMonth: focusedMonth,
                            selectedDay: selectedDay,
                            events: events,
                            startDayOfWeek: settings.calendarStartDay,
                          ),
                          loading: () => const Center(child: CircularProgressIndicator()),
                          error: (err, _) => Center(child: Text('Error loading events: $err')),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ).animate().fadeIn(duration: 400.ms)
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
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: monthEventsAsync.when(
                        data: (events) => CalendarDailyTimelineView(
                          selectedDay: selectedDay,
                          events: events,
                        ),
                        loading: () => const Center(child: CircularProgressIndicator()),
                        error: (err, _) => Center(child: Text('Error loading events: $err')),
                      ),
                    ),
                  ),
                ).animate().fadeIn(duration: 400.ms)
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
                    child: BackdropFilter(
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
                ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.1),
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
            ).animate().fadeIn(),
          );
        }
        final sorted = [...events]..sort((a, b) => a.start.compareTo(b.start));
        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          itemCount: sorted.length,
          itemBuilder: (context, index) => Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: _EventTile(event: sorted[index], palette: palette).animate().fadeIn(delay: (index * 50).ms).slideX(begin: 0.1),
          ),
        );
      },
      loading: () => Center(child: CircularProgressIndicator(color: palette.primary)),
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = GoogleEventColor.options.firstWhere(
      (c) => c.id == event.colorId,
      orElse: () => GoogleEventColor.options[6],
    );

    return Container(
      decoration: BoxDecoration(
        color: palette.surface.withValues(alpha: palette.isAmoled ? 1.0 : 0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.text.withValues(alpha: 0.05)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: Container(
              width: 12,
              height: 40,
              decoration: BoxDecoration(
                color: Color(color.hex),
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
                        color: Color(color.hex).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(tag, style: TextStyle(color: Color(color.hex), fontSize: 10, fontWeight: FontWeight.bold)),
                    )).toList(),
                  ),
                ],
              ],
            ),
            onTap: () => showEventFormSheet(
              context,
              initialDay: event.start,
              existingEvent: event,
            ),
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete event?'),
        content: Text(event.title),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(calendarRepositoryProvider).deleteEvent(event.id);
    ref.invalidate(
      monthEventsProvider(DateTime(event.start.year, event.start.month, 1)),
    );
  }
}
