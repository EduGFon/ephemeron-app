import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

// Deliberately public, not a private `_tableIdGenerator` — drift_dev
// re-embeds this clientDefault expression into database.g.dart, which is
// a part of database.dart's library, not this file's. A private
// identifier here is invisible from that library and fails to compile
// with "getter '_x' isn't defined" errors in the generated code; this
// was found and fixed during real-device testing on Linux.
const tableIdGenerator = Uuid();

/// Task lists (Inbox, Personal, Work, ...). One default Inbox list is
/// seeded on first run (see database.dart).
///
/// @DataClassName is required here — without it, Drift would generate a
/// data class literally named `List`, colliding with dart:core's `List<T>`
/// and making every file that imports both a headache. Caught and fixed
/// in Step 3, the first step that actually generates and uses this class.
@DataClassName('TaskList')
class Lists extends Table {
  TextColumn get id => text().clientDefault(() => tableIdGenerator.v4())();
  TextColumn get name => text()();
  TextColumn get colorHex => text().withDefault(const Constant('#1B4B4A'))();
  TextColumn get backgroundHex => text().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get isInbox => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt =>
      dateTime().clientDefault(() => DateTime.now())();

  @override
  Set<Column> get primaryKey => {id};
}

class Tags extends Table {
  TextColumn get id => text().clientDefault(() => tableIdGenerator.v4())();
  TextColumn get name => text()();
  TextColumn get colorHex => text().withDefault(const Constant('#D89B3C'))();
  // Default configs — auto-applied when this tag is selected in the event form
  TextColumn get defaultAlarmPreset => text().nullable()();  // 'light'|'medium'|'strong'|'constant'
  TextColumn get defaultColorHex => text().nullable()();     // e.g. '#7986CB'
  TextColumn get defaultNoteFolderId => text().nullable()(); // NoteFolder.id

  @override
  Set<Column> get primaryKey => {id};
}

/// Fields split into two intents, on purpose:
///  - fields also present in the Google Tasks API (title, description,
///    dueDate, isCompleted, parentTaskId one level deep) are best-effort
///    mirrored via [googleTaskId];
///  - everything else (priority, recurrenceRule, tags, duration, pin,
///    won't-do) is local-only, because the Tasks API has no field for
///    them — see the earlier CASA/Tasks-API-limits discussion.
class Tasks extends Table {
  TextColumn get id => text().clientDefault(() => tableIdGenerator.v4())();
  TextColumn get googleTaskId => text().nullable()();
  TextColumn get listId => text().references(Lists, #id)();
  TextColumn get parentTaskId => text().nullable().references(Tasks, #id)();
  TextColumn get title => text()();
  TextColumn get description => text().nullable()();
  IntColumn get priority =>
      integer().withDefault(const Constant(0))(); // 0 none .. 3 high
  DateTimeColumn get dueDate => dateTime().nullable()();
  BoolColumn get dueHasTime => boolean().withDefault(const Constant(false))();
  // Local-only recurrence description (RRULE-like); Google Tasks API
  // cannot read or write recurrence at all.
  TextColumn get recurrenceRule => text().nullable()();
  IntColumn get durationMinutes => integer().withDefault(const Constant(30))();
  BoolColumn get isCompleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get completedAt => dateTime().nullable()();
  BoolColumn get isWontDo => boolean().withDefault(const Constant(false))();
  BoolColumn get isPinned => boolean().withDefault(const Constant(false))();
  // Soft delete, backing the "Trash" smart list — nothing is ever hard
  // deleted from a user action alone, avoiding accidental permanent loss.
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  // Alarm linkage (Step 2 integration) — 'light'/'medium', matching
  // AlarmPreset.name; null means no alarm configured for this task.
  TextColumn get alarmPreset => text().nullable()();
  // JSON-encoded list of minutes-before-due for each configured
  // reminder (see ReminderOffset) — kept as opaque JSON here rather than
  // a join table since offsets are a small, fixed-shape list per task.
  TextColumn get reminderOffsetsMinutes => text().nullable()();
  // JSON-encoded list of the notification IDs AlarmScheduler returned
  // when these reminders were scheduled — needed to cancel/reschedule
  // them without recomputing hashes that could drift out of sync.
  TextColumn get scheduledAlarmIds => text().nullable()();
  DateTimeColumn get createdAt =>
      dateTime().clientDefault(() => DateTime.now())();
  DateTimeColumn get updatedAt =>
      dateTime().clientDefault(() => DateTime.now())();

  @override
  Set<Column> get primaryKey => {id};
}

class TaskTags extends Table {
  TextColumn get taskId => text().references(Tasks, #id)();
  TextColumn get tagId => text().references(Tags, #id)();

  @override
  Set<Column> get primaryKey => {taskId, tagId};
}

/// Links a Google Calendar event to local tags. Calendar events
/// themselves are never stored locally (Google Calendar is the source
/// of truth for those, unlike Tasks) — this table exists purely because
/// the Calendar API's own colorId is a fixed 11-color palette, not a
/// custom tag system, so richer tagging/filtering needs a local layer
/// keyed by the Google event ID. See the Step 4 README section for the
/// full reasoning.
class EventTags extends Table {
  TextColumn get googleEventId => text()();
  TextColumn get tagId => text().references(Tags, #id)();

  @override
  Set<Column> get primaryKey => {googleEventId, tagId};
}

class Habits extends Table {
  TextColumn get id => text().clientDefault(() => tableIdGenerator.v4())();
  TextColumn get name => text()();
  // morning / afternoon / night / other / <custom section id>
  TextColumn get section => text().withDefault(const Constant('other'))();
  // daily / weekly / interval
  TextColumn get frequencyType => text()();
  // JSON-encoded detail: weekdays for daily-custom, timesPerWeek for
  // weekly, everyNDays for interval. Kept as opaque JSON in the skeleton;
  // typed columns arrive when Habits is built out in step 6.
  TextColumn get frequencyConfig => text().nullable()();
  // binary / amount
  TextColumn get goalType => text().withDefault(const Constant('binary'))();
  RealColumn get goalAmount => real().nullable()();
  TextColumn get goalUnit => text().nullable()();
  // How much a single quick-log tap adds toward goalAmount (e.g. goal
  // "2 hours" with logIncrement 1 means each tap logs 1 hour; goal
  // "2500 ml" with logIncrement 200 means each tap logs 200 ml). Only
  // meaningful when goalType is 'amount'.
  RealColumn get logIncrement => real().withDefault(const Constant(1))();
  // 7 / 21 / 30 / 100 / 365 / forever / custom
  TextColumn get goalDuration =>
      text().withDefault(const Constant('forever'))();
  DateTimeColumn get startDate =>
      dateTime().clientDefault(() => DateTime.now())();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  // Reminder time-of-day (not a due date — habits recur, so this is
  // "what time each applicable day" rather than a one-shot moment).
  // Both null means no reminder configured.
  IntColumn get reminderHour => integer().nullable()();
  IntColumn get reminderMinute => integer().nullable()();
  // 'light'/'medium', matching AlarmPreset.name — null means no alarm.
  TextColumn get alarmPreset => text().nullable()();
  // JSON-encoded notification IDs currently scheduled for this habit —
  // same bookkeeping purpose as Tasks.scheduledAlarmIds.
  TextColumn get scheduledAlarmIds => text().nullable()();
  DateTimeColumn get createdAt =>
      dateTime().clientDefault(() => DateTime.now())();

  @override
  Set<Column> get primaryKey => {id};
}

class HabitLogs extends Table {
  TextColumn get id => text().clientDefault(() => tableIdGenerator.v4())();
  TextColumn get habitId => text().references(Habits, #id)();
  DateTimeColumn get date => dateTime()();
  RealColumn get amount => real().withDefault(const Constant(0))();
  BoolColumn get isCompleted => boolean().withDefault(const Constant(false))();

  // One log per habit per day — lets logging today's progress be a
  // clean insertOnConflictUpdate instead of a manual
  // check-then-insert-or-update dance.
  @override
  List<Set<Column>> get uniqueKeys => [
    {habitId, date},
  ];

  @override
  Set<Column> get primaryKey => {id};
}

class FocusSessions extends Table {
  TextColumn get id => text().clientDefault(() => tableIdGenerator.v4())();
  TextColumn get mode => text()(); // pomodoro / stopwatch
  TextColumn get linkedTaskId => text().nullable().references(Tasks, #id)();
  TextColumn get linkedHabitId => text().nullable().references(Habits, #id)();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get endedAt => dateTime().nullable()();
  IntColumn get durationSeconds => integer().withDefault(const Constant(0))();
  TextColumn get note => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class Countdowns extends Table {
  TextColumn get id => text().clientDefault(() => tableIdGenerator.v4())();
  TextColumn get title => text()();
  // holiday / anniversary / birthday / custom
  TextColumn get type => text().withDefault(const Constant('custom'))();
  DateTimeColumn get targetDate => dateTime()();
  BoolColumn get isYearly => boolean().withDefault(const Constant(false))();
  BoolColumn get showAge => boolean().withDefault(const Constant(false))();
  // Countdown alerts are a fixed default (3 days before + at the day,
  // per the brainstorm) rather than user-configurable like Tasks/Events
  // — this only needs to track what's currently scheduled, not a preset
  // or offset list.
  TextColumn get scheduledAlarmIds => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class NoteFolders extends Table {
  TextColumn get id => text().clientDefault(() => tableIdGenerator.v4())();
  TextColumn get name => text()();
  TextColumn get parentFolderId => text().nullable().references(NoteFolders, #id)();
  DateTimeColumn get createdAt =>
      dateTime().clientDefault(() => DateTime.now())();

  @override
  Set<Column> get primaryKey => {id};
}

class Notes extends Table {
  TextColumn get id => text().clientDefault(() => tableIdGenerator.v4())();
  TextColumn get title => text()();
  TextColumn get content => text()();
  TextColumn get folderId => text().nullable().references(NoteFolders, #id)();
  TextColumn get eventId => text().nullable()();
  TextColumn get linkedCalendarId => text().nullable()();
  DateTimeColumn get createdAt =>
      dateTime().clientDefault(() => DateTime.now())();
  DateTimeColumn get updatedAt =>
      dateTime().clientDefault(() => DateTime.now())();

  @override
  Set<Column> get primaryKey => {id};
}

class CachedCalendarEvents extends Table {
  TextColumn get id => text()();
  TextColumn get calendarId => text()();
  TextColumn get title => text()();
  TextColumn get description => text().nullable()();
  TextColumn get location => text().nullable()();
  DateTimeColumn get start => dateTime()();
  DateTimeColumn get end => dateTime()();
  BoolColumn get isAllDay => boolean().withDefault(const Constant(false))();
  TextColumn get colorId => text().nullable()();
  TextColumn get reminderMinutes => text().nullable()(); // JSON list of minutes
  TextColumn get attendees => text().nullable()(); // JSON list of emails
  BoolColumn get hasVideoConference => boolean().withDefault(const Constant(false))();
  TextColumn get videoConferenceLink => text().nullable()();
  TextColumn get selfResponseStatus => text().withDefault(const Constant('needsAction'))();

  @override
  Set<Column> get primaryKey => {id, calendarId};
}

