import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/local/database.dart';
import '../application/habit_providers.dart';
import '../domain/habit_metrics.dart';
import '../domain/habit_section.dart';
import 'habit_form_sheet.dart';

class HabitsScreen extends ConsumerWidget {
  const HabitsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final habitsAsync = ref.watch(habitsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Habits')),
      body: habitsAsync.when(
        data: (habits) {
          if (habits.isEmpty) {
            return Center(
              child: Text(
                'No habits yet',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            );
          }
          final bySection = <String, List<Habit>>{};
          for (final habit in habits) {
            bySection.putIfAbsent(habit.section, () => []).add(habit);
          }
          return ListView(
            children: [
              for (final entry in bySection.entries) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Row(
                    children: [
                      Icon(HabitSection.resolve(entry.key).icon, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        HabitSection.resolve(entry.key).label,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ],
                  ),
                ),
                for (final habit in entry.value) _HabitTile(habit: habit),
              ],
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            Center(child: Text('Could not load habits: $error')),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showHabitFormSheet(context),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _HabitTile extends ConsumerWidget {
  const _HabitTile({required this.habit});

  final Habit habit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metricsAsync = ref.watch(habitMetricsProvider(habit));
    final repo = ref.read(habitRepositoryProvider);
    final logsAsync = ref.watch(habitLogsProvider(habit.id));
    final today = DateTime.now();
    final todayNormalized = DateTime(today.year, today.month, today.day);
    final todayLog = _findTodayLog(logsAsync.valueOrNull, todayNormalized);

    return ListTile(
      leading: habit.goalType == 'binary'
          ? Checkbox(
              value: todayLog?.isCompleted ?? false,
              onChanged: (_) => repo.toggleBinaryToday(habit.id),
            )
          : GestureDetector(
              onLongPress: () => _logAmount(context, ref, habit, todayLog),
              child: IconButton(
                tooltip:
                    'Log ${_formatAmount(habit.logIncrement)} ${habit.goalUnit ?? ''} '
                    '(long-press to enter an exact amount)',
                icon: const Icon(Icons.add_circle_outline),
                onPressed: () => repo.quickLogToday(habit.id),
              ),
            ),
      title: Text(habit.name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (habit.goalType == 'amount' && habit.goalAmount != null)
            Text(
              '${_formatAmount(todayLog?.amount ?? 0)} / '
              '${_formatAmount(habit.goalAmount!)} ${habit.goalUnit ?? ''}',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          metricsAsync.when(
            data: (metrics) => Row(
              children: [
                _StreakBadge(streak: metrics.currentStreak),
                const SizedBox(width: 8),
                ..._buildWeekStrip(metrics),
              ],
            ),
            loading: () => const SizedBox(height: 16),
            error: (_, __) => const SizedBox.shrink(),
          ),
        ],
      ),
      onTap: () => showHabitFormSheet(context, existingHabit: habit),
    );
  }

  String _formatAmount(double amount) {
    return amount.truncateToDouble() == amount
        ? amount.toInt().toString()
        : amount.toStringAsFixed(1);
  }

  // dart:core has no firstOrNull — that's a package:collection extension
  // this project doesn't otherwise need, so a small manual lookup here
  // avoids pulling in a dependency for one call site.
  HabitLog? _findTodayLog(List<HabitLog>? logs, DateTime todayNormalized) {
    if (logs == null) return null;
    for (final log in logs) {
      if (DateTime(log.date.year, log.date.month, log.date.day) ==
          todayNormalized) {
        return log;
      }
    }
    return null;
  }

  List<Widget> _buildWeekStrip(HabitMetrics metrics) {
    return [
      for (final status in metrics.last7Days)
        Padding(
          padding: const EdgeInsets.only(right: 2),
          child: Icon(
            Icons.circle,
            size: 8,
            color: switch (status) {
              HabitDayStatus.completed => AppColors.priorityLow,
              HabitDayStatus.missed => AppColors.priorityHigh,
              HabitDayStatus.notDue => AppColors.priorityNone,
              HabitDayStatus.future => Colors.transparent,
            },
          ),
        ),
    ];
  }

  Future<void> _logAmount(
    BuildContext context,
    WidgetRef ref,
    Habit habit,
    HabitLog? todayLog,
  ) async {
    final controller = TextEditingController(
      text: todayLog?.amount.toString() ?? '',
    );
    final result = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          '${habit.name}${habit.goalUnit != null ? ' (${habit.goalUnit})' : ''}',
        ),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Amount',
            suffixText: habit.goalUnit,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, double.tryParse(controller.text)),
            child: const Text('Log'),
          ),
        ],
      ),
    );
    if (result == null) return;
    final goalAmount = habit.goalAmount ?? double.infinity;
    await ref
        .read(habitRepositoryProvider)
        .logProgress(
          habit.id,
          amount: result,
          isCompleted: result >= goalAmount,
        );
  }
}

class _StreakBadge extends StatelessWidget {
  const _StreakBadge({required this.streak});

  final int streak;

  @override
  Widget build(BuildContext context) {
    if (streak == 0) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.local_fire_department,
          size: 14,
          color: AppColors.amber,
        ),
        Text('$streak', style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}
