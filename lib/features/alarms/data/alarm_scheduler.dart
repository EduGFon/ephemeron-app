import 'dart:async';
import 'dart:convert' show jsonDecode;
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:drift/drift.dart' show Value, DoUpdate;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:uuid/uuid.dart';

import '../../../core/routing/root_navigator_key.dart';
import '../../../data/local/database.dart';
import '../../tasks/domain/task_recurrence.dart';
import '../domain/alarm_payload.dart';
import '../domain/alarm_preset.dart';
import '../domain/reminder_offset.dart';
import '../presentation/alarm_ring_screen.dart';

const _snoozeActionId = 'snooze';
const _doneActionId = 'done';
const _lightChannelId = 'light_reminders';
const _mediumChannelId = 'medium_alarms';
const _strongChannelId = 'strong_alarms';
const _constantChannelId = 'constant_alarms';

/// The type of action a user took on an alarm notification, surfaced via
/// [AlarmScheduler.actionEvents] so feature repositories (Tasks, Habits —
/// built in later steps) can react (e.g. mark a task complete) without
/// this engine needing to know anything about tasks or habits itself.
enum AlarmActionType { snoozed, done, opened }

class AlarmAction {
  const AlarmAction(this.entityId, this.type);
  final String entityId;
  final AlarmActionType type;
}

/// Wraps flutter_local_notifications with the app's specific alarm
/// behavior: two channels (light/medium) matching the preset system,
/// offset-based scheduling for a due date, and the snooze/done actions
/// described in the brainstorm.
///
/// One deliberate layering exception: this data-layer class imports
/// [AlarmRingScreen] (presentation) to push it directly from the
/// notification-tap callback. That callback has no BuildContext and
/// isn't reachable through go_router's declarative routes, so pushing
/// through the shared [rootNavigatorKey] is simpler and more robust here
/// than inventing an event-bus just to keep the import graph clean.
///
/// NOT implemented in this MVP step (see AlarmPreset's doc comment):
/// [AlarmPreset.strong] and [AlarmPreset.constant]. Also not implemented
/// yet: the "auto-snooze after 30s of no interaction" behavior lives in
/// [AlarmRingScreen], not here — this class only handles scheduling and
/// routing to that screen, not what happens once it's showing.
///
/// Web caveat, found during the Step 9 cross-platform pass: browsers do
/// not support scheduled or repeating notifications at all — this isn't
/// a bug to work around, it's a platform limitation with no client-only
/// fix (a real fix needs the Web Push API plus a server sending pushes,
/// which conflicts with this app's CASA-avoidance architecture anyway).
/// [scheduleAlarmsForOffsets], [scheduleRecurring], and [scheduleOneShotAt]
/// all check [supportsScheduledAlarms] and no-op rather than calling into
/// a plugin method the browser can't fulfill. UI layers should check the
/// same flag to hide/disable reminder pickers on web rather than letting
/// the user configure something that silently won't fire — see the new
/// Settings screen for where this gets surfaced.
class AlarmScheduler {
  /// Immediate (non-scheduled) notifications via [showOngoingNotification]
  /// still work on web — only scheduling/repetition doesn't.
  bool get supportsScheduledAlarms => !kIsWeb && !Platform.isLinux;

  Timer? _localAlarmTimer;
  final List<LocalAlarm> _localAlarms = [];
  Process? _activeSoundProcess;

  AlarmScheduler() : _plugin = FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  final _actionController = StreamController<AlarmAction>.broadcast();

  Stream<AlarmAction> get actionEvents => _actionController.stream;

  Future<void> initialize() async {
    await _initializeTimezone();

    if (!supportsScheduledAlarms) {
      _startLocalAlarmPolling();
    }

    if (kIsWeb || Platform.isLinux) return;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      settings: const InitializationSettings(android: androidInit),
      onDidReceiveNotificationResponse: _handleForegroundResponse,
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      await android.createNotificationChannel(
        const AndroidNotificationChannel(
          _lightChannelId,
          'Reminders',
          description: 'Task and event reminders (light preset)',
          importance: Importance.high,
        ),
      );
      await android.createNotificationChannel(
        const AndroidNotificationChannel(
          _mediumChannelId,
          'Alarms',
          description: 'Full-screen alarms (medium preset)',
          importance: Importance.max,
        ),
      );
      await android.createNotificationChannel(
        const AndroidNotificationChannel(
          _strongChannelId,
          'Strong Alarms',
          description: 'Full-screen alarms with long sound',
          importance: Importance.max,
        ),
      );
      await android.createNotificationChannel(
        const AndroidNotificationChannel(
          _constantChannelId,
          'Constant Alarms',
          description: 'Full-screen alarms that ring continuously',
          importance: Importance.max,
        ),
      );
    }
  }

  Future<void> _initializeTimezone() async {
    tz_data.initializeTimeZones();
    try {
      final localTimezone = await FlutterTimezone.getLocalTimezone();
      // NOTE: flutter_timezone's return shape has moved between a plain
      // IANA String and a TimezoneInfo object across versions. Written
      // as explicit if/else against a declared String, not a ternary —
      // a ternary here previously inferred as Object instead of String
      // (a real bug caught via a real build), rejected by
      // tz.getLocation's String parameter.
      final String identifier = localTimezone.identifier;
      tz.setLocalLocation(tz.getLocation(identifier));
    } catch (e) {
      debugPrint(
        'AlarmScheduler: could not resolve local timezone ($e), '
        'defaulting to UTC — alarms will fire at the wrong wall-clock '
        'time until this is fixed.',
      );
    }
  }

  /// Requests the runtime permissions alarms need. Deliberately not
  /// called automatically from [initialize] — surfacing a permission
  /// dialog before the user has any context why is bad UX. Call this
  /// from onboarding or the first time the user actually sets an alarm.
  Future<void> requestPermissions() async {
    // kIsWeb must be checked first — dart:io's Platform.isAndroid throws
    // at runtime on web rather than just returning false, so evaluating
    // it there would crash instead of gracefully no-op'ing. Caught during
    // the Step 9 cross-platform pass.
    if (kIsWeb || !Platform.isAndroid) return;
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;

    await android.requestNotificationsPermission();
    // USE_EXACT_ALARM (declared in the manifest, see README) does not
    // need a runtime prompt on Android — only request this if you switch
    // the manifest to the user-granted SCHEDULE_EXACT_ALARM instead.
    await android.requestExactAlarmsPermission();
    await android.requestFullScreenIntentPermission();
  }

  /// Schedules one notification per offset (skipping any offset whose
  /// computed fire time has already passed) and returns the notification
  /// IDs used, so the caller (a Task/Habit/Event repository) can store
  /// them for later cancellation via [cancelByIds].
  Future<List<int>> scheduleAlarmsForOffsets({
    required String entityId,
    required String title,
    required String body,
    required DateTime dueAt,
    required List<ReminderOffset> offsets,
    required AlarmPreset preset,
  }) async {
    final ids = [
      for (final offset in offsets) _stableId(entityId, offset.presetIndex),
    ];

    if (!supportsScheduledAlarms) {
      for (var i = 0; i < offsets.length; i++) {
        final fireAt = dueAt.subtract(offsets[i].beforeDue);
        if (fireAt.isBefore(DateTime.now())) continue;

        final siblingIds = [...ids]..removeAt(i);
        _localAlarms.add(LocalAlarm(
          id: ids[i],
          entityId: entityId,
          title: title,
          body: body,
          fireAt: fireAt,
          preset: preset,
          siblingIds: siblingIds,
        ));
      }
      return ids;
    }


    for (var i = 0; i < offsets.length; i++) {
      final fireAt = dueAt.subtract(offsets[i].beforeDue);
      if (fireAt.isBefore(DateTime.now())) continue;

      final siblingIds = [...ids]..removeAt(i);
      final payload = AlarmPayload(
        entityId: entityId,
        title: title,
        body: body,
        preset: preset,
        siblingIds: siblingIds,
      );

      await _plugin.zonedSchedule(
        id: ids[i],
        title: title,
        body: body,
        scheduledDate: tz.TZDateTime.from(fireAt, tz.local),
        notificationDetails: _detailsForPreset(preset),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: payload.encode(),
      );
    }

    return ids;
  }

  /// Schedules a genuinely OS-recurring alarm at [hour]:[minute] — every
  /// day if [weekday] is null, or only on that ISO weekday (1=Mon..7=Sun)
  /// otherwise. Used by Habits, whose reminders are "this time every
  /// applicable day" rather than Tasks/Events' "N minutes before one due
  /// moment" — a different enough shape that it doesn't fit
  /// [scheduleAlarmsForOffsets]. Because this uses
  /// [matchDateTimeComponents], the OS itself handles the repetition —
  /// no daily app-side rescheduling needed, which matters for the
  /// battery-usage goal.
  Future<int> scheduleRecurring({
    required String entityId,
    required String title,
    required String body,
    required int hour,
    required int minute,
    int? weekday,
    required AlarmPreset preset,
  }) async {
    final id = Object.hash(entityId, 'recurring', weekday) & 0x7FFFFFFF;
    final scheduled = _nextOccurrence(
      hour: hour,
      minute: minute,
      weekday: weekday,
    );

    if (!supportsScheduledAlarms) {
      _localAlarms.add(LocalAlarm(
        id: id,
        entityId: entityId,
        title: title,
        body: body,
        fireAt: scheduled,
        preset: preset,
        siblingIds: const [],
      ));
      return id;
    }

    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: scheduled,
      notificationDetails: _detailsForPreset(preset),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: weekday != null
          ? DateTimeComponents.dayOfWeekAndTime
          : DateTimeComponents.time,
      payload: AlarmPayload(
        entityId: entityId,
        title: title,
        body: body,
        preset: preset,
      ).encode(),
    );
    return id;
  }

  /// Non-recurring, single occurrence at the next matching [hour]:
  /// [minute] (optionally constrained to a specific [weekday]) — for
  /// Habit frequencies that don't have a fixed weekday to peg a native
  /// recurring alarm to (weekly-X-times-with-no-specific-days, and
  /// interval). Callers (HabitRepository) are responsible for calling
  /// this again once it's passed — see the Step 6 README section on
  /// `refreshHabitAlarms` for how that's kept honest rather than silently
  /// assumed to "just work" forever.
  Future<int> scheduleOneShotAt({
    required String entityId,
    required String title,
    required String body,
    required int hour,
    required int minute,
    required AlarmPreset preset,
  }) async {
    final id = Object.hash(entityId, 'oneshot') & 0x7FFFFFFF;
    final scheduled = _nextOccurrence(
      hour: hour,
      minute: minute,
      weekday: null,
    );

    if (!supportsScheduledAlarms) {
      _localAlarms.add(LocalAlarm(
        id: id,
        entityId: entityId,
        title: title,
        body: body,
        fireAt: scheduled,
        preset: preset,
        siblingIds: const [],
      ));
      return id;
    }
    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: scheduled,
      notificationDetails: _detailsForPreset(preset),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: AlarmPayload(
        entityId: entityId,
        title: title,
        body: body,
        preset: preset,
      ).encode(),
    );
    return id;
  }

  tz.TZDateTime _nextOccurrence({
    required int hour,
    required int minute,
    int? weekday,
  }) {
    final now = tz.TZDateTime.now(tz.local);
    var candidate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    if (weekday == null) {
      if (candidate.isBefore(now)) {
        candidate = candidate.add(const Duration(days: 1));
      }
      return candidate;
    }
    while (candidate.weekday != weekday || candidate.isBefore(now)) {
      candidate = candidate.add(const Duration(days: 1));
    }
    return candidate;
  }

  /// Cancels a specific set of notification IDs — used both when a task/
  /// event/habit is deleted or rescheduled, and internally when the user
  /// marks something done from a notification action.
  Future<void> cancelByIds(List<int> ids) async {
    _localAlarms.removeWhere((a) => ids.contains(a.id));
    if (!supportsScheduledAlarms) return;
    for (final id in ids) {
      await _plugin.cancel(id: id);
    }
  }

  /// Shows (or updates, if already showing) a persistent, non-dismissible
  /// notification with a live OS-rendered elapsed-time counter — the
  /// "pill notification when minimized" from the brainstorm, implemented
  /// as an ongoing notification with `usesChronometer` rather than a
  /// floating overlay window. See the earlier design discussion for why:
  /// `SYSTEM_ALERT_WINDOW` overlays draw heavy Play Store review scrutiny
  /// for non-emergency uses, while this achieves the same "glanceable
  /// while using other apps" effect the same way music players do, at no
  /// extra permission cost and for negligible battery — the OS renders
  /// the ticking counter itself, this call doesn't need to repeat.
  ///
  /// Honest limitation: this keeps the notification alive and updating
  /// while the app process is alive, but doesn't run a true Android
  /// foreground service — under sustained memory pressure while fully
  /// backgrounded for a long time, the OS can still suspend the process
  /// earlier than a foreground-service-backed app would. Making this
  /// bulletproof needs a dedicated foreground service, which is real
  /// native Android work scoped out of this step.
  Future<void> showOngoingNotification({
    required int id,
    required String title,
    required DateTime startedAt,
    bool isCountdown = false,
    Duration? duration,
  }) async {
    if (kIsWeb || Platform.isLinux) return;

    await requestPermissions();

    final whenMs = isCountdown && duration != null
        ? DateTime.now().add(duration).millisecondsSinceEpoch
        : startedAt.millisecondsSinceEpoch;

    final details = AndroidNotificationDetails(
      _lightChannelId,
      'Reminders',
      ongoing: true,
      autoCancel: false,
      usesChronometer: true,
      chronometerCountDown: isCountdown,
      when: whenMs,
      showWhen: true,
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.status,
    );

    if (Platform.isAndroid) {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) {
        try {
          await android.startForegroundService(
            id: id,
            title: title,
            body: isCountdown ? 'Focusing...' : 'Stopwatch running',
            notificationDetails: details,
          );
          return;
        } catch (e) {
          debugPrint('Failed to start foreground service: $e');
        }
      }
    }

    await _plugin.show(
      id: id,
      title: title,
      body: isCountdown ? 'Focusing...' : 'Stopwatch running',
      notificationDetails: NotificationDetails(
        android: details,
      ),
    );
  }

  Future<void> cancelOngoingNotification(int id) async {
    if (kIsWeb || Platform.isLinux) return;

    if (Platform.isAndroid) {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) {
        try {
          await android.stopForegroundService();
        } catch (e) {
          debugPrint('Failed to stop foreground service: $e');
        }
      }
    }
    await _plugin.cancel(id: id);
  }

  NotificationDetails _detailsForPreset(AlarmPreset preset) {
    final actions = [
      const AndroidNotificationAction(_snoozeActionId, 'Snooze'),
      const AndroidNotificationAction(
        _doneActionId,
        'Mark done',
        cancelNotification: true,
      ),
    ];

    switch (preset) {
      case AlarmPreset.light:
        return NotificationDetails(
          android: AndroidNotificationDetails(
            _lightChannelId,
            'Reminders',
            importance: Importance.high,
            priority: Priority.high,
            category: AndroidNotificationCategory.reminder,
            actions: actions,
          ),
        );
      case AlarmPreset.medium:
        return NotificationDetails(
          android: AndroidNotificationDetails(
            _mediumChannelId,
            'Alarms',
            importance: Importance.max,
            priority: Priority.max,
            category: AndroidNotificationCategory.alarm,
            fullScreenIntent: true,
            actions: actions,
          ),
        );
      case AlarmPreset.strong:
        return NotificationDetails(
          android: AndroidNotificationDetails(
            _strongChannelId,
            'Strong Alarms',
            importance: Importance.max,
            priority: Priority.max,
            category: AndroidNotificationCategory.alarm,
            fullScreenIntent: true,
            actions: actions,
          ),
        );
      case AlarmPreset.constant:
        return NotificationDetails(
          android: AndroidNotificationDetails(
            _constantChannelId,
            'Constant Alarms',
            importance: Importance.max,
            priority: Priority.max,
            category: AndroidNotificationCategory.alarm,
            fullScreenIntent: true,
            additionalFlags: Int32List.fromList([4]), // FLAG_INSISTENT
            actions: actions,
          ),
        );
    }
  }

  int _stableId(String entityId, int offsetIndex) {
    // Deterministic from (entityId, offsetIndex) so recomputing it later
    // (e.g. to reschedule after an edit) always lands on the same
    // notification ID without needing to look anything up. Masked to a
    // positive 31-bit range — Android notification IDs are plain ints.
    return Object.hash(entityId, offsetIndex) & 0x7FFFFFFF;
  }

  void _handleForegroundResponse(NotificationResponse response) {
    final payload = AlarmPayload.decode(response.payload);
    if (payload == null) return;

    switch (response.actionId) {
      case _snoozeActionId:
        snooze(payload);
      case _doneActionId:
        markDone(payload);
      default:
        // A real body tap (or a full-screen intent actually firing —
        // the plugin routes that through this same callback, see its
        // README). Only medium's genuine full-screen moment gets the
        // ring screen; light is just a normal notification opening the
        // app to wherever it already was.
        _actionController.add(
          AlarmAction(payload.entityId, AlarmActionType.opened),
        );
        if (payload.preset == AlarmPreset.medium) {
          rootNavigatorKey.currentState?.push(
            MaterialPageRoute(
              builder: (_) => AlarmRingScreen(payload: payload),
            ),
          );
        }
    }
  }

  /// Reschedules [payload]'s alarm ~5 minutes out. Public because both
  /// the internal notification-action callback and [AlarmRingScreen]'s
  /// Snooze button call this directly.
  Future<void> snooze(
    AlarmPayload payload, {
    Duration snoozeFor = const Duration(minutes: 5),
  }) async {
    final fireAt = DateTime.now().add(snoozeFor);
    final id = _stableId(
      payload.entityId,
      -1,
    ); // -1: reserved for the "current snooze" slot
    if (!supportsScheduledAlarms) {
      _localAlarms.add(LocalAlarm(
        id: id,
        entityId: payload.entityId,
        title: payload.title,
        body: payload.body,
        fireAt: fireAt,
        preset: payload.preset,
        siblingIds: payload.siblingIds,
      ));
    } else {
      await _plugin.zonedSchedule(
        id: id,
        title: payload.title,
        body: payload.body,
        scheduledDate: tz.TZDateTime.from(fireAt, tz.local),
        notificationDetails: _detailsForPreset(payload.preset),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: payload.encode(),
      );
    }
    _actionController.add(
      AlarmAction(payload.entityId, AlarmActionType.snoozed),
    );
  }

  /// Cancels [payload]'s sibling alarms. Public for the same reason as
  /// [snooze] above.
  Future<void> markDone(AlarmPayload payload) async {
    await cancelByIds(payload.siblingIds);
    _actionController.add(AlarmAction(payload.entityId, AlarmActionType.done));
  }

  void _startLocalAlarmPolling() {
    _localAlarmTimer?.cancel();
    _localAlarmTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final now = DateTime.now();
      final due = _localAlarms.where((a) => a.fireAt.isBefore(now)).toList();
      for (final alarm in due) {
        _localAlarms.remove(alarm);
        _triggerLocalAlarm(alarm);
      }
    });
  }

  void _triggerLocalAlarm(LocalAlarm alarm) {
    final isConstant = alarm.preset == AlarmPreset.constant;
    final isLongSound = alarm.preset == AlarmPreset.strong || isConstant;
    _playAlarmSound(longSound: isLongSound, loop: isConstant);

    final context = rootNavigatorKey.currentContext;
    if (context == null) return;

    if (alarm.preset == AlarmPreset.light) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(alarm.title, style: const TextStyle(fontWeight: FontWeight.bold)),
              if (alarm.body.isNotEmpty) Text(alarm.body),
            ],
          ),
          action: SnackBarAction(
            label: 'Mark Done',
            onPressed: () {
              _stopAlarmSound();
              final payload = AlarmPayload(
                entityId: alarm.entityId,
                title: alarm.title,
                body: alarm.body,
                preset: alarm.preset,
                siblingIds: alarm.siblingIds,
              );
              markDone(payload);
            },
          ),
          duration: const Duration(seconds: 10),
        ),
      );
      Timer(const Duration(seconds: 5), () {
        _stopAlarmSound();
      });
    } else {
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return _InAppAlarmDialog(
            alarm: alarm,
            onSnooze: (snoozeMinutes) {
              _stopAlarmSound();
              final payload = AlarmPayload(
                entityId: alarm.entityId,
                title: alarm.title,
                body: alarm.body,
                preset: alarm.preset,
                siblingIds: alarm.siblingIds,
              );
              unawaited(snooze(payload, snoozeFor: Duration(minutes: snoozeMinutes)));
              Navigator.of(dialogContext).pop();
            },
            onDone: () {
              _stopAlarmSound();
              final payload = AlarmPayload(
                entityId: alarm.entityId,
                title: alarm.title,
                body: alarm.body,
                preset: alarm.preset,
                siblingIds: alarm.siblingIds,
              );
              unawaited(markDone(payload));
              Navigator.of(dialogContext).pop();
            },
          );
        },
      );
    }
  }

  void _playAlarmSound({bool longSound = false, bool loop = false}) async {
    _activeSoundProcess?.kill();
    _activeSoundProcess = null;

    final prefs = await SharedPreferences.getInstance();
    final soundPath = longSound
        ? (prefs.getString('settings.alarmLongSoundPath') ?? '/usr/share/sounds/ocean/stereo/phone-incoming-call.oga')
        : (prefs.getString('settings.alarmShortSoundPath') ?? '/usr/share/sounds/ocean/stereo/alarm-clock-elapsed.oga');

    Future<void> runPlay() async {
      try {
        _activeSoundProcess = await Process.start('paplay', [soundPath]);
        if (loop) {
          unawaited(_activeSoundProcess?.exitCode.then((code) {
            if (_activeSoundProcess != null) {
              unawaited(runPlay());
            }
          }));
        }
      } catch (_) {
        try {
          _activeSoundProcess = await Process.start('pw-play', [soundPath]);
          if (loop) {
            unawaited(_activeSoundProcess?.exitCode.then((code) {
              if (_activeSoundProcess != null) {
                unawaited(runPlay());
              }
            }));
          }
        } catch (_) {
          try {
            _activeSoundProcess = await Process.start('aplay', ['/usr/share/sounds/alsa/Front_Center.wav']);
          } catch (_) {}
        }
      }
    }

    unawaited(runPlay());
  }

  void _stopAlarmSound() {
    _activeSoundProcess?.kill();
    _activeSoundProcess = null;
  }

  void dispose() {
    _localAlarmTimer?.cancel();
    _stopAlarmSound();
    _actionController.close();
  }
}

/// Runs in a separate isolate when the user taps a notification action
/// while the app is fully terminated. Timezones are initialized in this isolate,
/// and a direct sqlite/drift database connection is opened to immediately complete
/// tasks/habits and roll forward recurring schedules.
@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) async {
  final payload = AlarmPayload.decode(response.payload);
  if (payload == null) return;

  // Initialize timezones in this background isolate
  tz_data.initializeTimeZones();

  final plugin = FlutterLocalNotificationsPlugin();

  switch (response.actionId) {
    case _snoozeActionId:
      final fireAt = DateTime.now().add(const Duration(minutes: 5));
      unawaited(
        plugin.zonedSchedule(
          id: Object.hash(payload.entityId, -1) & 0x7FFFFFFF,
          title: payload.title,
          body: payload.body,
          scheduledDate: tz.TZDateTime.from(fireAt, tz.local),
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(_mediumChannelId, 'Alarms'),
          ),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          payload: response.payload,
        ),
      );
    case _doneActionId:
      for (final id in payload.siblingIds) {
        unawaited(plugin.cancel(id: id));
      }

      // Perform database updates in the background isolate
      try {
        final db = AppDatabase();

        // 1. Check if the entity is a Task and complete it
        final task = await (db.select(db.tasks)
              ..where((t) => t.id.equals(payload.entityId)))
            .getSingleOrNull();

        if (task != null) {
          await (db.update(db.tasks)
                ..where((t) => t.id.equals(payload.entityId)))
              .write(
            TasksCompanion(
              isCompleted: const Value(true),
              completedAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );

          // Cancel remaining alarms for this task
          if (task.scheduledAlarmIds != null) {
            final raw = task.scheduledAlarmIds;
            if (raw != null && raw.isNotEmpty) {
              final alarmIds = (jsonDecode(raw) as List<dynamic>).cast<int>();
              for (final id in alarmIds) {
                unawaited(plugin.cancel(id: id));
              }
            }
          }

          await (db.update(db.tasks)
                ..where((t) => t.id.equals(payload.entityId)))
              .write(
            const TasksCompanion(scheduledAlarmIds: Value(null)),
          );

          // Handle task recurrence
          final recurrenceRule = task.recurrenceRule;
          if (recurrenceRule != null && task.dueDate != null) {
            final recurrence = TaskRecurrence.decode(recurrenceRule);
            if (recurrence.isRecurring) {
              final nextDue = recurrence.nextOccurrence(task.dueDate!);
              final nextId = const Uuid().v4();
              await db.into(db.tasks).insert(
                TasksCompanion.insert(
                  id: Value(nextId),
                  listId: task.listId,
                  parentTaskId: Value(task.parentTaskId),
                  title: task.title,
                  description: Value(task.description),
                  priority: Value(task.priority),
                  dueDate: Value(nextDue),
                  dueHasTime: Value(task.dueHasTime),
                  recurrenceRule: Value(task.recurrenceRule),
                  durationMinutes: Value(task.durationMinutes),
                  alarmPreset: Value(task.alarmPreset),
                  reminderOffsetsMinutes: Value(task.reminderOffsetsMinutes),
                ),
              );
            }
          }
        }

        // 2. Check if the entity is a Habit and log completion for today
        final habit = await (db.select(db.habits)
              ..where((h) => h.id.equals(payload.entityId)))
            .getSingleOrNull();

        if (habit != null) {
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          await db.into(db.habitLogs).insert(
            HabitLogsCompanion.insert(
              habitId: habit.id,
              date: today,
              amount: Value(habit.goalAmount ?? 1),
              isCompleted: const Value(true),
            ),
            onConflict: DoUpdate(
              (old) => HabitLogsCompanion(
                habitId: Value(habit.id),
                date: Value(today),
                amount: Value(habit.goalAmount ?? 1),
                isCompleted: const Value(true),
              ),
              target: [db.habitLogs.habitId, db.habitLogs.date],
            ),
          );
        }

        await db.close();
      } catch (e) {
        debugPrint(
          'AlarmScheduler background isolate DB update failed: $e',
        );
      }
  }
}

class LocalAlarm {
  final int id;
  final String entityId;
  final String title;
  final String body;
  final DateTime fireAt;
  final AlarmPreset preset;
  final List<int> siblingIds;

  LocalAlarm({
    required this.id,
    required this.entityId,
    required this.title,
    required this.body,
    required this.fireAt,
    required this.preset,
    required this.siblingIds,
  });
}

class _InAppAlarmDialog extends StatefulWidget {
  final LocalAlarm alarm;
  final void Function(int minutes) onSnooze;
  final VoidCallback onDone;

  const _InAppAlarmDialog({
    required this.alarm,
    required this.onSnooze,
    required this.onDone,
  });

  @override
  State<_InAppAlarmDialog> createState() => _InAppAlarmDialogState();
}

class _InAppAlarmDialogState extends State<_InAppAlarmDialog> {
  int _snoozeMinutes = 5;
  Timer? _autoSnoozeTimer;
  late int _remainingSeconds;

  @override
  void initState() {
    super.initState();
    final isConstant = widget.alarm.preset == AlarmPreset.constant;
    _remainingSeconds = isConstant ? 600 : 30; // 10 minutes or 30 seconds

    _autoSnoozeTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds <= 1) {
        timer.cancel();
        widget.onSnooze(_snoozeMinutes);
      } else {
        if (mounted) {
          setState(() {
            _remainingSeconds--;
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _autoSnoozeTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () {}, // non-dismissible
              child: Container(
                color: Colors.black.withValues(alpha: 0.55),
              ),
            ),
          ),
          Center(
            child: Container(
              width: (mediaQuery.size.width * 0.85).clamp(280.0, 420.0),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF1E292B), // premium deep petrol dark color
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.45),
                    blurRadius: 25,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.alarm_on,
                    size: 64,
                    color: Color(0xFFD89B3C),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    widget.alarm.title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'Fraunces',
                      fontWeight: FontWeight.w600,
                      fontSize: 22,
                      color: Colors.white,
                    ),
                  ),
                  if (widget.alarm.body.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      widget.alarm.body,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 14,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  const Text(
                    'SNOOZE DURATION',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline, color: Colors.white70),
                        onPressed: () {
                          setState(() {
                            _snoozeMinutes = (_snoozeMinutes - 1).clamp(1, 60);
                          });
                        },
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black26,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '$_snoozeMinutes min',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline, color: Colors.white70),
                        onPressed: () {
                          setState(() {
                            _snoozeMinutes = (_snoozeMinutes + 1).clamp(1, 60);
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white38),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onPressed: () => widget.onSnooze(_snoozeMinutes),
                          child: const Text('Snooze'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFD89B3C),
                            foregroundColor: Colors.black87,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onPressed: widget.onDone,
                          child: const Text('Mark Done', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Auto-snoozing in $_remainingSeconds seconds...',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
