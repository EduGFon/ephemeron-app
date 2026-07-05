import 'package:drift/drift.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;
import 'package:http/http.dart' as http;

import '../../../core/config/app_config.dart';
import '../../../core/network/bearer_http_client.dart';
import '../../../data/local/database.dart';
import '../../alarms/data/alarm_scheduler.dart';
import '../../alarms/domain/alarm_preset.dart';
import '../../alarms/domain/reminder_offset.dart';
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

    final api = await _api();
    final result = await api.events.list(
      'primary',
      timeMin: rangeStart.toUtc(),
      timeMax: rangeEnd.toUtc(),
      singleEvents: true, // expands recurring events into instances
      orderBy: 'startTime',
    );

    final events = (result.items ?? []).map(CalendarEvent.fromGoogle).toList();
    await _scheduleEventAlarms(events);
    return events;
  }

  Future<CalendarEvent> createEvent(CalendarEvent event) async {
    final api = await _api();
    final created = await api.events.insert(event.toGoogle(), 'primary');
    final result = CalendarEvent.fromGoogle(created);
    await _scheduleEventAlarms([result]);
    return result;
  }

  Future<CalendarEvent> updateEvent(CalendarEvent event) async {
    final api = await _api();
    final updated = await api.events.update(
      event.toGoogle(),
      'primary',
      event.id,
    );
    final result = CalendarEvent.fromGoogle(updated);
    await _scheduleEventAlarms([result]);
    return result;
  }

  Future<void> deleteEvent(String eventId) async {
    final api = await _api();
    await api.events.delete('primary', eventId);
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

  Future<void> _scheduleEventAlarms(List<CalendarEvent> events) async {
    for (final event in events) {
      if (event.reminderMinutes.isEmpty) continue;
      if (event.start.isBefore(DateTime.now())) continue;
      final offsets = event.reminderMinutes
          .map(ReminderOffset.fromMinutes)
          .toList();
      await _alarmScheduler.scheduleAlarmsForOffsets(
        entityId: event.id,
        title: event.title,
        body: event.location ?? '',
        dueAt: event.start,
        offsets: offsets,
        preset: AlarmPreset.light,
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
