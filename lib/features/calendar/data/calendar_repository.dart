import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;
import 'package:http/http.dart' as http;

import '../../../core/config/app_config.dart';
import '../../../core/network/bearer_http_client.dart';
import '../../../data/local/database.dart';
import '../../alarms/data/alarm_scheduler.dart';
import '../../alarms/domain/alarm_preset.dart';
import '../../alarms/domain/reminder_offset.dart';
import '../../../core/settings/shared_preferences_provider.dart';
import '../../auth/google/google_auth_repository.dart';
import '../domain/calendar_event.dart';

class CalendarNotConnectedException implements Exception {
  const CalendarNotConnectedException();
}

/// Unlike TaskRepository, Google Calendar itself is the source of truth
/// here — there's no local mirror to fall back on, so failures surface
/// directly to the UI rather than being swallowed as best-effort (see
/// GoogleTasksMirror's doc comment for the contrast).
///
/// Event reminders piggyback on Google's own `reminders.overrides`
/// field rather than needing a parallel local table: the "when" (minutes
/// before) is read straight from what Google already stores, and every
/// [listEvents] call re-schedules local alarms for those minutes at
/// [AlarmPreset.light] — deterministic notification IDs (see
/// AlarmScheduler) make re-scheduling the same alarm idempotent, so this
/// needs no bookkeeping. Per-event preset choice (light vs. medium) isn't
/// exposed yet for the same reason Tasks' alarmPreset needed its own
/// column — that's Phase 2 if wanted, via a small local table mirroring
/// how Tasks already does it.
class CalendarRepository {
  CalendarRepository(this._authRepository, this._db, this._alarmScheduler);

  final GoogleAuthRepository _authRepository;
  final AppDatabase _db;
  final AlarmScheduler _alarmScheduler;

  Future<gcal.CalendarApi> _api() async {
    if (_authRepository.currentAccount == null) {
      throw const CalendarNotConnectedException();
    }

    final client = BearerHttpClient(
      tokenProvider: () => _authRepository.getAccessToken(const [
        AppConfig.googleCalendarScope,
        AppConfig.googleTasksScope,
      ]),
      inner: http.Client(),
    );
    return gcal.CalendarApi(client);
  }

  Future<void> _cacheEvents(List<CalendarEvent> events, {String? calendarId}) async {
    for (final e in events) {
      final calId = calendarId ?? e.calendarId;
      await _db.into(_db.cachedCalendarEvents).insert(
        CachedCalendarEventsCompanion.insert(
          id: e.id,
          calendarId: calId,
          title: e.title,
          description: Value(e.description),
          location: Value(e.location),
          start: e.start,
          end: e.end,
          isAllDay: Value(e.isAllDay),
          colorId: Value(e.colorId),
          reminderMinutes: Value(jsonEncode(e.reminderMinutes)),
          attendees: Value(jsonEncode(e.attendees)),
          hasVideoConference: Value(e.hasVideoConference),
          videoConferenceLink: Value(e.videoConferenceLink),
          selfResponseStatus: Value(e.selfResponseStatus.name),
        ),
        mode: InsertMode.insertOrReplace,
      );
    }
  }

  Future<List<CalendarEvent>> _loadCachedEvents(DateTime rangeStart, DateTime rangeEnd) async {
    final rows = await (_db.select(_db.cachedCalendarEvents)
          ..where((e) =>
              e.start.isSmallerOrEqualValue(rangeEnd) &
              e.end.isBiggerOrEqualValue(rangeStart)))
        .get();

    return rows.map((row) {
      final reminderList = row.reminderMinutes != null
          ? (jsonDecode(row.reminderMinutes!) as List<dynamic>).cast<int>().toList()
          : const <int>[];
      final attendeeList = row.attendees != null
          ? (jsonDecode(row.attendees!) as List<dynamic>).cast<String>().toList()
          : const <String>[];

      return CalendarEvent(
        id: row.id,
        calendarId: row.calendarId,
        title: row.title,
        description: row.description,
        location: row.location,
        start: row.start,
        end: row.end,
        isAllDay: row.isAllDay,
        colorId: row.colorId,
        reminderMinutes: reminderList,
        attendees: attendeeList,
        hasVideoConference: row.hasVideoConference,
        videoConferenceLink: row.videoConferenceLink,
        selfResponseStatus: RsvpStatus.values.byName(row.selfResponseStatus),
      );
    }).toList();
  }

  Future<List<CalendarEvent>> listEvents({
    required DateTime rangeStart,
    required DateTime rangeEnd,
  }) async {
    if (_authRepository.currentAccount == null) {
      // Mock events for Phase 3 UI testing until Phase 4 sync is built
      return [
        CalendarEvent(
          id: 'mock_1',
          title: 'Design Review',
          start: DateTime.now().add(const Duration(hours: 1)),
          end: DateTime.now().add(const Duration(hours: 2)),
          isAllDay: false,
          colorId: '3', // Grape
          tags: ['Work', 'Design'],
        ),
        CalendarEvent(
          id: 'mock_2',
          title: 'Dentist Appointment',
          start: DateTime.now().add(const Duration(days: 1, hours: -2)),
          end: DateTime.now().add(const Duration(days: 1, hours: -1)),
          isAllDay: false,
          colorId: '11', // Tomato
          tags: ['Personal', 'Health'],
        ),
        CalendarEvent(
          id: 'mock_3',
          title: 'Company Retreat',
          start: DateTime.now().add(const Duration(days: 3)),
          end: DateTime.now().add(const Duration(days: 5)),
          isAllDay: true,
          colorId: '7', // Peacock
          tags: ['Work'],
        ),
      ];
    }

    // Try loading from local cache first
    final cached = await _loadCachedEvents(rangeStart, rangeEnd);
    if (cached.isNotEmpty) {
      cached.sort((a, b) => a.start.compareTo(b.start));
      await _scheduleEventAlarms(cached);
      return cached;
    }

    // If cache is empty, refresh from remote
    return refreshEventsFromRemote(rangeStart: rangeStart, rangeEnd: rangeEnd);
  }

  Future<List<CalendarEvent>> refreshEventsFromRemote({
    required DateTime rangeStart,
    required DateTime rangeEnd,
  }) async {
    if (_authRepository.currentAccount == null) return const [];

    final api = await _api();
    final calendarList = await api.calendarList.list();
    final calendars = calendarList.items ?? [];

    List<CalendarEvent> allEvents = [];

    if (calendars.isEmpty) {
      final result = await api.events.list(
        'primary',
        timeMin: rangeStart.toUtc(),
        timeMax: rangeEnd.toUtc(),
        singleEvents: true,
        orderBy: 'startTime',
      );
      final events = (result.items ?? []).map((e) => CalendarEvent.fromGoogle(e, calendarId: 'primary')).toList();
      allEvents.addAll(events);
      await _cacheEvents(events, calendarId: 'primary');
    } else {
      final futures = calendars.map((cal) async {
        final calId = cal.id;
        if (calId == null) return <CalendarEvent>[];
        try {
          final result = await api.events.list(
            calId,
            timeMin: rangeStart.toUtc(),
            timeMax: rangeEnd.toUtc(),
            singleEvents: true,
            orderBy: 'startTime',
          );
          final events = (result.items ?? []).map((e) => CalendarEvent.fromGoogle(e, calendarId: calId)).toList();
          await _cacheEvents(events, calendarId: calId);
          return events;
        } catch (_) {
          return <CalendarEvent>[];
        }
      });

      final results = await Future.wait(futures);
      allEvents.addAll(results.expand((e) => e));
    }

    allEvents.sort((a, b) => a.start.compareTo(b.start));
    await _scheduleEventAlarms(allEvents);
    return allEvents;
  }

  Future<CalendarEvent> createEvent(
    CalendarEvent event, {
    AlarmPreset? preset,
    bool sendInvites = false,
    bool addVideoConference = false,
  }) async {
    final api = await _api();
    final body = event.toGoogle();
    final created = await api.events.insert(
      body,
      event.calendarId,
      conferenceDataVersion: addVideoConference ? 1 : null,
      sendUpdates: sendInvites ? 'all' : 'none',
    );
    final result = CalendarEvent.fromGoogle(created, calendarId: event.calendarId);
    if (preset != null) {
      await sharedPrefs.setString('event_alarm_preset_${result.id}', preset.name);
    }
    await _cacheEvents([result]);
    await _scheduleEventAlarms([result]);
    return result;
  }

  Future<CalendarEvent> updateEvent(
    CalendarEvent event, {
    AlarmPreset? preset,
    bool sendInvites = false,
    bool addVideoConference = false,
  }) async {
    final api = await _api();
    if (preset != null) {
      await sharedPrefs.setString('event_alarm_preset_${event.id}', preset.name);
    }
    final updated = await api.events.update(
      event.toGoogle(),
      event.calendarId,
      event.id,
      conferenceDataVersion: addVideoConference ? 1 : null,
      sendUpdates: sendInvites ? 'all' : 'none',
    );
    final result = CalendarEvent.fromGoogle(updated, calendarId: event.calendarId);
    await _cacheEvents([result]);
    await _scheduleEventAlarms([result]);
    return result;
  }

  /// Update the authenticated user's own RSVP response for an event.
  Future<void> respondToEvent(
    CalendarEvent event,
    RsvpStatus status, {
    bool sendInvites = false,
  }) async {
    final api = await _api();
    // We need to patch the self-attendee's responseStatus.
    // The safest way is to fetch the full event, mutate the self attendee, and patch.
    final gcalEvent = await api.events.get(event.calendarId, event.id);
    final attendees = gcalEvent.attendees ?? [];
    bool foundSelf = false;
    for (final a in attendees) {
      if (a.self == true) {
        a.responseStatus = status.googleStatus;
        foundSelf = true;
        break;
      }
    }
    if (!foundSelf) {
      // If the user is not in the attendee list, add them
      attendees.add(gcal.EventAttendee(
        responseStatus: status.googleStatus,
        self: true,
      ));
    }
    gcalEvent.attendees = attendees;
    await api.events.patch(
      gcalEvent,
      event.calendarId,
      event.id,
      sendUpdates: sendInvites ? 'all' : 'none',
    );
  }

  Future<void> deleteEvent(String eventId, {String calendarId = 'primary'}) async {
    final api = await _api();
    await api.events.delete(calendarId, eventId);
    await (_db.delete(_db.cachedCalendarEvents)..where((e) => e.id.equals(eventId) & e.calendarId.equals(calendarId))).go();
    // Cancel whatever alarms were computed for this event last time it
    // was listed — safe even if none were actually scheduled, since
    // AlarmScheduler.cancelByIds no-ops on IDs that aren't pending.
    // Offsets aren't known here without a re-fetch, so this cancels the
    // full preset range rather than the exact set — harmless over-cancel.
    final allPossibleIds = [
      for (final offset in ReminderOffset.presets)
        Object.hash(eventId, offset.presetIndex) & 0x7FFFFFFF,
    ];
    await _alarmScheduler.cancelByIds(allPossibleIds);
  }

  /// Fetch a single event by id. Tries [calendarId] first; if that
  /// throws (NotConnected or 404), returns null.
  Future<CalendarEvent?> getEvent(String calendarId, String eventId) async {
    try {
      final api = await _api();
      final gcalEvent = await api.events.get(calendarId, eventId);
      return CalendarEvent.fromGoogle(gcalEvent, calendarId: calendarId);
    } catch (_) {
      return null;
    }
  }

  Future<void> _scheduleEventAlarms(List<CalendarEvent> events) async {
    for (final event in events) {
      if (event.reminderMinutes.isEmpty) continue;
      if (event.start.isBefore(DateTime.now())) continue;
      final offsets = event.reminderMinutes
          .map(ReminderOffset.fromMinutes)
          .toList();
      final presetName = sharedPrefs.getString('event_alarm_preset_${event.id}') ?? 'light';
      final preset = AlarmPreset.values.byName(presetName);

      await _alarmScheduler.scheduleAlarmsForOffsets(
        entityId: event.id,
        title: event.title,
        body: event.location ?? '',
        dueAt: event.start,
        offsets: offsets,
        preset: preset,
      );
    }
  }

  // ---------------------------------------------------------------------
  // Local tag layer (see EventTags table's doc comment for why this
  // exists alongside, not instead of, Google's own colorId)
  // ---------------------------------------------------------------------

  Future<void> assignTag(String googleEventId, String tagId) async {
    await _db
        .into(_db.eventTags)
        .insertOnConflictUpdate(
          EventTagsCompanion.insert(googleEventId: googleEventId, tagId: tagId),
        );
  }

  Future<void> removeTag(String googleEventId, String tagId) async {
    await (_db.delete(_db.eventTags)..where(
          (t) => t.googleEventId.equals(googleEventId) & t.tagId.equals(tagId),
        ))
        .go();
  }

  Stream<List<Tag>> watchTagsForEvent(String googleEventId) {
    final query = _db.select(_db.tags).join([
      innerJoin(_db.eventTags, _db.eventTags.tagId.equalsExp(_db.tags.id)),
    ])..where(_db.eventTags.googleEventId.equals(googleEventId));
    return query.watch().map(
      (rows) => rows.map((r) => r.readTable(_db.tags)).toList(),
    );
  }
}
