import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../data/local/database.dart';
import '../../alarms/data/alarm_scheduler.dart';
import '../../alarms/domain/alarm_preset.dart';
import '../../alarms/domain/reminder_offset.dart';
import '../domain/smart_list_type.dart';
import '../domain/task_recurrence.dart';
import 'google_tasks_mirror.dart';

const _uuid = Uuid();

class TaskRepository {
  TaskRepository(this._db, this._alarmScheduler, this._googleTasksMirror);

  final AppDatabase _db;
  final AlarmScheduler _alarmScheduler;
  // Null when the user hasn't connected Google — every mirror call below
  // treats that the same as "the push failed," which is the correct
  // behavior either way (local data stays authoritative).
  final GoogleTasksMirror? _googleTasksMirror;

  // ---------------------------------------------------------------------
  // Lists
  // ---------------------------------------------------------------------

  Stream<List<TaskList>> watchLists() {
    return (_db.select(
      _db.lists,
    )..orderBy([(t) => OrderingTerm.asc(t.sortOrder)])).watch();
  }

  Future<TaskList> createList({
    required String name,
    String colorHex = '#1B4B4A',
  }) async {
    final id = _uuid.v4();
    await _db
        .into(_db.lists)
        .insert(
          ListsCompanion.insert(
            id: Value(id),
            name: name,
            colorHex: Value(colorHex),
          ),
        );
    return (_db.select(_db.lists)..where((t) => t.id.equals(id))).getSingle();
  }

  Future<void> renameList(String listId, String name) async {
    await (_db.update(_db.lists)..where((t) => t.id.equals(listId))).write(
      ListsCompanion(name: Value(name)),
    );
  }

  /// Deletes a list and reassigns its tasks to Inbox rather than
  /// cascading the delete onto them — losing a list's organization
  /// shouldn't mean losing the tasks themselves.
  Future<void> deleteList(String listId) async {
    final list = await (_db.select(
      _db.lists,
    )..where((t) => t.id.equals(listId))).getSingleOrNull();
    if (list == null || list.isInbox) return; // Inbox can't be deleted.

    final inbox = await _inboxList();
    await (_db.update(_db.tasks)..where((t) => t.listId.equals(listId))).write(
      TasksCompanion(listId: Value(inbox.id)),
    );
    await (_db.delete(_db.lists)..where((t) => t.id.equals(listId))).go();
  }

  Future<TaskList> _inboxList() {
    return (_db.select(
      _db.lists,
    )..where((t) => t.isInbox.equals(true))).getSingle();
  }

  // ---------------------------------------------------------------------
  // Watches
  // ---------------------------------------------------------------------

  Stream<List<Task>> watchTasksInList(String listId) {
    return (_db.select(_db.tasks)
          ..where(
            (t) =>
                t.listId.equals(listId) &
                t.isDeleted.equals(false) &
                t.parentTaskId.isNull(),
          )
          ..orderBy([
            (t) => OrderingTerm.desc(t.isPinned),
            (t) => OrderingTerm.asc(t.dueDate),
            (t) => OrderingTerm.asc(t.createdAt),
          ]))
        .watch();
  }

  Stream<List<Task>> watchAllPendingTasks() {
    return (_db.select(_db.tasks)
          ..where(
            (t) =>
                t.isDeleted.equals(false) &
                t.isCompleted.equals(false) &
                t.isWontDo.equals(false) &
                t.parentTaskId.isNull(),
          ))
        .watch();
  }

  Stream<List<Task>> watchAllActiveTasks() {
    return (_db.select(_db.tasks)
          ..where(
            (t) =>
                t.isDeleted.equals(false) &
                t.isWontDo.equals(false) &
                t.parentTaskId.isNull(),
          ))
        .watch();
  }

  Stream<List<Task>> watchSubtasks(String parentTaskId) {
    return (_db.select(_db.tasks)..where(
          (t) =>
              t.parentTaskId.equals(parentTaskId) & t.isDeleted.equals(false),
        ))
        .watch();
  }

  Stream<List<Task>> watchSmartList(SmartListType type) {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final startOfTomorrow = startOfToday.add(const Duration(days: 1));
    final startOfDayAfterTomorrow = startOfToday.add(const Duration(days: 2));
    final startOfNext7 = startOfToday.add(const Duration(days: 7));

    final query = _db.select(_db.tasks)..where((t) => t.parentTaskId.isNull());

    switch (type) {
      case SmartListType.today:
        query.where(
          (t) =>
              t.isDeleted.equals(false) &
              t.isWontDo.equals(false) &
              t.isCompleted.equals(false) &
              t.dueDate.isBiggerOrEqualValue(startOfToday) &
              t.dueDate.isSmallerThanValue(startOfTomorrow),
        );
      case SmartListType.tomorrow:
        query.where(
          (t) =>
              t.isDeleted.equals(false) &
              t.isWontDo.equals(false) &
              t.isCompleted.equals(false) &
              t.dueDate.isBiggerOrEqualValue(startOfTomorrow) &
              t.dueDate.isSmallerThanValue(startOfDayAfterTomorrow),
        );
      case SmartListType.next7Days:
        query.where(
          (t) =>
              t.isDeleted.equals(false) &
              t.isWontDo.equals(false) &
              t.isCompleted.equals(false) &
              t.dueDate.isBiggerOrEqualValue(startOfToday) &
              t.dueDate.isSmallerThanValue(startOfNext7),
        );
      case SmartListType.completed:
        query.where(
          (t) => t.isDeleted.equals(false) & t.isCompleted.equals(true),
        );
      case SmartListType.trash:
        query.where((t) => t.isDeleted.equals(true));
      case SmartListType.wontDo:
        query.where((t) => t.isDeleted.equals(false) & t.isWontDo.equals(true));
    }

    query.orderBy([(t) => OrderingTerm.asc(t.dueDate)]);
    return query.watch();
  }

  // ---------------------------------------------------------------------
  // Task CRUD
  // ---------------------------------------------------------------------

  Future<Task> createTask({
    required String listId,
    required String title,
    String? description,
    int priority = 0,
    DateTime? dueDate,
    bool dueHasTime = false,
    TaskRecurrence recurrence = TaskRecurrence.none,
    int durationMinutes = 30,
    String? parentTaskId,
    AlarmPreset? alarmPreset,
    List<ReminderOffset> reminderOffsets = const [],
  }) async {
    final id = _uuid.v4();

    await _db
        .into(_db.tasks)
        .insert(
          TasksCompanion.insert(
            id: Value(id),
            listId: listId,
            parentTaskId: Value(parentTaskId),
            title: title,
            description: Value(description),
            priority: Value(priority),
            dueDate: Value(dueDate),
            dueHasTime: Value(dueHasTime),
            recurrenceRule: Value(
              recurrence.isRecurring ? recurrence.encode() : null,
            ),
            durationMinutes: Value(durationMinutes),
            alarmPreset: Value(alarmPreset?.name),
            reminderOffsetsMinutes: Value(_encodeOffsets(reminderOffsets)),
          ),
        );

    await _syncAlarmsAndRemote(id);
    return (_db.select(_db.tasks)..where((t) => t.id.equals(id))).getSingle();
  }

  /// Partial update — pass only the fields that changed. Alarms are
  /// always fully recomputed after any update (cheap: cancel +
  /// reschedule) rather than trying to diff what specifically changed,
  /// which would be a lot of extra branching for very little benefit
  /// here.
  Future<void> updateTask(
    String taskId, {
    String? title,
    String? description,
    int? priority,
    Value<DateTime?>? dueDate,
    bool? dueHasTime,
    TaskRecurrence? recurrence,
    int? durationMinutes,
    Value<AlarmPreset?>? alarmPreset,
    List<ReminderOffset>? reminderOffsets,
  }) async {
    await (_db.update(_db.tasks)..where((t) => t.id.equals(taskId))).write(
      TasksCompanion(
        title: title != null ? Value(title) : const Value.absent(),
        description: description != null
            ? Value(description)
            : const Value.absent(),
        priority: priority != null ? Value(priority) : const Value.absent(),
        dueDate: dueDate ?? const Value.absent(),
        dueHasTime: dueHasTime != null
            ? Value(dueHasTime)
            : const Value.absent(),
        recurrenceRule: recurrence != null
            ? Value(recurrence.isRecurring ? recurrence.encode() : null)
            : const Value.absent(),
        durationMinutes: durationMinutes != null
            ? Value(durationMinutes)
            : const Value.absent(),
        alarmPreset: alarmPreset != null
            ? Value(alarmPreset.value?.name)
            : const Value.absent(),
        reminderOffsetsMinutes: reminderOffsets != null
            ? Value(_encodeOffsets(reminderOffsets))
            : const Value.absent(),
        updatedAt: Value(DateTime.now()),
      ),
    );
    await _syncAlarmsAndRemote(taskId);
  }

  /// Marks complete and, if the task recurs, creates the next occurrence
  /// as a fresh task — matching common task-app UX (the completed
  /// instance stays in history rather than the same row silently
  /// jumping forward in time).
  Future<void> completeTask(String taskId) async {
    final task = await _getTask(taskId);
    if (task == null) return;

    await (_db.update(_db.tasks)..where((t) => t.id.equals(taskId))).write(
      TasksCompanion(
        isCompleted: const Value(true),
        completedAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
      ),
    );
    await _cancelAlarms(task);
    await _pushCompletionToRemote(task, isCompleted: true);

    final recurrence = TaskRecurrence.decode(task.recurrenceRule);
    if (recurrence.isRecurring && task.dueDate != null) {
      final nextDue = recurrence.nextOccurrence(task.dueDate!);
      await createTask(
        listId: task.listId,
        title: task.title,
        description: task.description,
        priority: task.priority,
        dueDate: nextDue,
        dueHasTime: task.dueHasTime,
        recurrence: recurrence,
        durationMinutes: task.durationMinutes,
        alarmPreset: task.alarmPreset != null
            ? AlarmPreset.values.byName(task.alarmPreset!)
            : null,
        reminderOffsets: _decodeOffsets(task.reminderOffsetsMinutes),
      );
    }
  }

  Future<void> uncompleteTask(String taskId) async {
    await (_db.update(_db.tasks)..where((t) => t.id.equals(taskId))).write(
      const TasksCompanion(isCompleted: Value(false), completedAt: Value(null)),
    );
    final task = await _getTask(taskId);
    if (task != null) {
      await _syncAlarmsAndRemote(taskId);
      await _pushCompletionToRemote(task, isCompleted: false);
    }
  }

  Future<void> toggleWontDo(String taskId) async {
    final task = await _getTask(taskId);
    if (task == null) return;
    final newValue = !task.isWontDo;
    await (_db.update(_db.tasks)..where((t) => t.id.equals(taskId))).write(
      TasksCompanion(isWontDo: Value(newValue)),
    );
    if (newValue) await _cancelAlarms(task);
  }

  Future<void> togglePin(String taskId) async {
    final task = await _getTask(taskId);
    if (task == null) return;
    await (_db.update(_db.tasks)..where((t) => t.id.equals(taskId))).write(
      TasksCompanion(isPinned: Value(!task.isPinned)),
    );
  }

  Future<void> softDeleteTask(String taskId) async {
    final task = await _getTask(taskId);
    if (task == null) return;
    await (_db.update(_db.tasks)..where((t) => t.id.equals(taskId))).write(
      TasksCompanion(
        isDeleted: const Value(true),
        deletedAt: Value(DateTime.now()),
      ),
    );
    await _cancelAlarms(task);
    if (task.googleTaskId != null) {
      await _googleTasksMirror?.deleteRemoteTask(task.googleTaskId!);
    }
  }

  Future<void> restoreTask(String taskId) async {
    await (_db.update(_db.tasks)..where((t) => t.id.equals(taskId))).write(
      const TasksCompanion(isDeleted: Value(false), deletedAt: Value(null)),
    );
    await _syncAlarmsAndRemote(taskId);
  }

  Future<void> permanentlyDeleteTask(String taskId) async {
    await (_db.delete(_db.tasks)..where((t) => t.id.equals(taskId))).go();
  }

  Future<void> emptyTrash() async {
    await (_db.delete(_db.tasks)..where((t) => t.isDeleted.equals(true))).go();
  }

  // ---------------------------------------------------------------------
  // Tags
  // ---------------------------------------------------------------------

  Stream<List<Tag>> watchAllTags() => _db.select(_db.tags).watch();

  Future<Tag> createTag({
    required String name,
    String colorHex = '#D89B3C',
  }) async {
    final id = _uuid.v4();
    await _db
        .into(_db.tags)
        .insert(
          TagsCompanion.insert(
            id: Value(id),
            name: name,
            colorHex: Value(colorHex),
          ),
        );
    return (_db.select(_db.tags)..where((t) => t.id.equals(id))).getSingle();
  }

  Future<void> assignTag(String taskId, String tagId) async {
    await _db
        .into(_db.taskTags)
        .insertOnConflictUpdate(
          TaskTagsCompanion.insert(taskId: taskId, tagId: tagId),
        );
  }

  Future<void> removeTag(String taskId, String tagId) async {
    await (_db.delete(
      _db.taskTags,
    )..where((t) => t.taskId.equals(taskId) & t.tagId.equals(tagId))).go();
  }

  Stream<List<Tag>> watchTagsForTask(String taskId) {
    final query = _db.select(_db.tags).join([
      innerJoin(_db.taskTags, _db.taskTags.tagId.equalsExp(_db.tags.id)),
    ])..where(_db.taskTags.taskId.equals(taskId));
    return query.watch().map(
      (rows) => rows.map((r) => r.readTable(_db.tags)).toList(),
    );
  }

  // ---------------------------------------------------------------------
  // Internal: alarms + Google Tasks mirror wiring
  // ---------------------------------------------------------------------

  Future<Task?> _getTask(String taskId) {
    return (_db.select(
      _db.tasks,
    )..where((t) => t.id.equals(taskId))).getSingleOrNull();
  }

  Future<void> _cancelAlarms(Task task) async {
    final ids = _decodeAlarmIds(task.scheduledAlarmIds);
    if (ids.isNotEmpty) await _alarmScheduler.cancelByIds(ids);
    await (_db.update(_db.tasks)..where((t) => t.id.equals(task.id))).write(
      const TasksCompanion(scheduledAlarmIds: Value(null)),
    );
  }

  /// Recomputes alarms for the task's current state (cancel-then-
  /// reschedule) and best-effort pushes it to the Google Tasks mirror.
  /// Called after every create/update/restore.
  Future<void> _syncAlarmsAndRemote(String taskId) async {
    final task = await _getTask(taskId);
    if (task == null) return;

    final existingIds = _decodeAlarmIds(task.scheduledAlarmIds);
    if (existingIds.isNotEmpty) await _alarmScheduler.cancelByIds(existingIds);

    List<int> newIds = [];
    final offsets = _decodeOffsets(task.reminderOffsetsMinutes);
    if (task.dueDate != null &&
        task.alarmPreset != null &&
        offsets.isNotEmpty &&
        !task.isCompleted) {
      newIds = await _alarmScheduler.scheduleAlarmsForOffsets(
        entityId: task.id,
        title: task.title,
        body: task.description ?? '',
        dueAt: task.dueDate!,
        offsets: offsets,
        preset: AlarmPreset.values.byName(task.alarmPreset!),
      );
    }

    await (_db.update(_db.tasks)..where((t) => t.id.equals(taskId))).write(
      TasksCompanion(
        scheduledAlarmIds: Value(newIds.isEmpty ? null : jsonEncode(newIds)),
      ),
    );

    await _pushToRemote(task);
  }

  Future<void> _pushToRemote(Task task) async {
    final mirror = _googleTasksMirror;
    if (mirror == null) return;

    if (task.googleTaskId == null) {
      final remoteId = await mirror.createRemoteTask(
        title: task.title,
        notes: task.description,
        dueDate: task.dueDate,
        isCompleted: task.isCompleted,
      );
      if (remoteId != null) {
        await (_db.update(_db.tasks)..where((t) => t.id.equals(task.id))).write(
          TasksCompanion(googleTaskId: Value(remoteId)),
        );
      }
    } else {
      await mirror.updateRemoteTask(
        googleTaskId: task.googleTaskId!,
        title: task.title,
        notes: task.description,
        dueDate: task.dueDate,
        isCompleted: task.isCompleted,
      );
    }
  }

  Future<void> _pushCompletionToRemote(
    Task task, {
    required bool isCompleted,
  }) async {
    if (task.googleTaskId == null) return;
    await _googleTasksMirror?.updateRemoteTask(
      googleTaskId: task.googleTaskId!,
      title: task.title,
      notes: task.description,
      dueDate: task.dueDate,
      isCompleted: isCompleted,
    );
  }

  String? _encodeOffsets(List<ReminderOffset> offsets) {
    if (offsets.isEmpty) return null;
    return jsonEncode(offsets.map((o) => o.beforeDue.inMinutes).toList());
  }

  List<ReminderOffset> _decodeOffsets(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    final minutes = (jsonDecode(raw) as List<dynamic>).cast<int>();
    return minutes.map(ReminderOffset.fromMinutes).toList();
  }

  List<int> _decodeAlarmIds(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    return (jsonDecode(raw) as List<dynamic>).cast<int>();
  }
}
