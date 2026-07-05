import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
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
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Focus')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              SegmentedButton<FocusMode>(
                segments: const [
                  ButtonSegment(value: FocusMode.pomodoro, label: Text('Pomodoro')),
                  ButtonSegment(value: FocusMode.stopwatch, label: Text('Stopwatch')),
                ],
                selected: {timerState.mode},
                onSelectionChanged: timerState.isRunning
                    ? null
                    : (selection) => controller.setMode(selection.first),
              ),
              const Spacer(),
              if (timerState.mode == FocusMode.pomodoro)
                Text(
                  timerState.pomodoroPhase == PomodoroPhase.work ? 'Focus' : 'Break',
                  style: theme.textTheme.titleMedium,
                ),
              const SizedBox(height: 8),
              Text(
                _formatDuration(timerState.elapsed),
                style: const TextStyle(
                  fontFamily: 'Fraunces',
                  fontSize: 64,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (timerState.mode == FocusMode.pomodoro)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'of ${_formatDuration(timerState.pomodoroTarget)}',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              const SizedBox(height: 24),
              _LinkPicker(state: timerState, controller: controller),
              const SizedBox(height: 16),
              SwitchListTile(
                title: const Text('Keep screen on'),
                value: timerState.keepScreenOn,
                onChanged: controller.setKeepScreenOn,
              ),
              const Spacer(),
              _Controls(state: timerState, controller: controller),
              const SizedBox(height: 24),
              const _TotalsRow(),
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
  const _LinkPicker({required this.state, required this.controller});

  final FocusTimerState state;
  final FocusTimerController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (state.isRunning) {
      return Text(
        state.linkedTaskId != null
            ? 'Linked to a task'
            : state.linkedHabitId != null
                ? 'Linked to a habit'
                : 'Not linked to a task or habit',
        style: Theme.of(context).textTheme.bodyMedium,
      );
    }
    return OutlinedButton.icon(
      icon: const Icon(Icons.link),
      label: Text(
        state.linkedTaskId != null || state.linkedHabitId != null ? 'Change link' : 'Link to task/habit',
      ),
      onPressed: () => _showLinkPicker(context, ref),
    );
  }

  Future<void> _showLinkPicker(BuildContext context, WidgetRef ref) async {
    final tasksAsync = ref.read(smartListProvider(SmartListType.today));
    final habitsAsync = ref.read(habitsProvider);
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: const Text('None'),
              onTap: () {
                controller.setLinkedTask(null);
                Navigator.pop(context);
              },
            ),
            if (habitsAsync.valueOrNull case final habits?)
              for (final habit in habits)
                ListTile(
                  leading: const Icon(Icons.repeat_outlined),
                  title: Text(habit.name),
                  onTap: () {
                    controller.setLinkedHabit(habit.id);
                    Navigator.pop(context);
                  },
                ),
            if (tasksAsync.valueOrNull case final tasks?)
              for (final task in tasks)
                ListTile(
                  leading: const Icon(Icons.checklist_outlined),
                  title: Text(task.title),
                  onTap: () {
                    controller.setLinkedTask(task.id);
                    Navigator.pop(context);
                  },
                ),
          ],
        ),
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.state, required this.controller});

  final FocusTimerState state;
  final FocusTimerController controller;

  @override
  Widget build(BuildContext context) {
    final hasSession = state.startedAt != null;

    if (!hasSession) {
      return FilledButton.icon(
        onPressed: controller.start,
        icon: const Icon(Icons.play_arrow),
        label: const Text('Start'),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        OutlinedButton.icon(
          onPressed: () async {
            await controller.stop();
          },
          icon: const Icon(Icons.stop),
          label: const Text('Stop'),
        ),
        const SizedBox(width: 16),
        FilledButton.icon(
          onPressed: state.isRunning ? controller.pause : controller.resume,
          icon: Icon(state.isRunning ? Icons.pause : Icons.play_arrow),
          label: Text(state.isRunning ? 'Pause' : 'Resume'),
        ),
      ],
    );
  }
}

class _TotalsRow extends ConsumerWidget {
  const _TotalsRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(totalFocusedTodayProvider);
    final week = ref.watch(totalFocusedThisWeekProvider);

    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const FocusMonthScreen()),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.bar_chart, size: 16, color: AppColors.petrol),
            const SizedBox(width: 6),
            Text(
              'Today: ${_short(today.valueOrNull)}  ·  This week: ${_short(week.valueOrNull)}',
              style: Theme.of(context).textTheme.labelSmall,
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
