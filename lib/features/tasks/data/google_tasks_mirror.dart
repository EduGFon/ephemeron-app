import 'package:googleapis/tasks/v1.dart' as gtasks;
import 'package:http/http.dart' as http;

import '../../../core/config/app_config.dart';
import '../../../core/network/bearer_http_client.dart';
import '../../auth/google/google_auth_repository.dart';

/// Mirrors the Google-Tasks-compatible subset of a local task (title,
/// notes, due date, completion, one level of subtask) to the user's
/// Google account — see the earlier design discussion on why priority,
/// tags, recurrence, and due-time can't make this round trip: the public
/// Tasks API simply has no fields for them.
///
/// Deliberately push-only (local -> remote) in this MVP step. Detecting
/// edits made directly in Google's own Tasks app and pulling them back
/// requires either polling-and-diffing or a webhook channel — the latter
/// needs a publicly reachable server, which conflicts with this app's
/// CASA-avoidance architecture (the backend must never touch Google
/// data). Client-side polling is the right way to add pull sync later;
/// not built yet, noted rather than silently skipped.
///
/// All Google Tasks lists collapse into Google's single built-in
/// "@default" list for now — Ephemeron's own Lists are a purely local
/// concept; nothing about how the user organizes tasks locally needs to
/// be mirrored in Google's list structure too.
class GoogleTasksMirror {
  GoogleTasksMirror(this._authRepository);

  final GoogleAuthRepository _authRepository;
  static const _defaultTaskList = '@default';

  Future<gtasks.TasksApi> _api() async {
    final client = BearerHttpClient(
      tokenProvider: () => _authRepository.getAccessToken(const [
        AppConfig.googleCalendarScope,
        AppConfig.googleTasksScope,
      ]),
      inner: http.Client(),
    );
    return gtasks.TasksApi(client);
  }

  /// Creates the remote task and returns its Google-assigned ID, to be
  /// stored as the local task's `googleTaskId`. Returns null on any
  /// failure — callers treat this as "not mirrored yet," not a fatal
  /// error; the local task remains the source of truth either way.
  Future<String?> createRemoteTask({
    required String title,
    String? notes,
    DateTime? dueDate,
    bool isCompleted = false,
  }) async {
    try {
      final api = await _api();
      final created = await api.tasks.insert(
        gtasks.Task(
          title: title,
          notes: notes,
          due: dueDate?.toUtc().toIso8601String(),
          status: isCompleted ? 'completed' : 'needsAction',
        ),
        _defaultTaskList,
      );
      return created.id;
    } catch (_) {
      return null;
    }
  }

  /// Best-effort update; silently no-ops on failure (offline, token
  /// expired, task deleted remotely by the user, etc.) — the next
  /// successful push will reconcile.
  Future<void> updateRemoteTask({
    required String googleTaskId,
    required String title,
    String? notes,
    DateTime? dueDate,
    required bool isCompleted,
  }) async {
    try {
      final api = await _api();
      await api.tasks.patch(
        gtasks.Task(
          title: title,
          notes: notes,
          due: dueDate?.toUtc().toIso8601String(),
          status: isCompleted ? 'completed' : 'needsAction',
        ),
        _defaultTaskList,
        googleTaskId,
      );
    } catch (_) {
      // See doc comment — best-effort.
    }
  }

  Future<void> deleteRemoteTask(String googleTaskId) async {
    try {
      final api = await _api();
      await api.tasks.delete(_defaultTaskList, googleTaskId);
    } catch (_) {
      // Already gone, or offline — either way nothing local depends on
      // this succeeding.
    }
  }

  /// Lists all tasks from the default task list.
  Future<List<gtasks.Task>> listRemoteTasks() async {
    try {
      final api = await _api();
      final result = await api.tasks.list(_defaultTaskList);
      return result.items ?? [];
    } catch (_) {
      return [];
    }
  }
}
