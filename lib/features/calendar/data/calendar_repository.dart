import 'dart:convert';
import 'dart:async' show unawaited;
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
import '../../../core/utils/dev_logger.dart';
import '../domain/calendar_event.dart';
import 'package:flutter_timezone/flutter_timezone.dart';

class CalendarNotConnectedException implements Exception {
  const CalendarNotConnectedException();
}

class CalendarPermissionDeniedException implements Exception {
  final String message;
  const CalendarPermissionDeniedException([
    this.message = 'Permission denied (403): You do not have edit access to this calendar.',
  ]);

  @override
  String toString() => message;
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

  Future<String?> _getLocalTimeZone() async {
    try {
      dynamic localTimezone = await FlutterTimezone.getLocalTimezone();
      return (localTimezone is String)
          ? localTimezone
          : localTimezone.identifier as String;
    } catch (_) {
      return null;
    }
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
          recurrence: Value(e.recurrence != null ? jsonEncode(e.recurrence) : null),
          recurringEventId: Value(e.recurringEventId),
          originalStartTime: Value(e.originalStartTime),
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
          ? (jsonDecode(row.reminderMinutes!) as List<dynamic>?)
                  ?.whereType<int>()
                  .toList() ??
              const <int>[]
          : const <int>[];
      final attendeeList = row.attendees != null
          ? (jsonDecode(row.attendees!) as List<dynamic>?)
                  ?.map((e) => e.toString())
                  .toList() ??
              const <String>[]
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
        recurrence: row.recurrence != null
            ? (jsonDecode(row.recurrence!) as List<dynamic>?)?.map((e) => e.toString()).toList()
            : null,
        recurringEventId: row.recurringEventId,
        originalStartTime: row.originalStartTime,
      );
    }).toList();
  }

  Future<List<CalendarEvent>> listEvents({
    required DateTime rangeStart,
    required DateTime rangeEnd,
  }) async {
    if (_authRepository.currentAccount == null) {
      await (_db.delete(_db.cachedCalendarEvents)
            ..where((e) => e.id.like('mock_%')))
          .go();
      return const [];
    }

    // Load from local cache exclusively.
    // Remote syncing is handled by SyncService (auto/manual triggers).
    final cached = await _loadCachedEvents(rangeStart, rangeEnd);
    cached.sort((a, b) => a.start.compareTo(b.start));
    await _scheduleEventAlarms(cached);
    return cached;
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
      await (_db.delete(_db.cachedCalendarEvents)
            ..where((e) =>
                e.calendarId.equals('primary') &
                (e.recurrence.isNotNull() |
                 (e.start.isSmallerOrEqualValue(rangeEnd) &
                  e.end.isBiggerOrEqualValue(rangeStart)))))
          .go();
      await _cacheEvents(events, calendarId: 'primary');
    } else {
      final futures = calendars.map((cal) async {
        final rawCalId = cal.id;
        if (rawCalId == null) return <CalendarEvent>[];
        final calId = cal.primary == true ? 'primary' : rawCalId;
        try {
          final result = await api.events.list(
            rawCalId,
            timeMin: rangeStart.toUtc(),
            timeMax: rangeEnd.toUtc(),
            singleEvents: true,
            orderBy: 'startTime',
          );
          final events = (result.items ?? []).map((e) => CalendarEvent.fromGoogle(e, calendarId: calId)).toList();
          await (_db.delete(_db.cachedCalendarEvents)
                ..where((e) =>
                    e.calendarId.equals(calId) &
                    (e.recurrence.isNotNull() |
                     (e.start.isSmallerOrEqualValue(rangeEnd) &
                      e.end.isBiggerOrEqualValue(rangeStart)))))
              .go();
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

  Never _handleApiError(Object e) {
    if (e is gcal.DetailedApiRequestError && e.status == 403) {
      throw const CalendarPermissionDeniedException();
    }
    if (e.toString().contains('403') || e.toString().contains('Forbidden')) {
      throw const CalendarPermissionDeniedException();
    }
    throw e;
  }

  Future<CalendarEvent> createEvent(
    CalendarEvent event, {
    AlarmPreset? preset,
    bool sendInvites = false,
    bool addVideoConference = false,
  }) async {
    if (_authRepository.currentAccount == null) {
      throw const CalendarNotConnectedException();
    }

    final api = await _api();
    final localTimeZone = await _getLocalTimeZone();
    final body = event.toGoogle(localTimeZone: localTimeZone);
    gcal.Event created;
    try {
      created = await api.events.insert(
        body,
        event.calendarId,
        conferenceDataVersion: addVideoConference ? 1 : null,
        sendUpdates: sendInvites ? 'all' : 'none',
      );
    } catch (e) {
      _handleApiError(e);
    }
    final result = CalendarEvent.fromGoogle(created, calendarId: event.calendarId);
    if (preset != null) {
      await sharedPrefs.setString('event_alarm_preset_${result.id}', preset.name);
    }
    final isRecurring = result.recurrence != null && result.recurrence!.isNotEmpty;
    if (!isRecurring) {
      await _cacheEvents([result]);
      await _scheduleEventAlarms([result]);

      if (result.attendees.isNotEmpty) {
        final start = DateTime(result.start.year, result.start.month - 1, 1);
        final end = DateTime(result.start.year, result.start.month + 3, 1);
        unawaited(refreshEventsFromRemote(rangeStart: start, rangeEnd: end));
      }
    } else {
      final start = DateTime(result.start.year, result.start.month - 1, 1);
      final end = DateTime(result.start.year, result.start.month + 3, 1);
      await refreshEventsFromRemote(rangeStart: start, rangeEnd: end);
    }
    return result;
  }

  Future<CalendarEvent> updateEvent(
    CalendarEvent event, {
    AlarmPreset? preset,
    bool sendInvites = false,
    bool addVideoConference = false,
  }) async {
    if (_authRepository.currentAccount == null) {
      throw const CalendarNotConnectedException();
    }

    final api = await _api();
    if (preset != null) {
      await sharedPrefs.setString('event_alarm_preset_${event.id}', preset.name);
    }

    final localTimeZone = await _getLocalTimeZone();
    gcal.Event updated;
    try {
      updated = await api.events.update(
        event.toGoogle(localTimeZone: localTimeZone),
        event.calendarId,
        event.id,
        conferenceDataVersion: addVideoConference ? 1 : null,
        sendUpdates: sendInvites ? 'all' : 'none',
      );
    } catch (e) {
      _handleApiError(e);
    }
    final result = CalendarEvent.fromGoogle(updated, calendarId: event.calendarId);

    final isRecurring = result.recurrence != null && result.recurrence!.isNotEmpty;
    if (!isRecurring) {
      await _cacheEvents([result]);
      await _scheduleEventAlarms([result]);

      if (result.attendees.isNotEmpty) {
        final start = DateTime(result.start.year, result.start.month - 1, 1);
        final end = DateTime(result.start.year, result.start.month + 3, 1);
        unawaited(refreshEventsFromRemote(rangeStart: start, rangeEnd: end));
      }
    } else {
      final start = DateTime(result.start.year, result.start.month - 1, 1);
      final end = DateTime(result.start.year, result.start.month + 3, 1);
      await refreshEventsFromRemote(rangeStart: start, rangeEnd: end);
    }
    return result;
  }

  /// Update the authenticated user's own RSVP response for an event.
  Future<void> respondToEvent(
    CalendarEvent event,
    RsvpStatus status, {
    bool sendInvites = false,
  }) async {
    if (_authRepository.currentAccount == null) {
      throw const CalendarNotConnectedException();
    }

    final api = await _api();
    // We need to patch the self-attendee's responseStatus.
    // The safest way is to fetch the full event, mutate the self attendee, and patch.
    gcal.Event updated;
    try {
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
        final selfEmail = _authRepository.currentAccount?.email;
        attendees.add(gcal.EventAttendee(
          email: selfEmail,
          responseStatus: status.googleStatus,
          self: true,
        ));
      }
      gcalEvent.attendees = attendees;
      updated = await api.events.patch(
        gcalEvent,
        event.calendarId,
        event.id,
        sendUpdates: sendInvites ? 'all' : 'none',
      );
    } catch (e) {
      _handleApiError(e);
    }
    final result = CalendarEvent.fromGoogle(updated, calendarId: event.calendarId);
    await _cacheEvents([result]);

    if (result.attendees.isNotEmpty) {
      final start = DateTime(result.start.year, result.start.month - 1, 1);
      final end = DateTime(result.start.year, result.start.month + 3, 1);
      unawaited(refreshEventsFromRemote(rangeStart: start, rangeEnd: end));
    }
  }

  Future<void> deleteEvent(String eventId, {String calendarId = 'primary'}) async {
    if (_authRepository.currentAccount == null) {
      throw const CalendarNotConnectedException();
    }

    final api = await _api();
    try {
      await api.events.delete(calendarId, eventId);
    } on gcal.DetailedApiRequestError catch (e) {
      if (e.status == 403) {
        DevLogger.log('Delete forbidden (403). Trying to decline the event instead.');
        try {
          final event = await getEvent(calendarId, eventId);
          if (event != null) {
            await respondToEvent(event, RsvpStatus.declined);
          }
        } catch (declineError) {
          DevLogger.logError('Failed to decline forbidden event: $declineError');
        }
      } else if (e.status != 404 && e.status != 410) {
        rethrow;
      }
    }
    await (_db.delete(_db.cachedCalendarEvents)
          ..where((e) =>
              (e.id.equals(eventId) | e.recurringEventId.equals(eventId)) &
              e.calendarId.equals(calendarId)))
        .go();
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

  Future<void> deleteThisAndFutureEvents(CalendarEvent event) async {
    final parentId = event.recurringEventId;
    if (parentId == null) {
      await deleteEvent(event.id, calendarId: event.calendarId);
      return;
    }

    if (_authRepository.currentAccount == null) {
      throw const CalendarNotConnectedException();
    }

    final parentEvent = await getEvent(event.calendarId, parentId);
    if (parentEvent == null) return;

    final untilTime = event.start.subtract(const Duration(seconds: 1)).toUtc();

    final newRecurrence = <String>[];
    if (parentEvent.recurrence != null) {
      for (final rrule in parentEvent.recurrence!) {
        if (rrule.startsWith('RRULE:')) {
          final parts = rrule.substring(6).split(';');
          final newParts = parts.where((part) => !part.startsWith('COUNT=') && !part.startsWith('UNTIL=')).toList();

          final formattedUntil = '${untilTime.year.toString().padLeft(4, '0')}'
              '${untilTime.month.toString().padLeft(2, '0')}'
              '${untilTime.day.toString().padLeft(2, '0')}T'
              '${untilTime.hour.toString().padLeft(2, '0')}'
              '${untilTime.minute.toString().padLeft(2, '0')}'
              '${untilTime.second.toString().padLeft(2, '0')}Z';

          newParts.add('UNTIL=$formattedUntil');
          newRecurrence.add('RRULE:${newParts.join(';')}');
        } else {
          newRecurrence.add(rrule);
        }
      }
    }

    if (newRecurrence.isEmpty) {
      await deleteEvent(parentId, calendarId: event.calendarId);
      return;
    }

    final updatedParent = parentEvent.copyWith(recurrence: newRecurrence);
    await updateEvent(updatedParent);

    // Clean up local cache for all instances from this series starting on or after this event
    await (_db.delete(_db.cachedCalendarEvents)
          ..where((e) =>
              e.calendarId.equals(event.calendarId) &
              (e.recurringEventId.equals(parentId) | e.id.equals(parentId)) &
              e.start.isBiggerOrEqualValue(event.start)))
        .go();
  }

  /// Fetch a single event by id. Tries [calendarId] first; if that
  /// throws (NotConnected or 404), returns null.
  Future<CalendarEvent?> getEvent(String calendarId, String eventId) async {
    try {
      if (_authRepository.currentAccount != null) {
        final api = await _api();
        final gcalEvent = await api.events.get(calendarId, eventId);
        return CalendarEvent.fromGoogle(gcalEvent, calendarId: calendarId);
      }
    } catch (_) {
      // Fallback to local DB check below
    }

    final rows = await (_db.select(_db.cachedCalendarEvents)
          ..where((e) => e.id.equals(eventId) & e.calendarId.equals(calendarId)))
        .get();
    if (rows.isNotEmpty) {
      final row = rows.first;
      final reminderList = row.reminderMinutes != null
          ? (jsonDecode(row.reminderMinutes!) as List<dynamic>?)
                  ?.whereType<int>()
                  .toList() ??
              const <int>[]
          : const <int>[];
      final attendeeList = row.attendees != null
          ? (jsonDecode(row.attendees!) as List<dynamic>?)
                  ?.map((e) => e.toString())
                  .toList() ??
              const <String>[]
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
        recurrence: row.recurrence != null
            ? (jsonDecode(row.recurrence!) as List<dynamic>?)?.map((e) => e.toString()).toList()
            : null,
        recurringEventId: row.recurringEventId,
        originalStartTime: row.originalStartTime,
      );
    }
    return null;
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
