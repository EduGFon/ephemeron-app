import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/theme_engine_provider.dart';
import '../../../core/theme/theme_palettes.dart';
import '../application/calendar_providers.dart';
import '../domain/calendar_event.dart';
import 'event_form_sheet.dart';
import '../../tasks/presentation/task_form_sheet.dart';
import '../../tasks/application/task_providers.dart';
import '../../habits/presentation/habit_form_sheet.dart';
import '../../habits/application/habit_providers.dart';
import 'package:drift/drift.dart' show Value;
import '../data/calendar_repository.dart';

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

class CalendarMultiDayTimelineView extends ConsumerStatefulWidget {
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
  ConsumerState<CalendarMultiDayTimelineView> createState() => _CalendarMultiDayTimelineViewState();
}

class _CalendarMultiDayTimelineViewState extends ConsumerState<CalendarMultiDayTimelineView> {
  String? _draggingEventId;
  double _dragCurrentTop = 0.0;
  double _dragOriginalTop = 0.0;
  DateTime? _dragCurrentStart;
  DateTime? _dragCurrentEnd;
  final Map<String, ({DateTime start, DateTime end})> _pendingMovedEvents = {};
  late final ScrollController _scrollController;
  double _baseHourHeight = 80.0;

  @override
  void initState() {
    super.initState();
    final hourHeight = ref.read(calendarHourHeightProvider);
    final initialOffset = _calculateInitialScrollOffset(
      widget.selectedDay,
      widget.daysCount,
      widget.startDayOfWeek,
      hourHeight,
    );
    _scrollController = ScrollController(
      initialScrollOffset: initialOffset,
    );
  }

  @override
  void didUpdateWidget(CalendarMultiDayTimelineView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedDay != widget.selectedDay ||
        oldWidget.daysCount != widget.daysCount ||
        oldWidget.startDayOfWeek != widget.startDayOfWeek) {
      final hourHeight = ref.read(calendarHourHeightProvider);
      final offset = _calculateInitialScrollOffset(
        widget.selectedDay,
        widget.daysCount,
        widget.startDayOfWeek,
        hourHeight,
      );
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          offset,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      }
    }
  }

  double _calculateInitialScrollOffset(
    DateTime baseDay,
    int daysCount,
    int startDayOfWeek,
    double hourHeight,
  ) {
    final visibleDays = _calculateVisibleDays(baseDay, daysCount, startDayOfWeek);
    final now = DateTime.now();
    final containsToday = visibleDays.any(
      (d) => d.year == now.year && d.month == now.month && d.day == now.day,
    );

    if (containsToday) {
      final redLineOffset = (now.hour + now.minute / 60.0) * hourHeight;
      return (redLineOffset - hourHeight * 1.5).clamp(0.0, 24.0 * hourHeight);
    }
    return hourHeight * 7.0;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = ref.watch(themeEngineProvider);
    final hourHeight = ref.watch(calendarHourHeightProvider);
    final visibleDays = _calculateVisibleDays(widget.selectedDay, widget.daysCount, widget.startDayOfWeek);
    final gmtOffset = _getGmtOffsetString(widget.selectedDay);

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
                      final shiftDays = widget.daysCount == 7 ? 7 : widget.daysCount;
                      final prevDay = widget.selectedDay.subtract(Duration(days: shiftDays));
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
                      final shiftDays = widget.daysCount == 7 ? 7 : widget.daysCount;
                      final nextDay = widget.selectedDay.add(Duration(days: shiftDays));
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
                width: CalendarMultiDayTimelineView.timeColumnWidth,
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
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.equal, control: true): () {
                final current = ref.read(calendarHourHeightProvider);
                ref.read(calendarHourHeightProvider.notifier).state =
                    (current + 10.0).clamp(40.0, 240.0);
              },
              const SingleActivator(LogicalKeyboardKey.numpadAdd, control: true): () {
                final current = ref.read(calendarHourHeightProvider);
                ref.read(calendarHourHeightProvider.notifier).state =
                    (current + 10.0).clamp(40.0, 240.0);
              },
              const SingleActivator(LogicalKeyboardKey.minus, control: true): () {
                final current = ref.read(calendarHourHeightProvider);
                ref.read(calendarHourHeightProvider.notifier).state =
                    (current - 10.0).clamp(40.0, 240.0);
              },
              const SingleActivator(LogicalKeyboardKey.numpadSubtract, control: true): () {
                final current = ref.read(calendarHourHeightProvider);
                ref.read(calendarHourHeightProvider.notifier).state =
                    (current - 10.0).clamp(40.0, 240.0);
              },
            },
            child: Focus(
              autofocus: true,
              child: Listener(
                onPointerSignal: (pointerSignal) {
                  if (pointerSignal is PointerScrollEvent) {
                    final isControlPressed = HardwareKeyboard.instance.isControlPressed;
                    if (isControlPressed) {
                      final zoomDelta = -pointerSignal.scrollDelta.dy * 0.1;
                      final current = ref.read(calendarHourHeightProvider);
                      ref.read(calendarHourHeightProvider.notifier).state =
                          (current + zoomDelta).clamp(40.0, 240.0);
                    }
                  }
                },
                child: GestureDetector(
                  onScaleStart: (details) {
                    _baseHourHeight = ref.read(calendarHourHeightProvider);
                  },
                  onScaleUpdate: (details) {
                    ref.read(calendarHourHeightProvider.notifier).state =
                        (_baseHourHeight * details.scale).clamp(40.0, 240.0);
                  },
                  child: SingleChildScrollView(
                    controller: _scrollController,
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
                              width: CalendarMultiDayTimelineView.timeColumnWidth,
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
                  left: CalendarMultiDayTimelineView.timeColumnWidth,
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

                                final now = DateTime.now();
                                final isToday = day.year == now.year &&
                                    day.month == now.month &&
                                    day.day == now.day;

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
                                    if (isToday)
                                      Positioned(
                                        top: _getTopOffset(now) - 4, // center the 8px dot/line vertically
                                        left: 0,
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
      ),
    ),
  ),
),
      ],
    );
  }

  DateTime _getDateTimeFromTop(double top, DateTime originalStart) {
    final hourHeight = ref.read(calendarHourHeightProvider);
    final totalMinutes = (top / hourHeight * 60.0).round();
    final snappedMinutes = (totalMinutes / 15.0).round() * 15;
    final clampedMinutes = snappedMinutes.clamp(0, 24 * 60 - 15);
    final hour = clampedMinutes ~/ 60;
    final minute = clampedMinutes % 60;
    return DateTime(originalStart.year, originalStart.month, originalStart.day, hour, minute);
  }

  List<Widget> _buildAllDayEventsForDay(
    BuildContext context,
    WidgetRef ref,
    DateTime day,
    AppPalette palette,
  ) {
    final mappedEvents = widget.events.map((e) {
      final pending = _pendingMovedEvents[e.id];
      if (pending != null) {
        if (e.start.isAtSameMomentAs(pending.start) && e.end.isAtSameMomentAs(pending.end)) {
          _pendingMovedEvents.remove(e.id);
          return e;
        }
        return e.copyWith(start: pending.start, end: pending.end);
      }
      return e;
    });

    final allDayList = mappedEvents.where((e) {
      if (!e.isAllDay) return false;
      final targetDay = DateTime(day.year, day.month, day.day);
      final sLocal = e.start.toLocal();
      final eLocal = e.end.toLocal();
      final startZero = DateTime(sLocal.year, sLocal.month, sLocal.day);
      final endZero = DateTime(eLocal.year, eLocal.month, eLocal.day);
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
    final mappedEvents = widget.events.map((e) {
      final pending = _pendingMovedEvents[e.id];
      if (pending != null) {
        if (e.start.isAtSameMomentAs(pending.start) && e.end.isAtSameMomentAs(pending.end)) {
          _pendingMovedEvents.remove(e.id);
          return e;
        }
        return e.copyWith(start: pending.start, end: pending.end);
      }
      return e;
    });

    return mappedEvents.where((e) {
      if (e.isAllDay) return false;
      final targetDay = DateTime(day.year, day.month, day.day);
      final sLocal = e.start.toLocal();
      final eventDay = DateTime(sLocal.year, sLocal.month, sLocal.day);
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
    final startLocal = _draggingEventId == event.id ? _dragCurrentStart! : event.start.toLocal();
    final endLocal = _draggingEventId == event.id ? _dragCurrentEnd! : event.end.toLocal();

    final double top = _draggingEventId == event.id ? _dragCurrentTop : _getTopOffset(startLocal);
    final double height = _getHeight(startLocal, endLocal);
    final Color eventColor = _getEventColor(event.colorId, palette);

    return Positioned(
      top: top + 1,
      left: left + 2,
      width: width - 4,
      height: height - 2,
      child: GestureDetector(
        onTap: () => _onEventTapped(context, ref, event),
        onLongPressStart: (details) {
          final sLocal = event.start.toLocal();
          final duration = event.end.difference(event.start);
          setState(() {
            _draggingEventId = event.id;
            _dragOriginalTop = _getTopOffset(sLocal);
            _dragCurrentTop = _dragOriginalTop;
            _dragCurrentStart = sLocal;
            _dragCurrentEnd = sLocal.add(duration);
          });
        },
        onLongPressMoveUpdate: (details) {
          if (_draggingEventId == event.id) {
            final duration = event.end.difference(event.start);
            setState(() {
              final hourHeight = ref.read(calendarHourHeightProvider);
              _dragCurrentTop = _dragOriginalTop + details.localOffsetFromOrigin.dy;
              _dragCurrentTop = _dragCurrentTop.clamp(0.0, 24.0 * hourHeight);
              _dragCurrentStart = _getDateTimeFromTop(_dragCurrentTop, event.start.toLocal());
              _dragCurrentEnd = _dragCurrentStart!.add(duration);
            });
          }
        },
        onLongPressEnd: (details) async {
          if (_draggingEventId == event.id) {
            final newStart = _dragCurrentStart!;
            final newEnd = _dragCurrentEnd!;
            final oldDraggingId = _draggingEventId!;

            _pendingMovedEvents[oldDraggingId] = (start: newStart, end: newEnd);

            setState(() {
              _draggingEventId = null;
              _dragCurrentStart = null;
              _dragCurrentEnd = null;
            });

            final taskRepo = ref.read(taskRepositoryProvider);
            final calendarRepo = ref.read(calendarRepositoryProvider);
            final messenger = ScaffoldMessenger.of(context);

            CalendarEvent? originalEvent;
            try {
              if (oldDraggingId.startsWith('task:')) {
                final taskId = oldDraggingId.substring(5);
                await taskRepo.updateTask(
                  taskId,
                  dueDate: Value(newStart),
                  dueHasTime: true,
                );
              } else if (oldDraggingId.startsWith('habit:')) {
                throw Exception('Habits cannot be dragged. Edit the habit to change its reminder time.');
              } else {
                originalEvent = widget.events.firstWhere((e) => e.id == oldDraggingId);
                final updated = originalEvent.copyWith(
                  start: newStart,
                  end: newEnd,
                );

                await calendarRepo.cacheEvents([updated]);
                ref.read(calendarEventOverridesProvider.notifier).updateEvent(updated);

                final result = await calendarRepo.updateEvent(updated);
                ref.read(calendarEventOverridesProvider.notifier).updateEvent(result);
              }
            } catch (e) {
              _pendingMovedEvents.remove(oldDraggingId);
              if (mounted) {
                setState(() {});
                if (originalEvent != null) {
                  await calendarRepo.cacheEvents([originalEvent]);
                  ref.read(calendarEventOverridesProvider.notifier).updateEvent(originalEvent);
                } else {
                  ref.read(calendarEventOverridesProvider.notifier).removeOverride(oldDraggingId);
                }
                final msg = e is CalendarPermissionDeniedException
                    ? e.message
                    : 'Failed to update event: $e';
                messenger.showSnackBar(
                  SnackBar(content: Text(msg)),
                );
              }
            }
          }
        },
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: height < 40 ? 4.0 : 6.0,
            vertical: height < 40 ? 2.0 : 4.0,
          ),
          decoration: BoxDecoration(
            color: eventColor.withValues(alpha: _draggingEventId == event.id ? 0.7 : 0.85),
            borderRadius: BorderRadius.circular(6),
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
                  child: Text(
                    event.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (height >= 36) ...[
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
              ],
            ),
          ),
        ),
      ),
    );
  }

  double _getTopOffset(DateTime time) {
    final hourHeight = ref.read(calendarHourHeightProvider);
    return (time.hour + time.minute / 60.0) * hourHeight;
  }

  double _getHeight(DateTime start, DateTime end) {
    final hourHeight = ref.read(calendarHourHeightProvider);
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
        showTaskFormSheet(context, listId: task.listId, existingTask: task); // ignore: unawaited_futures
      }
    } else if (event.id.startsWith('habit:')) {
      final habitId = event.id.split(':')[1];
      final habit = await ref.read(habitRepositoryProvider).getHabit(habitId);
      if (habit != null && context.mounted) {
        showHabitFormSheet(context, existingHabit: habit); // ignore: unawaited_futures
      }
    } else {
      showEventFormSheet(context, initialDay: event.start, existingEvent: event); // ignore: unawaited_futures
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
    if (dayTimedEvents.isEmpty) return [];

    final sorted = List<CalendarEvent>.from(dayTimedEvents)..sort((a, b) {
      final startCmp = a.start.compareTo(b.start);
      if (startCmp != 0) return startCmp;
      final durA = a.end.difference(a.start);
      final durB = b.end.difference(b.start);
      return durB.compareTo(durA);
    });

    final roots = <_EventLayoutNode>[];

    for (final event in sorted) {
      final node = _EventLayoutNode(event);
      _EventLayoutNode? bestParent;

      void findParent(_EventLayoutNode current) {
        final pDur = current.event.end.difference(current.event.start);
        final eDur = event.end.difference(event.start);
        final encloses = !event.start.isBefore(current.event.start) &&
            !event.end.isAfter(current.event.end) &&
            pDur > eDur;
        if (encloses) {
          bestParent = current;
          for (final child in current.children) {
            findParent(child);
          }
        }
      }

      for (final root in roots) {
        findParent(root);
      }

      if (bestParent != null) {
        bestParent!.children.add(node);
      } else {
        roots.add(node);
      }
    }

    final positioned = <PositionedEvent>[];

    void layoutLevel(List<_EventLayoutNode> nodes, double availLeft, double availWidth) {
      if (nodes.isEmpty) return;

      final clusters = <List<_EventLayoutNode>>[];
      for (final node in nodes) {
        List<_EventLayoutNode>? matchedCluster;
        for (final cluster in clusters) {
          final overlaps = cluster.any((n) =>
              node.event.start.isBefore(n.event.end) &&
              node.event.end.isAfter(n.event.start));
          if (overlaps) {
            matchedCluster = cluster;
            break;
          }
        }
        if (matchedCluster != null) {
          matchedCluster.add(node);
        } else {
          clusters.add([node]);
        }
      }

      for (final cluster in clusters) {
        final nodeCols = <_EventLayoutNode, int>{};
        final colEndTimes = <int, DateTime>{};

        for (final node in cluster) {
          int assignedCol = 0;
          while (colEndTimes.containsKey(assignedCol) &&
              colEndTimes[assignedCol]!.isAfter(node.event.start)) {
            assignedCol++;
          }
          nodeCols[node] = assignedCol;
          colEndTimes[assignedCol] = node.event.end;
        }

        final maxCols = (nodeCols.values.isEmpty ? 0 : nodeCols.values.reduce((a, b) => a > b ? a : b)) + 1;
        final colWidth = availWidth / maxCols;

        for (final node in cluster) {
          final col = nodeCols[node]!;

          int colSpan = 1;
          for (int c = col + 1; c < maxCols; c++) {
            final isFree = cluster.every((other) {
              if (nodeCols[other] != c) return true;
              return !node.event.end.isAfter(other.event.start) ||
                  !node.event.start.isBefore(other.event.end);
            });
            if (isFree) {
              colSpan++;
            } else {
              break;
            }
          }

          final leftFrac = availLeft + col * colWidth;
          final widthFrac = colSpan * colWidth;

          positioned.add(PositionedEvent(
            event: node.event,
            leftFraction: leftFrac,
            widthFraction: widthFrac,
          ));

          if (node.children.isNotEmpty) {
            final inset = (widthFrac * 0.14).clamp(0.04, 0.14);
            final innerLeft = leftFrac + inset;
            final innerWidth = (widthFrac - inset - 0.01).clamp(0.05, 1.0);
            layoutLevel(node.children, innerLeft, innerWidth);
          }
        }
      }
    }

    layoutLevel(roots, 0.0, 1.0);
    return positioned;
  }
}

class _EventLayoutNode {
  final CalendarEvent event;
  final List<_EventLayoutNode> children = [];

  _EventLayoutNode(this.event);
}
