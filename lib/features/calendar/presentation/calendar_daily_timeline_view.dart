import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' show Value;

import '../../../core/theme/theme_engine_provider.dart';
import '../../../core/theme/theme_palettes.dart';
import '../application/calendar_providers.dart';
import '../domain/calendar_event.dart';
import 'event_form_sheet.dart';
import '../../tasks/presentation/task_form_sheet.dart';
import '../../tasks/application/task_providers.dart';
import '../../habits/presentation/habit_form_sheet.dart';
import '../../habits/application/habit_providers.dart';

class CalendarDailyTimelineView extends ConsumerStatefulWidget {
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
  ConsumerState<CalendarDailyTimelineView> createState() => _CalendarDailyTimelineViewState();
}

class _CalendarDailyTimelineViewState extends ConsumerState<CalendarDailyTimelineView> {
  String? _draggingEventId;
  double _dragCurrentTop = 0.0;
  DateTime? _dragCurrentStart;
  DateTime? _dragCurrentEnd;
  late final ScrollController _scrollController;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController(
      initialScrollOffset: CalendarDailyTimelineView.hourHeight * 7,
    );
    _timer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  DateTime _getDateTimeFromTop(double top, DateTime originalStart) {
    final totalMinutes = (top / CalendarDailyTimelineView.hourHeight * 60.0).round();
    final snappedMinutes = (totalMinutes / 15.0).round() * 15;
    final clampedMinutes = snappedMinutes.clamp(0, 24 * 60 - 15);
    final hour = clampedMinutes ~/ 60;
    final minute = clampedMinutes % 60;
    return DateTime(originalStart.year, originalStart.month, originalStart.day, hour, minute);
  }

  @override
  Widget build(BuildContext context) {
    final palette = ref.watch(themeEngineProvider);

    // Filter events for the selected day
    final dayEvents = widget.events.where((e) {
      final targetDay = DateTime(widget.selectedDay.year, widget.selectedDay.month, widget.selectedDay.day);
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

    final gmtOffset = _getGmtOffsetString(widget.selectedDay);
    final weekdayName = _getWeekdayName(widget.selectedDay.weekday);

    final now = DateTime.now();
    final isToday = widget.selectedDay.year == now.year &&
        widget.selectedDay.month == now.month &&
        widget.selectedDay.day == now.day;

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
                    '${widget.selectedDay.day}',
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
                        widget.selectedDay.subtract(const Duration(days: 1)),
                      );
                      ref.read(focusedMonthProvider.notifier).setMonth(DateTime(
                        widget.selectedDay.year,
                        widget.selectedDay.month,
                        1,
                      ));
                    },
                  ),
                  IconButton(
                    icon: Icon(Icons.chevron_right, color: palette.text),
                    onPressed: () {
                      ref.read(selectedDayProvider.notifier).setDay(
                        widget.selectedDay.add(const Duration(days: 1)),
                      );
                      ref.read(focusedMonthProvider.notifier).setMonth(DateTime(
                        widget.selectedDay.year,
                        widget.selectedDay.month,
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
            controller: _scrollController,
            child: Stack(
              children: [
                // Horizontal grid lines and hour labels
                Column(
                  children: [
                    for (int hour = 0; hour <= 24; hour++)
                      SizedBox(
                        height: CalendarDailyTimelineView.hourHeight,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Hour label
                            Container(
                              width: CalendarDailyTimelineView.timeColumnWidth,
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
                  left: CalendarDailyTimelineView.timeColumnWidth,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final width = constraints.maxWidth;
                      final positionedEvents = _layoutEvents(timedEvents);
                      return Stack(
                        children: [
                          for (final pe in positionedEvents)
                            _buildTimelineEventCard(
                              context,
                              ref,
                              pe.event,
                              pe.leftFraction * (width - 16) + 8,
                              pe.widthFraction * (width - 16),
                              palette,
                            ),
                        ],
                      );
                    },
                  ),
                ),
                if (isToday)
                  Positioned(
                    top: _getTopOffset(now) - 4, // Center the 8px dot/line vertically
                    left: CalendarDailyTimelineView.timeColumnWidth - 4,
                    right: 0,
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Colors.redAccent,
                            shape: BoxShape.circle,
                          ),
                        ),
                        Expanded(
                          child: Container(
                            height: 2,
                            color: Colors.redAccent,
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

  Widget _buildTimelineEventCard(
    BuildContext context,
    WidgetRef ref,
    CalendarEvent event,
    double left,
    double width,
    AppPalette palette,
  ) {
    final startLocal = _draggingEventId == event.id ? _dragCurrentStart! : event.start.toLocal();
    final endLocal = _draggingEventId == event.id ? _dragCurrentEnd! : event.end.toLocal();

    // Calculate vertical offset and height
    final double top = _draggingEventId == event.id ? _dragCurrentTop : _getTopOffset(startLocal);
    final double height = _getHeight(startLocal, endLocal);
    final Color eventColor = _getEventColor(event.colorId, palette);

    final showTime = height >= 42;
    final paddingVertical = height < 50 ? 4.0 : 8.0;
    final paddingHorizontal = height < 50 ? 8.0 : 12.0;

    return Positioned(
      top: top + 1, // small offset to avoid overlaying the line
      left: left,
      width: width,
      height: height - 2,
      child: GestureDetector(
        onTap: () => _onEventTapped(context, ref, event),
        onVerticalDragStart: (details) {
          final sLocal = event.start.toLocal();
          final duration = event.end.difference(event.start);
          setState(() {
            _draggingEventId = event.id;
            _dragCurrentTop = _getTopOffset(sLocal);
            _dragCurrentStart = sLocal;
            _dragCurrentEnd = sLocal.add(duration);
          });
        },
        onVerticalDragUpdate: (details) {
          if (_draggingEventId == event.id) {
            final duration = event.end.difference(event.start);
            setState(() {
              _dragCurrentTop += details.primaryDelta ?? 0.0;
              _dragCurrentTop = _dragCurrentTop.clamp(0.0, 24.0 * CalendarDailyTimelineView.hourHeight);
              _dragCurrentStart = _getDateTimeFromTop(_dragCurrentTop, event.start.toLocal());
              _dragCurrentEnd = _dragCurrentStart!.add(duration);
            });
          }
        },
        onVerticalDragEnd: (details) async {
          if (_draggingEventId == event.id) {
            final newStart = _dragCurrentStart!;
            final newEnd = _dragCurrentEnd!;
            final oldDraggingId = _draggingEventId!;

            setState(() {
              _draggingEventId = null;
              _dragCurrentStart = null;
              _dragCurrentEnd = null;
            });

            final taskRepo = ref.read(taskRepositoryProvider);
            final calendarRepo = ref.read(calendarRepositoryProvider);

            if (oldDraggingId.startsWith('task:')) {
              final taskId = oldDraggingId.substring(5);
              await taskRepo.updateTask(
                taskId,
                dueDate: Value(newStart),
                dueHasTime: true,
              );
            } else {
              final originalEvent = widget.events.firstWhere((e) => e.id == oldDraggingId);
              final updated = originalEvent.copyWith(
                start: newStart,
                end: newEnd,
              );
              await calendarRepo.updateEvent(updated);
            }
            if (mounted) {
              ref.invalidate(monthEventsProvider(DateTime(newStart.year, newStart.month, 1)));
            }
          }
        },
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: paddingHorizontal, vertical: paddingVertical),
          decoration: BoxDecoration(
            color: eventColor.withValues(alpha: _draggingEventId == event.id ? 0.7 : 0.85),
            borderRadius: BorderRadius.circular(height < 50 ? 8 : 12),
            boxShadow: [
              if (height >= 30)
                BoxShadow(
                  color: Colors.black.withValues(alpha: _draggingEventId == event.id ? 0.2 : 0.1),
                  blurRadius: _draggingEventId == event.id ? 8 : 4,
                  offset: Offset(0, _draggingEventId == event.id ? 4 : 2),
                ),
            ],
          ),
          child: ClipRect(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      if (event.id.startsWith('task:')) ...[
                        GestureDetector(
                          onTap: () {
                            final taskId = event.id.substring(5);
                            final isCompleted = event.title.startsWith('✓ ');
                            final repo = ref.read(taskRepositoryProvider);
                            if (isCompleted) {
                              repo.uncompleteTask(taskId);
                            } else {
                              repo.completeTask(taskId);
                            }
                          },
                          child: Container(
                            width: height < 50 ? 14 : 18,
                            height: height < 50 ? 14 : 18,
                            margin: const EdgeInsets.only(right: 6),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white.withValues(alpha: 0.8), width: 1.5),
                              color: event.title.startsWith('✓ ')
                                  ? Colors.white.withValues(alpha: 0.2)
                                  : Colors.transparent,
                            ),
                            child: event.title.startsWith('✓ ')
                                ? Icon(Icons.check, size: height < 50 ? 10 : 12, color: Colors.white)
                                : null,
                          ),
                        ),
                      ] else if (event.id.startsWith('habit:')) ...[
                        GestureDetector(
                          onTap: () async {
                            final parts = event.id.split(':');
                            final habitId = parts[1];
                            final dateStr = parts[2];
                            final date = DateTime.parse(dateStr);
                            await ref.read(habitRepositoryProvider).toggleBinary(habitId, date);
                          },
                          child: Container(
                            width: height < 50 ? 14 : 18,
                            height: height < 50 ? 14 : 18,
                            margin: const EdgeInsets.only(right: 6),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white.withValues(alpha: 0.8), width: 1.5),
                              color: event.title.startsWith('✓ ')
                                  ? Colors.white.withValues(alpha: 0.2)
                                  : Colors.transparent,
                            ),
                            child: event.title.startsWith('✓ ')
                                ? Icon(Icons.check, size: height < 50 ? 10 : 12, color: Colors.white)
                                : null,
                          ),
                        ),
                      ],
                      Expanded(
                        child: Text(
                          (event.id.startsWith('task:') || event.id.startsWith('habit:')) ? event.title.substring(2) : event.title,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: height < 50 ? 11 : 13,
                            decoration: event.title.startsWith('✓ ') ? TextDecoration.lineThrough : null,
                          ),
                          maxLines: height < 50 ? 1 : 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                if (showTime) ...[
                  const SizedBox(height: 2),
                  Text(
                    event.isAllDay
                        ? 'All day'
                        : '${_formatTime(startLocal)} – ${_formatTime(endLocal)}',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: height < 50 ? 9 : 11,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  double _getTopOffset(DateTime time) {
    return (time.hour + time.minute / 60.0) * CalendarDailyTimelineView.hourHeight;
  }

  double _getHeight(DateTime start, DateTime end) {
    final duration = end.difference(start).inMinutes;
    // Minimum 30 minutes height representation
    final actualDuration = duration <= 0 ? 30 : duration;
    return (actualDuration / 60.0) * CalendarDailyTimelineView.hourHeight;
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
    if (colorId.startsWith('habit:')) {
      return palette.secondary;
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
    } else if (event.id.startsWith('habit:')) {
      final habitId = event.id.split(':')[1];
      final habit = await ref.read(habitRepositoryProvider).getHabit(habitId);
      if (habit != null && context.mounted) {
        showHabitFormSheet(context, existingHabit: habit);
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
