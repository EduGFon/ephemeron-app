import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../calendar/application/calendar_providers.dart';
import '../../tasks/application/task_providers.dart';
import '../../../core/settings/app_settings_provider.dart';
import '../../../core/utils/dev_logger.dart';
import '../../auth/google/google_auth_provider.dart';
import '../../../data/local/database_provider.dart';
import 'package:drift/drift.dart';

class SyncState {
  final bool isSyncing;
  final DateTime? lastSyncedAt;
  final String? error;

  SyncState({this.isSyncing = false, this.lastSyncedAt, this.error});

  SyncState copyWith({bool? isSyncing, DateTime? lastSyncedAt, String? error}) {
    return SyncState(
      isSyncing: isSyncing ?? this.isSyncing,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      error: error ?? this.error,
    );
  }
}

class SyncService extends Notifier<SyncState> {
  Timer? _syncTimer;

  @override
  SyncState build() {
    // Listen to settings changes to schedule/re-schedule the timer
    final settings = ref.watch(appSettingsProvider);
    _setupTimer(settings.autoSync, settings.syncIntervalMinutes);

    ref.onDispose(() {
      _syncTimer?.cancel();
    });

    return SyncState();
  }

  void _setupTimer(bool autoSync, int intervalMinutes) {
    _syncTimer?.cancel();
    if (!autoSync) return;

    _syncTimer = Timer.periodic(Duration(minutes: intervalMinutes), (timer) {
      sync();
    });
  }

  /// Perform a manual or automatic synchronization.
  Future<void> sync() async {
    if (state.isSyncing) return;

    state = state.copyWith(isSyncing: true, error: null);

    DevLogger.log('Starting sync with remote...');
    try {
      // 1. Sync Calendar Events (from previous month to 3 months ahead)
      final now = DateTime.now();
      final start = DateTime(now.year, now.month - 1, 1);
      final end = DateTime(now.year, now.month + 3, 1);
      
      DevLogger.log('Syncing calendar events from $start to $end...');
      ref.read(deviceCalendarRepositoryProvider).clearCache();
      final calendarRepo = ref.read(calendarRepositoryProvider);
      await calendarRepo.refreshEventsFromRemote(rangeStart: start, rangeEnd: end);
      DevLogger.log('Calendar events sync completed.');

      // 2. Sync Tasks
      DevLogger.log('Syncing tasks with remote...');
      final taskRepo = ref.read(taskRepositoryProvider);
      await taskRepo.syncTasksWithRemote();
      DevLogger.log('Tasks sync completed.');

      // 3. Invalidate/Refresh relevant providers to update the UI
      ref.invalidate(monthEventsProvider);
      final currentMonth = DateTime(now.year, now.month, 1);
      ref.invalidate(monthEventsProvider(currentMonth));

      DevLogger.log('Sync completed successfully.');
      state = state.copyWith(
        isSyncing: false,
        lastSyncedAt: DateTime.now(),
      );

      // Reschedule the auto-sync timer to avoid useless syncs in a short time
      final settings = ref.read(appSettingsProvider);
      _setupTimer(settings.autoSync, settings.syncIntervalMinutes);
    } catch (e, stack) {
      DevLogger.logError('Sync failed', e, stack);
      state = state.copyWith(
        isSyncing: false,
        error: e.toString(),
      );
    }
  }
}

final syncServiceProvider = NotifierProvider<SyncService, SyncState>(() {
  return SyncService();
});

final hasUnsyncedChangesProvider = StreamProvider<bool>((ref) {
  final account = ref.watch(googleAccountProvider).value;
  if (account == null) {
    return Stream.value(false);
  }
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.tasks)
        ..where((t) => t.googleTaskId.isNull() & t.isDeleted.equals(false)))
      .watch()
      .map((tasks) => tasks.isNotEmpty);
});
