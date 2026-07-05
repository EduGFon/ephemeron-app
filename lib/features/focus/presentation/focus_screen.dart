import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/theme/theme_engine_provider.dart';
import '../../../core/theme/theme_palettes.dart';
import '../../habits/application/habit_providers.dart';
import '../../tasks/application/task_providers.dart';
import '../../tasks/domain/smart_list_type.dart';
import '../application/focus_metrics_providers.dart';
import '../application/focus_timer_controller.dart';
import '../application/focus_timer_state.dart';
import '../domain/focus_mode.dart';
import 'focus_month_screen.dart';

class FocusScreen extends ConsumerWidget {
  const FocusScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timerState = ref.watch(focusTimerControllerProvider);
    final controller = ref.read(focusTimerControllerProvider.notifier);
    final palette = ref.watch(themeEngineProvider);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text('Focus', style: TextStyle(color: palette.text, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Column(
            children: [
              SegmentedButton<FocusMode>(
                style: SegmentedButton.styleFrom(
                  backgroundColor: palette.surface.withValues(alpha: 0.5),
                  foregroundColor: palette.text,
                  selectedBackgroundColor: palette.primary.withValues(alpha: 0.2),
                  selectedForegroundColor: palette.primary,
                ),
                segments: const [
                  ButtonSegment(value: FocusMode.pomodoro, label: Text('Pomodoro')),
                  ButtonSegment(value: FocusMode.stopwatch, label: Text('Stopwatch')),
                ],
                selected: {timerState.mode},
                onSelectionChanged: timerState.isRunning
                    ? null
                    : (selection) => controller.setMode(selection.first),
              ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.1),
              
              const Spacer(),
              
              if (timerState.mode == FocusMode.pomodoro)
                Text(
                  timerState.pomodoroPhase == PomodoroPhase.work ? 'Focus' : 'Break',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: palette.primary,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ).animate(key: ValueKey(timerState.pomodoroPhase)).fadeIn().scale(),
              
              const SizedBox(height: 16),
              
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 32),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: palette.surface.withValues(alpha: palette.isAmoled ? 1.0 : 0.4),
                  boxShadow: [
                    BoxShadow(
                      color: palette.primary.withValues(alpha: timerState.isRunning ? 0.2 : 0.05),
                      blurRadius: timerState.isRunning ? 50 : 20,
                      spreadRadius: timerState.isRunning ? 10 : 0,
                    )
                  ],
                  border: Border.all(
                    color: palette.primary.withValues(alpha: timerState.isRunning ? 0.5 : 0.1),
                    width: 2,
                  ),
                ),
                child: ClipOval(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _formatDuration(timerState.elapsed),
                          style: TextStyle(
                            fontFamily: 'Fraunces',
                            fontSize: 72,
                            fontWeight: FontWeight.w600,
                            color: palette.text,
                            height: 1.0,
                          ),
                        ),
                        if (timerState.mode == FocusMode.pomodoro)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              'of ${_formatDuration(timerState.pomodoroTarget)}',
                              style: theme.textTheme.bodyMedium?.copyWith(color: palette.text.withValues(alpha: 0.6)),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ).animate(target: timerState.isRunning ? 1 : 0).scale(
                begin: const Offset(1, 1), 
                end: const Offset(1.05, 1.05), 
                duration: 1.seconds, 
                curve: Curves.easeInOutSine,
              ),

              const SizedBox(height: 48),
              
              _LinkPicker(state: timerState, controller: controller, palette: palette)
                  .animate().fadeIn(duration: 500.ms, delay: 200.ms).slideY(begin: 0.1),
              
              const SizedBox(height: 16),
              
              Container(
                decoration: BoxDecoration(
                  color: palette.surface.withValues(alpha: palette.isAmoled ? 1.0 : 0.4),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: palette.text.withValues(alpha: 0.1)),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: SwitchListTile(
                      title: Text('Keep screen on', style: TextStyle(color: palette.text)),
                      value: timerState.keepScreenOn,
                      onChanged: controller.setKeepScreenOn,
                      activeThumbColor: palette.primary,
                    ),
                  ),
                ),
              ).animate().fadeIn(duration: 500.ms, delay: 300.ms).slideY(begin: 0.1),
              
              const Spacer(),
              
              _Controls(state: timerState, controller: controller, palette: palette)
                  .animate().fadeIn(duration: 500.ms, delay: 400.ms).slideY(begin: 0.2),
              
              const SizedBox(height: 24),
              
              _TotalsRow(palette: palette).animate().fadeIn(duration: 500.ms, delay: 500.ms),
              const SizedBox(height: 90), // Bottom padding for floating pill
            ],
          ),
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }
}

class _LinkPicker extends ConsumerWidget {
  const _LinkPicker({required this.state, required this.controller, required this.palette});

  final FocusTimerState state;
  final FocusTimerController controller;
  final AppPalette palette;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (state.isRunning) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: palette.surface.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          state.linkedTaskId != null
              ? 'Linked to a task'
              : state.linkedHabitId != null
                  ? 'Linked to a habit'
                  : 'Not linked to a task or habit',
          style: TextStyle(color: palette.text.withValues(alpha: 0.8)),
        ),
      );
    }
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: palette.primary,
        side: BorderSide(color: palette.primary.withValues(alpha: 0.5)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      icon: const Icon(Icons.link),
      label: Text(
        state.linkedTaskId != null || state.linkedHabitId != null
            ? 'Change link'
            : 'Link to task/habit',
      ),
      onPressed: () => _showLinkPicker(context, ref),
    );
  }

  Future<void> _showLinkPicker(BuildContext context, WidgetRef ref) async {
    final tasksAsync = ref.read(smartListProvider(SmartListType.today));
    final habitsAsync = ref.read(habitsProvider);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: palette.surface.withValues(alpha: 0.9),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: SafeArea(
              child: ListView(
                shrinkWrap: true,
                children: [
                  const SizedBox(height: 8),
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: palette.text.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    title: Text('None', style: TextStyle(color: palette.text)),
                    onTap: () {
                      controller.setLinkedTask(null);
                      Navigator.pop(context);
                    },
                  ),
                  if (habitsAsync.value case final habits?)
                    for (final habit in habits)
                      ListTile(
                        leading: Icon(Icons.repeat_outlined, color: palette.text),
                        title: Text(habit.name, style: TextStyle(color: palette.text)),
                        onTap: () {
                          controller.setLinkedHabit(habit.id);
                          Navigator.pop(context);
                        },
                      ),
                  if (tasksAsync.value case final tasks?)
                    for (final task in tasks)
                      ListTile(
                        leading: Icon(Icons.checklist_outlined, color: palette.text),
                        title: Text(task.title, style: TextStyle(color: palette.text)),
                        onTap: () {
                          controller.setLinkedTask(task.id);
                          Navigator.pop(context);
                        },
                      ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.state, required this.controller, required this.palette});

  final FocusTimerState state;
  final FocusTimerController controller;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final hasSession = state.startedAt != null;

    if (!hasSession) {
      return FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: palette.primary,
          foregroundColor: palette.background,
          padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        ),
        onPressed: controller.start,
        icon: const Icon(Icons.play_arrow),
        label: const Text('Start', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: palette.text,
            side: BorderSide(color: palette.text.withValues(alpha: 0.3)),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          ),
          onPressed: () async {
            await controller.stop();
          },
          icon: const Icon(Icons.stop),
          label: const Text('Stop', style: TextStyle(fontSize: 16)),
        ),
        const SizedBox(width: 16),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: palette.primary,
            foregroundColor: palette.background,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          ),
          onPressed: state.isRunning ? controller.pause : controller.resume,
          icon: Icon(state.isRunning ? Icons.pause : Icons.play_arrow),
          label: Text(state.isRunning ? 'Pause' : 'Resume', style: const TextStyle(fontSize: 16)),
        ),
      ],
    );
  }
}

class _TotalsRow extends ConsumerWidget {
  const _TotalsRow({required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(totalFocusedTodayProvider);
    final week = ref.watch(totalFocusedThisWeekProvider);

    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const FocusMonthScreen()),
      ),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
        decoration: BoxDecoration(
          color: palette.surface.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: palette.primary.withValues(alpha: 0.1)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bar_chart, size: 18, color: palette.primary),
            const SizedBox(width: 8),
            Text(
              'Today: ${_short(today.value)}  ·  This week: ${_short(week.value)}',
              style: TextStyle(color: palette.text, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }

  String _short(Duration? d) {
    if (d == null) return '...';
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    return hours > 0 ? '${hours}h ${minutes}m' : '${minutes}m';
  }
}
