import 'package:googleapis/calendar/v3.dart' as gcal;

/// The 11 fixed colors Google Calendar events can use.
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

/// RSVP response status — mirrors Google Calendar's attendee responseStatus
/// plus a virtual flag (local-only, Google has no concept of "virtual yes").
enum RsvpStatus {
  needsAction,
  accepted,
  acceptedVirtually, // local-only extension
  tentative,
  declined;

  /// Human-readable label shown in the RSVP button row.
  String get label {
    switch (this) {
      case RsvpStatus.needsAction: return 'Respond';
      case RsvpStatus.accepted: return 'Yes';
      case RsvpStatus.acceptedVirtually: return 'Yes, virtually';
      case RsvpStatus.tentative: return 'Maybe';
      case RsvpStatus.declined: return 'No';
    }
  }

  /// Maps to Google's responseStatus string (virtual maps to accepted on Google).
  String get googleStatus {
    switch (this) {
      case RsvpStatus.needsAction: return 'needsAction';
      case RsvpStatus.accepted: return 'accepted';
      case RsvpStatus.acceptedVirtually: return 'accepted'; // virtual = accepted to Google
      case RsvpStatus.tentative: return 'tentative';
      case RsvpStatus.declined: return 'declined';
    }
  }

  static RsvpStatus fromGoogle(String? status) {
    switch (status) {
      case 'accepted': return RsvpStatus.accepted;
      case 'tentative': return RsvpStatus.tentative;
      case 'declined': return RsvpStatus.declined;
      default: return RsvpStatus.needsAction;
    }
  }
}

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
    // Attendees — list of email addresses
    this.attendees = const [],
    // Video conference — true when a Google Meet link is attached
    this.hasVideoConference = false,
    this.videoConferenceLink,
    // RSVP — the authenticated user's own response
    this.selfResponseStatus = RsvpStatus.needsAction,
    this.isSelfVirtual = false,
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
  final List<int> reminderMinutes;
  final List<String> tags;
  final bool isDeleted;

  // Attendees & conferencing
  final List<String> attendees;
  final bool hasVideoConference;
  final String? videoConferenceLink;

  // RSVP
  final RsvpStatus selfResponseStatus;
  final bool isSelfVirtual;

  static CalendarEvent fromGoogle(gcal.Event event, {String calendarId = 'primary'}) {
    final startDateTime = event.start?.dateTime;
    final startDate = event.start?.date;
    final endDateTime = event.end?.dateTime;
    final endDate = event.end?.date;
    final isAllDay = startDateTime == null && startDate != null;

    // Extract attendees (email list, excluding self for display)
    final attendees = event.attendees
            ?.where((a) => a.email != null && a.self != true)
            .map((a) => a.email!)
            .toList() ??
        const [];

    // Self attendee for RSVP status
    final selfAttendee = event.attendees?.where((a) => a.self == true).firstOrNull;
    final selfStatus = RsvpStatus.fromGoogle(selfAttendee?.responseStatus);

    // Conference data (Google Meet)
    final hangoutLink = event.hangoutLink;
    final hasVideo = hangoutLink != null && hangoutLink.isNotEmpty;

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
      tags: const [],
      isDeleted: false,
      attendees: attendees,
      hasVideoConference: hasVideo,
      videoConferenceLink: hangoutLink,
      selfResponseStatus: selfStatus,
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
      attendees: attendees.isEmpty
          ? null
          : attendees
              .map((email) => gcal.EventAttendee(email: email))
              .toList(),
    );
  }
}
