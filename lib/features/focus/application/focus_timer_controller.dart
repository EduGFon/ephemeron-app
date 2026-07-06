import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../core/settings/shared_preferences_provider.dart';
import '../../alarms/application/alarm_scheduler_provider.dart';
import 'focus_metrics_providers.dart';
import '../domain/focus_mode.dart';
import 'focus_repository_provider.dart';
import 'focus_timer_state.dart';

// Fixed notification ID — only one focus session can ever be active at
// once, so there's no need for the per-entity hashing scheme the alarm
// engine uses elsewhere.
const _ongoingNotificationId =
    0x46435553; // 'FCUS' as hex, arbitrary but stable

class FocusTimerController extends Notifier<FocusTimerState> {
  Timer? _ticker;
  Duration _accumulatedBeforePause = Duration.zero;
  // The session's true first start, distinct from state.startedAt (which
  // resets on every resume-after-pause) — needed so a paused-and-resumed
  // session still records its real start time, not one skewed forward by
  // however long it was paused.
  DateTime? _trueSessionStart;

  @override
  FocusTimerState build() {
    ref.onDispose(() {
      _ticker?.cancel();
      unawaited(WakelockPlus.disable());
    });

    final prefs = ref.watch(sharedPreferencesProvider);
    final savedModeStr = prefs.getString('focus.lastMode');
    final initialMode = savedModeStr == 'stopwatch' ? FocusMode.stopwatch : FocusMode.pomodoro;

    return FocusTimerState(mode: initialMode);
  }

  void setMode(FocusMode mode) {
    if (state.isRunning) return; // don't allow switching mid-session
    state = state.copyWith(mode: mode, elapsed: Duration.zero);
    ref.read(sharedPreferencesProvider).setString('focus.lastMode', mode.name);
  }

  void setLinkedTask(String? taskId) {
    state = state.copyWith(
      linkedTaskId: () => taskId,
      linkedHabitId: () => null,
    );
  }

  void setLinkedHabit(String? habitId) {
    state = state.copyWith(
      linkedHabitId: () => habitId,
      linkedTaskId: () => null,
    );
  }

  void setNote(String note) => state = state.copyWith(note: note);

  Future<void> setKeepScreenOn(bool value) async {
    state = state.copyWith(keepScreenOn: value);
    if (state.isRunning) {
      await WakelockPlus.toggle(enable: value);
    }
  }

  Future<void> start() async {
    if (state.isRunning) return;
    final now = DateTime.now();
    _trueSessionStart ??= now;
    _accumulatedBeforePause = state.elapsed;
    state = state.copyWith(
      isRunning: true,
      startedAt: () => now,
      pomodoroPhase: state.elapsed == Duration.zero
          ? PomodoroPhase.work
          : state.pomodoroPhase,
    );

    if (state.keepScreenOn) await WakelockPlus.enable();

    final scheduler = ref.read(alarmSchedulerProvider);
    await scheduler.showOngoingNotification(
      id: _ongoingNotificationId,
      title: state.mode == FocusMode.pomodoro
          ? 'Focus (Pomodoro)'
          : 'Focus session',
      startedAt: now,
    );

    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    final startedAt = state.startedAt;
    if (startedAt == null) return;
    final elapsed =
        _accumulatedBeforePause + DateTime.now().difference(startedAt);

    if (state.mode == FocusMode.pomodoro && elapsed >= state.pomodoroTarget) {
      // Flip phase and restart the phase clock — MVP scope is a visual
      // phase change only; a dedicated "break time!" alert is a Phase 2
      // addition rather than bundled into this already-large step.
      final nextPhase = state.pomodoroPhase == PomodoroPhase.work
          ? PomodoroPhase.breakTime
          : PomodoroPhase.work;
      _accumulatedBeforePause = Duration.zero;
      state = state.copyWith(
        pomodoroPhase: nextPhase,
        elapsed: Duration.zero,
        startedAt: () => DateTime.now(),
      );
      return;
    }

    state = state.copyWith(elapsed: elapsed);
  }

  void pause() {
    if (!state.isRunning) return;
    _ticker?.cancel();
    _accumulatedBeforePause = state.elapsed;
    state = state.copyWith(isRunning: false);
    unawaited(WakelockPlus.disable());
  }

  Future<void> resume() => start();

  /// Ends the session: stops the ticker, persists it (if long enough —
  /// see FocusRepository.endSession), applies habit-goal time credit if
  /// applicable, tears down the wakelock and ongoing notification, and
  /// resets to idle.
  Future<String?> stop() async {
    _ticker?.cancel();
    final wasRunning = state.startedAt != null;
    if (!wasRunning) return null;

    final finalElapsed = state.isRunning
        ? _accumulatedBeforePause + DateTime.now().difference(state.startedAt!)
        : state.elapsed;
    final sessionStart =
        _trueSessionStart ?? DateTime.now().subtract(finalElapsed);

    final repo = ref.read(focusRepositoryProvider);
    final sessionId = await repo.endSession(
      mode: state.mode,
      startedAt: sessionStart,
      endedAt: DateTime.now(),
      linkedTaskId: state.linkedTaskId,
      linkedHabitId: state.linkedHabitId,
      note: state.note.isEmpty ? null : state.note,
    );

    await WakelockPlus.disable();
    await ref
        .read(alarmSchedulerProvider)
        .cancelOngoingNotification(_ongoingNotificationId);

    if (sessionId != null) {
      ref.read(focusMetricsRefreshProvider.notifier).state++;
    }

    _accumulatedBeforePause = Duration.zero;
    _trueSessionStart = null;
    state = FocusTimerState(mode: state.mode);
    return sessionId;
  }
}

final focusTimerControllerProvider =
    NotifierProvider<FocusTimerController, FocusTimerState>(
      FocusTimerController.new,
    );
