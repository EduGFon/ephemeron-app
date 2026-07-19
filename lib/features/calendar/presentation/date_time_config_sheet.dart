import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../../core/theme/theme_palettes.dart';
import '../../calendar/presentation/event_form_sheet.dart';
import '../../alarms/domain/reminder_offset.dart';
import 'package:intl/intl.dart';

class DateTimeConfigResult {
  final DateTime start;
  final DateTime end;
  final RecurrenceConfig recurrence;
  final Set<ReminderOffset> reminderOffsets;

  DateTimeConfigResult({
    required this.start,
    required this.end,
    required this.recurrence,
    required this.reminderOffsets,
  });
}

class DateTimeConfigSheet extends StatefulWidget {
  final AppPalette palette;
  final DateTime initialStart;
  final DateTime initialEnd;
  final RecurrenceConfig initialRecurrence;
  final Set<ReminderOffset> initialReminderOffsets;

  const DateTimeConfigSheet({
    super.key,
    required this.palette,
    required this.initialStart,
    required this.initialEnd,
    required this.initialRecurrence,
    required this.initialReminderOffsets,
  });

  @override
  State<DateTimeConfigSheet> createState() => _DateTimeConfigSheetState();
}

class _DateTimeConfigSheetState extends State<DateTimeConfigSheet> {
  late DateTime _focusedDay;
  late DateTime _selectedStart;
  late DateTime _selectedEnd;
  late RecurrenceConfig _recurrence;
  late Set<ReminderOffset> _reminderOffsets;

  bool _isDurationTab = false;

  @override
  void initState() {
    super.initState();
    _focusedDay = widget.initialStart;
    _selectedStart = widget.initialStart;
    _selectedEnd = widget.initialEnd;
    _recurrence = widget.initialRecurrence;
    _reminderOffsets = widget.initialReminderOffsets;
  }

  void _save() {
    Navigator.of(context).pop(
      DateTimeConfigResult(
        start: _selectedStart,
        end: _selectedEnd,
        recurrence: _recurrence,
        reminderOffsets: _reminderOffsets,
      ),
    );
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_selectedStart),
    );
    if (t != null) {
      setState(() {
        _selectedStart = DateTime(_selectedStart.year, _selectedStart.month, _selectedStart.day, t.hour, t.minute);
        if (_selectedEnd.isBefore(_selectedStart)) {
          _selectedEnd = _selectedStart.add(const Duration(minutes: 30));
        }
      });
    }
  }

  Future<void> _pickReminder() async {
     // Extremely simple cycle for now (could be expanded)
     setState(() {
       if (_reminderOffsets.isEmpty) {
         _reminderOffsets = {ReminderOffset.atTime};
       } else if (_reminderOffsets.contains(ReminderOffset.atTime)) {
         _reminderOffsets = {ReminderOffset.thirtyMinBefore};
       } else if (_reminderOffsets.contains(ReminderOffset.thirtyMinBefore)) {
         _reminderOffsets = {ReminderOffset.oneHourBefore};
       } else {
         _reminderOffsets = {};
       }
     });
  }

  Future<void> _pickRepeat() async {
     setState(() {
       switch (_recurrence.type) {
         case RecurrenceType.none: _recurrence = _recurrence.copyWith(type: RecurrenceType.daily); break;
         case RecurrenceType.daily: _recurrence = _recurrence.copyWith(type: RecurrenceType.weekly); break;
         case RecurrenceType.weekly: _recurrence = _recurrence.copyWith(type: RecurrenceType.monthly); break;
         case RecurrenceType.monthly: _recurrence = _recurrence.copyWith(type: RecurrenceType.yearly); break;
         case RecurrenceType.yearly: _recurrence = _recurrence.copyWith(type: RecurrenceType.none); break;
       }
     });
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;

    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(Icons.close, color: palette.text),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => setState(() => _isDurationTab = false),
                  child: Text(
                    'Date',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: !_isDurationTab ? palette.primary : palette.text.withValues(alpha: 0.5),
                      decoration: !_isDurationTab ? TextDecoration.underline : TextDecoration.none,
                      decorationColor: palette.primary,
                      decorationThickness: 2,
                    ),
                  ),
                ),
                const SizedBox(width: 24),
                GestureDetector(
                  onTap: () => setState(() => _isDurationTab = true),
                  child: Text(
                    'Duration',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _isDurationTab ? palette.primary : palette.text.withValues(alpha: 0.5),
                      decoration: _isDurationTab ? TextDecoration.underline : TextDecoration.none,
                      decorationColor: palette.primary,
                      decorationThickness: 2,
                    ),
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(Icons.check, color: palette.text),
                  onPressed: _save,
                ),
              ],
            ),
          ),
          
          if (!_isDurationTab) ...[
            // Month display
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Row(
                children: [
                  Text(
                    DateFormat.MMMM().format(_focusedDay),
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: palette.text),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(Icons.chevron_left, color: palette.text),
                    onPressed: () {
                      setState(() {
                        _focusedDay = DateTime(_focusedDay.year, _focusedDay.month - 1, 1);
                      });
                    },
                  ),
                  IconButton(
                    icon: Icon(Icons.chevron_right, color: palette.text),
                    onPressed: () {
                      setState(() {
                        _focusedDay = DateTime(_focusedDay.year, _focusedDay.month + 1, 1);
                      });
                    },
                  ),
                ],
              ),
            ),
            
            // Calendar
            TableCalendar(
              firstDay: DateTime.utc(2000, 1, 1),
              lastDay: DateTime.utc(2100, 12, 31),
              focusedDay: _focusedDay,
              currentDay: _selectedStart,
              headerVisible: false,
              calendarStyle: CalendarStyle(
                defaultTextStyle: TextStyle(color: palette.text),
                weekendTextStyle: TextStyle(color: palette.text.withValues(alpha: 0.7)),
                outsideTextStyle: TextStyle(color: palette.text.withValues(alpha: 0.3)),
                todayDecoration: const BoxDecoration(),
                todayTextStyle: TextStyle(color: palette.text, fontWeight: FontWeight.bold),
                selectedDecoration: BoxDecoration(
                  color: palette.primary,
                  shape: BoxShape.circle,
                ),
                selectedTextStyle: TextStyle(color: palette.surface, fontWeight: FontWeight.bold),
              ),
              daysOfWeekStyle: DaysOfWeekStyle(
                weekdayStyle: TextStyle(color: palette.text.withValues(alpha: 0.5)),
                weekendStyle: TextStyle(color: palette.text.withValues(alpha: 0.5)),
              ),
              selectedDayPredicate: (day) => isSameDay(_selectedStart, day),
              onDaySelected: (selectedDay, focusedDay) {
                setState(() {
                  _selectedStart = DateTime(selectedDay.year, selectedDay.month, selectedDay.day, _selectedStart.hour, _selectedStart.minute);
                  if (_selectedEnd.isBefore(_selectedStart)) {
                    _selectedEnd = _selectedStart.add(const Duration(minutes: 30));
                  }
                  _focusedDay = focusedDay;
                });
              },
              onPageChanged: (focusedDay) {
                setState(() => _focusedDay = focusedDay);
              },
            ),
            
            const SizedBox(height: 16),
            
            // List Tiles
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: palette.text.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  ListTile(
                    leading: Icon(Icons.access_time, color: palette.text.withValues(alpha: 0.7)),
                    title: Text('Time', style: TextStyle(color: palette.text)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(DateFormat('HH:mm').format(_selectedStart), style: TextStyle(color: palette.text.withValues(alpha: 0.7))),
                        const SizedBox(width: 8),
                        GestureDetector(
                           onTap: () {
                             setState(() {
                               _selectedStart = DateTime(_selectedStart.year, _selectedStart.month, _selectedStart.day, 0, 0);
                             });
                           },
                           child: Icon(Icons.close, size: 16, color: palette.text.withValues(alpha: 0.5)),
                        ),
                      ],
                    ),
                    onTap: _pickTime,
                  ),
                  ListTile(
                    leading: Icon(Icons.alarm, color: palette.text.withValues(alpha: 0.7)),
                    title: Text('Reminder', style: TextStyle(color: palette.text)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_reminderOffsets.isNotEmpty ? _reminderOffsets.first.label : 'None', style: TextStyle(color: palette.text.withValues(alpha: 0.7))),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => setState(() => _reminderOffsets.clear()),
                          child: Icon(Icons.close, size: 16, color: palette.text.withValues(alpha: 0.5)),
                        ),
                      ],
                    ),
                    onTap: _pickReminder,
                  ),
                  ListTile(
                    leading: Icon(Icons.repeat, color: palette.text.withValues(alpha: 0.7)),
                    title: Text('Repeat', style: TextStyle(color: palette.text)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_recurrence.label, style: TextStyle(color: palette.text.withValues(alpha: 0.7))),
                        const SizedBox(width: 8),
                        Icon(Icons.chevron_right, size: 20, color: palette.text.withValues(alpha: 0.5)),
                      ],
                    ),
                    onTap: _pickRepeat,
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            TextButton(
              onPressed: () {
                setState(() {
                  _selectedStart = DateTime.now();
                  _selectedEnd = DateTime.now().add(const Duration(minutes: 30));
                  _recurrence = const RecurrenceConfig();
                  _reminderOffsets = {};
                });
              },
              child: const Text('Clear', style: TextStyle(color: Colors.red, fontSize: 16)),
            ),
          ] else ...[
             // Duration Tab simple placeholder implementation
             Padding(
               padding: const EdgeInsets.all(24.0),
               child: Center(
                 child: Text('Duration settings will be implemented here', style: TextStyle(color: palette.text)),
               ),
             ),
          ]
        ],
      ),
    );
  }
}

Future<DateTimeConfigResult?> showDateTimeConfigSheet({
  required BuildContext context,
  required AppPalette palette,
  required DateTime initialStart,
  required DateTime initialEnd,
  required RecurrenceConfig initialRecurrence,
  required Set<ReminderOffset> initialReminderOffsets,
}) {
  return showModalBottomSheet<DateTimeConfigResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => DateTimeConfigSheet(
      palette: palette,
      initialStart: initialStart,
      initialEnd: initialEnd,
      initialRecurrence: initialRecurrence,
      initialReminderOffsets: initialReminderOffsets,
    ),
  );
}
