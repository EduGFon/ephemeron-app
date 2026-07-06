import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/theme_engine_provider.dart';
import '../../../core/theme/theme_palettes.dart';
import '../application/calendar_providers.dart';
import '../domain/calendar_event.dart';
import 'event_form_sheet.dart';

class CalendarMonthGridView extends ConsumerWidget {
  const CalendarMonthGridView({
    required this.focusedMonth,
    required this.selectedDay,
    required this.events,
    required this.startDayOfWeek,
    super.key,
  });

  final DateTime focusedMonth;
  final DateTime selectedDay;
  final List<CalendarEvent> events;
  final int startDayOfWeek; // 1 = Mon, 7 = Sun (ISO)

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = ref.watch(themeEngineProvider);
    final gridDays = _generateGridDays(focusedMonth, startDayOfWeek);
    final weekdayHeaders = _getWeekdayHeaders(startDayOfWeek);

    return LayoutBuilder(
      builder: (context, constraints) {
        // Leave space for the weekday headers at the top
        final availableHeight = constraints.maxHeight - 32;
        final rowHeight = availableHeight / 6;

        return Column(
          children: [
            // Weekday Headers row (SUN, MON, TUE, etc.)
            Row(
              children: [
                // Narrow empty spacer for week number column
                const SizedBox(width: 24),
                for (final weekday in weekdayHeaders)
                  Expanded(
                    child: Container(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                        weekday,
                        style: TextStyle(
                          color: palette.text.withValues(alpha: 0.5),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            // Month calendar grid (6 rows of weeks)
            Expanded(
              child: Column(
                children: [
                  for (int weekIndex = 0; weekIndex < 6; weekIndex++)
                    Expanded(
                      child: Row(
                        children: [
                          // Week number column (e.g. 27, 28, 29)
                          Container(
                            width: 24,
                            height: rowHeight,
                            alignment: Alignment.center,
                            child: Text(
                              '${_weekNumber(gridDays[weekIndex * 7])}',
                              style: TextStyle(
                                color: palette.text.withValues(alpha: 0.3),
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          // 7 days of this week
                          for (int dayIndex = 0; dayIndex < 7; dayIndex++)
                            Expanded(
                              child: _buildDayCell(
                                context,
                                ref,
                                gridDays[weekIndex * 7 + dayIndex],
                                rowHeight,
                                palette,
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDayCell(
    BuildContext context,
    WidgetRef ref,
    DateTime day,
    double height,
    AppPalette palette,
  ) {
    final isToday = _isSameDay(day, DateTime.now());
    final isSelected = _isSameDay(day, selectedDay);
    final isCurrentMonth = day.month == focusedMonth.month;

    // Filter events for this specific day
    final dayEvents = events.where((e) {
      final eventDay = DateTime(e.start.year, e.start.month, e.start.day);
      final targetDay = DateTime(day.year, day.month, day.day);
      
      if (e.isAllDay) {
        // Multi-day all-day event checks
        final startZero = DateTime(e.start.year, e.start.month, e.start.day);
        final endZero = DateTime(e.end.year, e.end.month, e.end.day);
        return !targetDay.isBefore(startZero) && targetDay.isBefore(endZero);
      }
      
      return eventDay == targetDay;
    }).toList();

    final availableEventsHeight = height - 24.0;
    final maxEvents = (availableEventsHeight / 14.5).floor();
    final maxFit = maxEvents < 1 ? 1 : maxEvents;
    final showMore = dayEvents.length > maxFit;
    final displayCount = showMore ? maxFit - 1 : dayEvents.length;

    // Format date text: display month abbreviation on first day (e.g. "Jul 1")
    String dateText = '${day.day}';
    if (day.day == 1) {
      dateText = '${_monthAbbr(day.month)} 1';
    }

    return GestureDetector(
      onTap: () {
        ref.read(selectedDayProvider.notifier).setDay(DateTime(day.year, day.month, day.day));
      },
      onDoubleTap: () {
        ref.read(selectedDayProvider.notifier).setDay(DateTime(day.year, day.month, day.day));
        ref.read(calendarViewProvider.notifier).setView(CalendarView.dailyTimeline);
      },
      child: Container(
        height: height,
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: palette.text.withValues(alpha: 0.08), width: 0.5),
            left: BorderSide(color: palette.text.withValues(alpha: 0.08), width: 0.5),
            right: day.weekday == startDayOfWeek - 1 || (startDayOfWeek == 1 && day.weekday == 7)
                ? BorderSide(color: palette.text.withValues(alpha: 0.08), width: 0.5)
                : BorderSide.none,
            bottom: BorderSide(color: palette.text.withValues(alpha: 0.08), width: 0.5),
          ),
          color: isSelected
              ? palette.primary.withValues(alpha: 0.05)
              : Colors.transparent,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Day Number indicator at the top
            Padding(
              padding: const EdgeInsets.only(top: 4, right: 6, left: 4),
              child: Align(
                alignment: Alignment.topRight,
                child: isToday
                    ? Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: palette.primary,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          dateText,
                          style: TextStyle(
                            color: palette.background,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      )
                    : Text(
                        dateText,
                        style: TextStyle(
                          color: isCurrentMonth
                              ? palette.text.withValues(alpha: 0.8)
                              : palette.text.withValues(alpha: 0.3),
                          fontSize: 11,
                          fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
              ),
            ),
            // Events list space
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: showMore ? displayCount + 1 : displayCount,
                  itemBuilder: (context, index) {
                    if (showMore && index == displayCount) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                        child: Text(
                          '+${dayEvents.length - displayCount} more',
                          style: TextStyle(
                            color: palette.text.withValues(alpha: 0.4),
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      );
                    }
                    return _buildEventItem(context, ref, dayEvents[index], palette);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEventItem(
    BuildContext context,
    WidgetRef ref,
    CalendarEvent event,
    AppPalette palette,
  ) {
    final eventColor = _getEventColor(event.colorId, palette);

    if (event.isAllDay) {
      // Rounded colored block for All-day events
      return GestureDetector(
        onTap: () => showEventFormSheet(context, initialDay: event.start, existingEvent: event),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 1, horizontal: 2),
          padding: const EdgeInsets.symmetric(vertical: 1.5, horizontal: 4),
          decoration: BoxDecoration(
            color: eventColor.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            event.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 9,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
    } else {
      // Small dot + Time + Title for Timed events
      return GestureDetector(
        onTap: () => showEventFormSheet(context, initialDay: event.start, existingEvent: event),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 0.5),
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Row(
            children: [
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  color: eventColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 3),
              Text(
                _formatEventTime(event.start),
                style: TextStyle(
                  color: palette.text,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 3),
              Expanded(
                child: Text(
                  event.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.text.withValues(alpha: 0.9),
                    fontSize: 9,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  Color _getEventColor(String? colorId, AppPalette palette) {
    if (colorId == null) return palette.primary;
    final match = GoogleEventColor.options.firstWhere(
      (c) => c.id == colorId,
      orElse: () => const GoogleEventColor('0', 'Default', 0),
    );
    if (match.id == '0') return palette.primary;
    return Color(match.hex);
  }

  String _formatEventTime(DateTime dt) {
    final localDt = dt.toLocal();
    return '${localDt.hour.toString().padLeft(2, '0')}:${localDt.minute.toString().padLeft(2, '0')}';
  }

  String _monthAbbr(int month) {
    return switch (month) {
      1 => 'Jan',
      2 => 'Feb',
      3 => 'Mar',
      4 => 'Apr',
      5 => 'May',
      6 => 'Jun',
      7 => 'Jul',
      8 => 'Aug',
      9 => 'Sep',
      10 => 'Oct',
      11 => 'Nov',
      _ => 'Dec',
    };
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  int _weekNumber(DateTime date) {
    final firstDayOfYear = DateTime(date.year, 1, 1);
    final days = date.difference(firstDayOfYear).inDays;
    return ((days + firstDayOfYear.weekday - 1) / 7).floor() + 1;
  }

  DateTime _getGridStartDate(DateTime month, int startDayOfWeek) {
    final firstOfMonth = DateTime(month.year, month.month, 1);
    int daysBefore = firstOfMonth.weekday - startDayOfWeek;
    if (daysBefore < 0) {
      daysBefore += 7;
    }
    return firstOfMonth.subtract(Duration(days: daysBefore));
  }

  List<DateTime> _generateGridDays(DateTime month, int startDayOfWeek) {
    final startDate = _getGridStartDate(month, startDayOfWeek);
    return List.generate(42, (index) => startDate.add(Duration(days: index)));
  }

  List<String> _getWeekdayHeaders(int startDayOfWeek) {
    const weekdays = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    final list = <String>[];
    for (int i = 0; i < 7; i++) {
      final index = (startDayOfWeek - 1 + i) % 7;
      list.add(weekdays[index]);
    }
    return list;
  }
}
