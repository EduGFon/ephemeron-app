import 'package:googleapis/calendar/v3.dart' as gcal;

/// The 11 fixed colors Google Calendar events can use — this is the
/// entire "coloring" system the Calendar API itself offers (see the
/// Step 4 README section on why richer tagging needs a local layer on
/// top of this rather than replacing it).
class GoogleEventColor {
  const GoogleEventColor(this.id, this.label, this.hex);

  final String id;
  final String label;
  final int hex;

  static const options = [
    GoogleEventColor('1', 'Lavender', 0xFF7986CB),
    GoogleEventColor('2', 'Sage', 0xFF33B679),
    GoogleEventColor('3', 'Grape', 0xFF8E24AA),
    GoogleEventColor('4', 'Flamingo', 0xFFE67C73),
    GoogleEventColor('5', 'Banana', 0xFFF6BF26),
    GoogleEventColor('6', 'Tangerine', 0xFFF4511E),
    GoogleEventColor('7', 'Peacock', 0xFF039BE5),
    GoogleEventColor('8', 'Graphite', 0xFF616161),
    GoogleEventColor('9', 'Blueberry', 0xFF3F51B5),
    GoogleEventColor('10', 'Basil', 0xFF0B8043),
    GoogleEventColor('11', 'Tomato', 0xFFD50000),
  ];
}

/// App-level view of a calendar event — deliberately not exposing the
/// full [gcal.Event] shape everywhere, so the UI layer isn't coupled to
/// googleapis's (fairly heavy) generated types.
class CalendarEvent {
  const CalendarEvent({
    required this.id,
    this.calendarId = 'primary',
    required this.title,
    this.description,
    this.location,
    required this.start,
    required this.end,
    required this.isAllDay,
    this.colorId,
    this.reminderMinutes = const [],
    this.tags = const [],
    this.isDeleted = false,
  });

  final String id;
  final String calendarId;
  final String title;
  final String? description;
  final String? location;
  final DateTime start;
  final DateTime end;
  final bool isAllDay;
  final String? colorId;

  /// Minutes-before-start for each reminder Google has stored for this
  /// event (from `reminders.overrides`) — this is the "when" source of
  /// truth for the local alarms Step 4 schedules; see CalendarRepository
  /// for why there's no local "preset" field per event yet.
  final List<int> reminderMinutes;
  
  final List<String> tags;
  final bool isDeleted;

  static CalendarEvent fromGoogle(gcal.Event event, {String calendarId = 'primary'}) {
    final startDateTime = event.start?.dateTime;
    final startDate = event.start?.date;
    final endDateTime = event.end?.dateTime;
    final endDate = event.end?.date;
    final isAllDay = startDateTime == null && startDate != null;

    return CalendarEvent(
      id: event.id ?? '',
      calendarId: calendarId,
      title: event.summary ?? '(No title)',
      description: event.description,
      location: event.location,
      start: startDateTime ?? startDate ?? DateTime.now(),
      end: endDateTime ?? endDate ?? DateTime.now(),
      isAllDay: isAllDay,
      colorId: event.colorId,
      reminderMinutes: event.reminders?.overrides
              ?.map((r) => r.minutes)
              .whereType<int>()
              .toList() ??
          const [],
      tags: const [], // Will be hydrated by local DB in Phase 4
      isDeleted: false,
    );
  }

  gcal.Event toGoogle() {
    return gcal.Event(
      summary: title,
      description: description,
      location: location,
      colorId: colorId,
      start: isAllDay
          ? gcal.EventDateTime(date: DateTime(start.year, start.month, start.day))
          : gcal.EventDateTime(dateTime: start),
      end: isAllDay
          ? gcal.EventDateTime(date: DateTime(end.year, end.month, end.day))
          : gcal.EventDateTime(dateTime: end),
      reminders: reminderMinutes.isEmpty
          ? gcal.EventReminders(useDefault: true)
          : gcal.EventReminders(
              useDefault: false,
              overrides: [
                for (final minutes in reminderMinutes)
                  gcal.EventReminder(method: 'popup', minutes: minutes),
              ],
            ),
    );
  }
}
