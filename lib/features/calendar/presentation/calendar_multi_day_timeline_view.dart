import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/theme_engine_provider.dart';
import '../../../core/theme/theme_palettes.dart';
import '../application/calendar_providers.dart';
import '../domain/calendar_event.dart';
import 'event_form_sheet.dart';
import '../../tasks/presentation/task_form_sheet.dart';
import '../../tasks/application/task_providers.dart';

class PositionedEvent {
  final CalendarEvent event;
  final double leftFraction;
  final double widthFraction;
  PositionedEvent({
    required this.event,
    required this.leftFraction,
    required this.widthFraction,
  });
}

class CalendarMultiDayTimelineView extends ConsumerWidget {
  const CalendarMultiDayTimelineView({
    required this.selectedDay,
    required this.events,
    required this.daysCount,
    required this.startDayOfWeek,
    super.key,
  });

  final DateTime selectedDay;
  final List<CalendarEvent> events;
  final int daysCount;
  final int startDayOfWeek;

  static const double hourHeight = 80.0;
  static const double timeColumnWidth = 60.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = ref.watch(themeEngineProvider);
    final visibleDays = _calculateVisibleDays(selectedDay, daysCount, startDayOfWeek);
    final gmtOffset = _getGmtOffsetString(selectedDay);

    final scrollController = ScrollController(initialScrollOffset: hourHeight * 7);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Navigation & Switcher Title Header Row
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatHeaderRange(visibleDays),
                style: TextStyle(
                  color: palette.text,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.chevron_left, color: palette.text),
                    onPressed: () {
                      final shiftDays = daysCount == 7 ? 7 : daysCount;
                      final prevDay = selectedDay.subtract(Duration(days: shiftDays));
                      ref.read(selectedDayProvider.notifier).setDay(prevDay);
                      ref.read(focusedMonthProvider.notifier).setMonth(DateTime(
                            prevDay.year,
                            prevDay.month,
                            1,
                          ));
                    },
                  ),
                  IconButton(
                    icon: Icon(Icons.chevron_right, color: palette.text),
                    onPressed: () {
                      final shiftDays = daysCount == 7 ? 7 : daysCount;
                      final nextDay = selectedDay.add(Duration(days: shiftDays));
                      ref.read(selectedDayProvider.notifier).setDay(nextDay);
                      ref.read(focusedMonthProvider.notifier).setMonth(DateTime(
                            nextDay.year,
                            nextDay.month,
                            1,
                          ));
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        // Columns Headers (GMT-03 + SUN 5 + MON 6 etc) + Reserved All-Day space
        Container(
          padding: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: palette.text.withValues(alpha: 0.08), width: 1),
            ),
          ),
          child: Row(
            children: [
              // GMT label column
              Container(
                width: timeColumnWidth,
                alignment: Alignment.center,
                child: Text(
                  gmtOffset,
                  style: TextStyle(
                    color: palette.text.withValues(alpha: 0.4),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              // Day headers columns
              for (final day in visibleDays)
                Expanded(
                  child: Column(
                    children: [
                      // Weekday name (e.g. SUN)
                      Text(
                        _getWeekdayName(day.weekday),
                        style: TextStyle(
                          color: _isSameDay(day, DateTime.now())
                              ? palette.primary
                              : palette.text.withValues(alpha: 0.5),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      // Day number
                      _isSameDay(day, DateTime.now())
                          ? Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: palette.primary,
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                '${day.day}',
                                style: TextStyle(
                                  color: palette.background,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            )
                          : Text(
                              '${day.day}',
                              style: TextStyle(
                                color: palette.text,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                      const SizedBox(height: 6),
                      // Reserved all-day events space for this day
                      ..._buildAllDayEventsForDay(context, ref, day, palette),
                    ],
                  ),
                ),
            ],
          ),
        ),
        // Scrollable timeline columns grid
        Expanded(
          child: SingleChildScrollView(
            controller: scrollController,
            child: Stack(
              children: [
                // Horizontal grid lines and hour labels
                Column(
                  children: [
                    for (int hour = 0; hour <= 24; hour++)
                      SizedBox(
                        height: hourHeight,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Hour label
                            Container(
                              width: timeColumnWidth,
                              padding: const EdgeInsets.only(right: 8, top: 4),
                              alignment: Alignment.topRight,
                              child: Text(
                                _formatHour(hour),
                                style: TextStyle(
                                  color: palette.text.withValues(alpha: 0.4),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            // Horizontal grid line
                            Expanded(
                              child: Container(
                                height: 0.5,
                                color: palette.text.withValues(alpha: 0.08),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                // Layered day columns for timed events
                Positioned.fill(
                  left: timeColumnWidth,
                  child: Row(
                    children: [
                      for (final day in visibleDays)
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border(
                                right: BorderSide(
                                  color: palette.text.withValues(alpha: 0.04),
                                  width: 0.5,
                                ),
                              ),
                            ),
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final width = constraints.maxWidth;
                                final timedEvents = _getTimedEventsForDay(day);
                                final positionedEvents = _layoutEvents(timedEvents);

                                return Stack(
                                  children: [
                                    for (final pe in positionedEvents)
                                      _buildEventCard(
                                        context,
                                        ref,
                                        pe.event,
                                        pe.leftFraction * width,
                                        pe.widthFraction * width,
                                        palette,
                                      ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildAllDayEventsForDay(
    BuildContext context,
    WidgetRef ref,
    DateTime day,
    AppPalette palette,
  ) {
    final allDayList = events.where((e) {
      if (!e.isAllDay) return false;
      final targetDay = DateTime(day.year, day.month, day.day);
      final startZero = DateTime(e.start.year, e.start.month, e.start.day);
      final endZero = DateTime(e.end.year, e.end.month, e.end.day);
      return !targetDay.isBefore(startZero) && targetDay.isBefore(endZero);
    }).toList();

    return [
      for (final event in allDayList)
        GestureDetector(
          onTap: () => _onEventTapped(context, ref, event),
          child: Container(
            margin: const EdgeInsets.only(top: 2, left: 2, right: 2),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2.5),
            decoration: BoxDecoration(
              color: _getEventColor(event.colorId, palette).withValues(alpha: 0.85),
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
        ),
    ];
  }

  List<CalendarEvent> _getTimedEventsForDay(DateTime day) {
    return events.where((e) {
      if (e.isAllDay) return false;
      final targetDay = DateTime(day.year, day.month, day.day);
      final eventDay = DateTime(e.start.year, e.start.month, e.start.day);
      return eventDay == targetDay;
    }).toList();
  }

  Widget _buildEventCard(
    BuildContext context,
    WidgetRef ref,
    CalendarEvent event,
    double left,
    double width,
    AppPalette palette,
  ) {
    final startLocal = event.start.toLocal();
    final endLocal = event.end.toLocal();

    final double top = _getTopOffset(startLocal);
    final double height = _getHeight(startLocal, endLocal);
    final Color eventColor = _getEventColor(event.colorId, palette);

    return Positioned(
      top: top + 1,
      left: left + 2,
      width: width - 4,
      height: height - 2,
      child: GestureDetector(
        onTap: () => _onEventTapped(context, ref, event),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: eventColor.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                event.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 10,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 1),
              Text(
                '${_formatTime(startLocal)} – ${_formatTime(endLocal)}',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 8,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  double _getTopOffset(DateTime time) {
    return (time.hour + time.minute / 60.0) * hourHeight;
  }

  double _getHeight(DateTime start, DateTime end) {
    final duration = end.difference(start).inMinutes;
    final actualDuration = duration <= 0 ? 30 : duration;
    return (actualDuration / 60.0) * hourHeight;
  }

  Color _getEventColor(String? colorId, AppPalette palette) {
    if (colorId == null) return palette.primary;
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
    final match = GoogleEventColor.options.firstWhere(
      (c) => c.id == colorId,
      orElse: () => const GoogleEventColor('0', 'Default', 0),
    );
    if (match.id == '0') return palette.primary;
    return Color(match.hex);
  }

  void _onEventTapped(BuildContext context, WidgetRef ref, CalendarEvent event) async {
    if (event.id.startsWith('task:')) {
      final taskId = event.id.substring(5);
      final task = await ref.read(taskRepositoryProvider).getTask(taskId);
      if (task != null && context.mounted) {
        showTaskFormSheet(context, listId: task.listId, existingTask: task);
      }
    } else {
      showEventFormSheet(context, initialDay: event.start, existingEvent: event);
    }
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _formatHour(int hour) {
    return '${hour.toString().padLeft(2, '0')}:00';
  }

  String _getGmtOffsetString(DateTime date) {
    final offset = date.timeZoneOffset;
    final hours = offset.inHours.abs().toString().padLeft(2, '0');
    final sign = offset.isNegative ? '-' : '+';
    return 'GMT$sign$hours';
  }

  String _getWeekdayName(int weekday) {
    return switch (weekday) {
      1 => 'MON',
      2 => 'TUE',
      3 => 'WED',
      4 => 'THU',
      5 => 'FRI',
      6 => 'SAT',
      _ => 'SUN',
    };
  }

  List<DateTime> _calculateVisibleDays(DateTime baseDay, int daysCount, int startDayOfWeek) {
    if (daysCount == 7) {
      int diff = baseDay.weekday - startDayOfWeek;
      if (diff < 0) {
        diff += 7;
      }
      final startOfWeek = baseDay.subtract(Duration(days: diff));
      return List.generate(7, (index) => startOfWeek.add(Duration(days: index)));
    } else {
      return List.generate(daysCount, (index) => baseDay.add(Duration(days: index)));
    }
  }

  String _formatHeaderRange(List<DateTime> visibleDays) {
    final first = visibleDays.first;
    final last = visibleDays.last;
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];

    if (first.year != last.year) {
      return '${months[first.month - 1]} ${first.year} – ${months[last.month - 1]} ${last.year}';
    } else if (first.month != last.month) {
      return '${months[first.month - 1]} – ${months[last.month - 1]} ${first.year}';
    } else {
      return '${months[first.month - 1]} ${first.year}';
    }
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  List<PositionedEvent> _layoutEvents(List<CalendarEvent> dayTimedEvents) {
    final positioned = <PositionedEvent>[];
    dayTimedEvents.sort((a, b) => a.start.compareTo(b.start));

    final groups = <List<CalendarEvent>>[];
    for (final event in dayTimedEvents) {
      List<CalendarEvent>? matchedGroup;
      for (final group in groups) {
        final overlaps = group.any((e) =>
            event.start.isBefore(e.end) && event.end.isAfter(e.start));
        if (overlaps) {
          matchedGroup = group;
          break;
        }
      }
      if (matchedGroup != null) {
        matchedGroup.add(event);
      } else {
        groups.add([event]);
      }
    }

    for (final group in groups) {
      final count = group.length;
      for (int i = 0; i < count; i++) {
        final e = group[i];
        positioned.add(PositionedEvent(
          event: e,
          leftFraction: i / count,
          widthFraction: 1.0 / count,
        ));
      }
    }
    return positioned;
  }
}
