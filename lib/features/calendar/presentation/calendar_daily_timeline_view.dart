import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/theme_engine_provider.dart';
import '../../../core/theme/theme_palettes.dart';
import '../application/calendar_providers.dart';
import '../domain/calendar_event.dart';
import 'event_form_sheet.dart';
import '../../tasks/presentation/task_form_sheet.dart';
import '../../tasks/application/task_providers.dart';

class CalendarDailyTimelineView extends ConsumerWidget {
  const CalendarDailyTimelineView({
    required this.selectedDay,
    required this.events,
    super.key,
  });

  final DateTime selectedDay;
  final List<CalendarEvent> events;

  static const double hourHeight = 80.0;
  static const double timeColumnWidth = 60.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = ref.watch(themeEngineProvider);

    // Filter events for the selected day
    final dayEvents = events.where((e) {
      final targetDay = DateTime(selectedDay.year, selectedDay.month, selectedDay.day);
      if (e.isAllDay) {
        final startZero = DateTime(e.start.year, e.start.month, e.start.day);
        final endZero = DateTime(e.end.year, e.end.month, e.end.day);
        return !targetDay.isBefore(startZero) && targetDay.isBefore(endZero);
      }
      final eventDay = DateTime(e.start.year, e.start.month, e.start.day);
      return eventDay == targetDay;
    }).toList();

    final allDayEvents = dayEvents.where((e) => e.isAllDay).toList();
    final timedEvents = dayEvents.where((e) => !e.isAllDay).toList();

    final gmtOffset = _getGmtOffsetString(selectedDay);
    final weekdayName = _getWeekdayName(selectedDay.weekday);

    // Timeline hours range from 00:00 to 24:00.
    // We scroll automatically to show morning hours (e.g. 07:00) by default.
    final scrollController = ScrollController(initialScrollOffset: hourHeight * 7);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Daily header details (THU / 9 / GMT-03)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    weekdayName,
                    style: TextStyle(
                      color: palette.text.withValues(alpha: 0.5),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                    ),
                  ),
                  Text(
                    '${selectedDay.day}',
                    style: TextStyle(
                      color: palette.text,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    gmtOffset,
                    style: TextStyle(
                      color: palette.text.withValues(alpha: 0.4),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              // Chevrons to navigate days
              Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.chevron_left, color: palette.text),
                    onPressed: () {
                      ref.read(selectedDayProvider.notifier).setDay(
                        selectedDay.subtract(const Duration(days: 1)),
                      );
                      ref.read(focusedMonthProvider.notifier).setMonth(DateTime(
                        selectedDay.year,
                        selectedDay.month,
                        1,
                      ));
                    },
                  ),
                  IconButton(
                    icon: Icon(Icons.chevron_right, color: palette.text),
                    onPressed: () {
                      ref.read(selectedDayProvider.notifier).setDay(
                        selectedDay.add(const Duration(days: 1)),
                      );
                      ref.read(focusedMonthProvider.notifier).setMonth(DateTime(
                        selectedDay.year,
                        selectedDay.month,
                        1,
                      ));
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        // Reserved space for All-day events
        if (allDayEvents.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ALL-DAY EVENTS',
                  style: TextStyle(
                    color: palette.text.withValues(alpha: 0.4),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final event in allDayEvents)
                      GestureDetector(
                        onTap: () => _onEventTapped(context, ref, event),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: _getEventColor(event.colorId, palette).withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            event.title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Divider(color: palette.text.withValues(alpha: 0.08), height: 1),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ],
        // Scrollable Timeline grid
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
                                  fontSize: 11,
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
                // Stacked events layered over the timeline
                Positioned.fill(
                  left: timeColumnWidth,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final width = constraints.maxWidth;
                      return Stack(
                        children: [
                          for (final event in timedEvents)
                            _buildTimelineEventCard(context, ref, event, width, palette),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTimelineEventCard(
    BuildContext context,
    WidgetRef ref,
    CalendarEvent event,
    double maxWidth,
    AppPalette palette,
  ) {
    final startLocal = event.start.toLocal();
    final endLocal = event.end.toLocal();

    // Calculate vertical offset and height
    final double top = _getTopOffset(startLocal);
    final double height = _getHeight(startLocal, endLocal);
    final Color eventColor = _getEventColor(event.colorId, palette);

    return Positioned(
      top: top + 1, // small offset to avoid overlaying the line
      left: 8,
      width: maxWidth - 16,
      height: height - 2,
      child: GestureDetector(
        onTap: () => _onEventTapped(context, ref, event),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: eventColor.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                event.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                event.isAllDay
                    ? 'All day'
                    : '${_formatTime(startLocal)} – ${_formatTime(endLocal)}',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
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
    // Minimum 30 minutes height representation
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
}
