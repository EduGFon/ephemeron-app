import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../calendar/application/calendar_providers.dart';
import '../../tasks/application/task_providers.dart';
import '../../../core/settings/app_settings_provider.dart';

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

    try {
      // 1. Sync Calendar Events (from previous month to 3 months ahead)
      final now = DateTime.now();
      final start = DateTime(now.year, now.month - 1, 1);
      final end = DateTime(now.year, now.month + 3, 1);
      
      final calendarRepo = ref.read(calendarRepositoryProvider);
      await calendarRepo.refreshEventsFromRemote(rangeStart: start, rangeEnd: end);

      // 2. Sync Tasks
      final taskRepo = ref.read(taskRepositoryProvider);
      await taskRepo.syncTasksWithRemote();

      // 3. Invalidate/Refresh relevant providers to update the UI
      ref.invalidate(monthEventsProvider);
      // Wait, listEvents caches locally, so monthEventsProvider will load from cache instantly.
      // Refreshing monthEventsProvider for current month is helpful.
      final currentMonth = DateTime(now.year, now.month, 1);
      ref.invalidate(monthEventsProvider(currentMonth));

      state = state.copyWith(
        isSyncing: false,
        lastSyncedAt: DateTime.now(),
      );
    } catch (e) {
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
