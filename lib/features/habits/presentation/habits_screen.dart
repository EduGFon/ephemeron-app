import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/theme_engine_provider.dart';
import '../../../core/theme/theme_palettes.dart';
import '../../../data/local/database.dart';
import '../application/habit_providers.dart';
import '../data/habit_repository.dart';
import '../domain/habit_metrics.dart';
import '../domain/habit_section.dart';
import 'habit_form_sheet.dart';
import 'package:ephemeron/presentation/widgets/glassmorphic_wrapper.dart';

class HabitsScreen extends ConsumerWidget {
  const HabitsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final habitsAsync = ref.watch(habitsProvider);
    final palette = ref.watch(themeEngineProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Habits', style: TextStyle(color: palette.text, fontWeight: FontWeight.bold)),
            _DateNavigator(palette: palette),
          ],
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: habitsAsync.when(
        data: (habits) {
          if (habits.isEmpty) {
            return Center(
              child: Text(
                'No habits yet',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: palette.text),
              ),
            );
          }
          final bySection = <String, List<Habit>>{};
          for (final habit in habits) {
            bySection.putIfAbsent(habit.section, () => []).add(habit);
          }
          
          return ListView(
            padding: const EdgeInsets.only(bottom: 120),
            children: [
              for (final entry in bySection.entries) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
                  child: Row(
                    children: [
                      Icon(HabitSection.resolve(entry.key).icon, size: 22, color: palette.primary),
                      const SizedBox(width: 12),
                      Text(
                        HabitSection.resolve(entry.key).label,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: palette.text,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                for (final habit in entry.value) 
                  _HabitTile(habit: habit, palette: palette),
              ],
            ],
          );
        },
        loading: () => Center(child: CircularProgressIndicator(color: palette.primary)),
        error: (error, _) => Center(child: Text('Could not load habits: $error', style: TextStyle(color: palette.text))),
      ),
    );
  }
}

class _DateNavigator extends ConsumerWidget {
  const _DateNavigator({required this.palette});
  final AppPalette palette;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedDate = ref.watch(habitSelectedDateProvider);
    final now = DateTime.now();
    final isToday = selectedDate.year == now.year && selectedDate.month == now.month && selectedDate.day == now.day;

    String dateText;
    if (isToday) {
      dateText = 'Today';
    } else {
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      dateText = '${months[selectedDate.month - 1]} ${selectedDate.day}';
    }

    return Container(
      decoration: BoxDecoration(
        color: palette.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(Icons.chevron_left, color: palette.text, size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: () {
              ref.read(habitSelectedDateProvider.notifier).state = selectedDate.subtract(const Duration(days: 1));
            },
          ),
          GestureDetector(
            onTap: () async {
              final date = await showDatePicker(
                context: context,
                initialDate: selectedDate,
                firstDate: DateTime(2000),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (date != null) {
                ref.read(habitSelectedDateProvider.notifier).state = date;
              }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                dateText,
                style: TextStyle(color: palette.text, fontWeight: FontWeight.w600, fontSize: 14),
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.chevron_right, color: palette.text, size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: () {
              ref.read(habitSelectedDateProvider.notifier).state = selectedDate.add(const Duration(days: 1));
            },
          ),
        ],
      ),
    );
  }
}

class _HabitTile extends ConsumerWidget {
  const _HabitTile({required this.habit, required this.palette});

  final Habit habit;
  final AppPalette palette;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metricsAsync = ref.watch(habitMetricsProvider(habit));
    final repo = ref.read(habitRepositoryProvider);
    final logsAsync = ref.watch(habitLogsProvider(habit.id));
    
    final selectedDate = ref.watch(habitSelectedDateProvider);
    final selectedDateNormalized = DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
    final selectedDateLog = _findLogForDate(logsAsync.value, selectedDateNormalized);

    final isCompleted = habit.goalType == 'binary' 
        ? (selectedDateLog?.isCompleted ?? false)
        : ((selectedDateLog?.amount ?? 0) >= (habit.goalAmount ?? double.infinity));

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: palette.surface.withValues(alpha: palette.isAmoled ? 1.0 : 0.4),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isCompleted ? palette.primary.withValues(alpha: 0.5) : palette.text.withValues(alpha: 0.1),
          width: 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: GlassmorphicWrapper(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => showHabitFormSheet(context, existingHabit: habit),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                child: Row(
                  children: [
                    _buildActionWidget(repo, selectedDateLog, isCompleted, context, ref, selectedDateNormalized),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            habit.name,
                            style: TextStyle(
                              color: palette.text,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              decoration: isCompleted ? TextDecoration.lineThrough : null,
                            ),
                          ),
                          const SizedBox(height: 6),
                          metricsAsync.when(
                            data: (metrics) => Row(
                              children: [
                                _StreakBadge(streak: metrics.currentStreak, color: palette.primary),
                                const SizedBox(width: 12),
                                ..._buildWeekStrip(metrics, ref),
                              ],
                            ),
                            loading: () => const SizedBox(height: 16),
                            error: (_, __) => const SizedBox.shrink(),
                          ),
                        ],
                      ),
                    ),
                    if (habit.goalType == 'amount' && habit.goalAmount != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: palette.text.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${_formatAmount(selectedDateLog?.amount ?? 0)} / ${_formatAmount(habit.goalAmount!)} ${habit.goalUnit ?? ''}',
                          style: TextStyle(color: palette.text.withValues(alpha: 0.7), fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionWidget(HabitRepository repo, HabitLog? selectedDateLog, bool isCompleted, BuildContext context, WidgetRef ref, DateTime selectedDate) {
    if (habit.goalType == 'binary') {
      return GestureDetector(
        onTap: () => repo.toggleBinary(habit.id, selectedDate),
        onDoubleTap: () => repo.resetLog(habit.id, selectedDate),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isCompleted ? palette.primary : Colors.transparent,
            border: Border.all(
              color: isCompleted ? palette.primary : palette.text.withValues(alpha: 0.3),
              width: 2,
            ),
          ),
          child: isCompleted
              ? Icon(Icons.check, size: 20, color: palette.background)
              : null,
        ),
      );
    } else {
      return GestureDetector(
        onLongPress: () => _logAmount(context, ref, habit, selectedDateLog, selectedDate),
        onTap: () => repo.quickLog(habit.id, selectedDate),
        onDoubleTap: () => repo.resetLog(habit.id, selectedDate),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isCompleted ? palette.primary : palette.primary.withValues(alpha: 0.1),
          ),
          child: isCompleted 
              ? Icon(Icons.check, color: palette.background, size: 20)
              : Icon(Icons.add, color: palette.primary, size: 20),
        ),
      );
    }
  }

  String _formatAmount(double amount) {
    return amount.truncateToDouble() == amount
        ? amount.toInt().toString()
        : amount.toStringAsFixed(1);
  }

  HabitLog? _findLogForDate(List<HabitLog>? logs, DateTime dateNormalized) {
    if (logs == null) return null;
    for (final log in logs) {
      if (DateTime(log.date.year, log.date.month, log.date.day) == dateNormalized) {
        return log;
      }
    }
    return null;
  }

  List<Widget> _buildWeekStrip(HabitMetrics metrics, WidgetRef ref) {
    final now = DateTime.now();
    return [
      for (int i = 0; i < metrics.last7Days.length; i++) ...[
        () {
          final status = metrics.last7Days[i];
          final day = now.subtract(Duration(days: 6 - i));
          const weekdays = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
          final isCompleted = status == HabitDayStatus.completed;
          final isMissed = status == HabitDayStatus.missed;
          
          return GestureDetector(
            onTap: () {
              ref.read(habitSelectedDateProvider.notifier).state = day;
            },
            child: Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    weekdays[day.weekday - 1],
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: palette.text.withValues(alpha: 0.4),
                    ),
                  ),
                  const SizedBox(height: 4),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: switch (status) {
                        HabitDayStatus.completed => palette.primary,
                        HabitDayStatus.missed => Colors.redAccent.withValues(alpha: 0.6),
                        HabitDayStatus.notDue => palette.text.withValues(alpha: 0.1),
                        HabitDayStatus.future => Colors.transparent,
                      },
                      border: (status == HabitDayStatus.future || status == HabitDayStatus.notDue)
                          ? Border.all(color: palette.text.withValues(alpha: 0.1))
                          : null,
                    ),
                    child: isCompleted
                        ? Icon(Icons.check, size: 8, color: palette.background)
                        : isMissed 
                            ? Icon(Icons.close, size: 8, color: palette.background)
                            : null,
                  ),
                ],
              ),
            ),
          );
        }(),
      ]
    ];
  }

  Future<void> _logAmount(
    BuildContext context,
    WidgetRef ref,
    Habit habit,
    HabitLog? selectedDateLog,
    DateTime selectedDate,
  ) async {
    final controller = TextEditingController(text: selectedDateLog?.amount.toString() ?? '');
    final result = await showDialog<double?>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: palette.surface,
        title: Text('${habit.name}${habit.goalUnit != null ? ' (${habit.goalUnit})' : ''}', style: TextStyle(color: palette.text)),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          style: TextStyle(color: palette.text),
          decoration: InputDecoration(
            labelText: 'Amount',
            suffixText: habit.goalUnit,
            labelStyle: TextStyle(color: palette.text.withValues(alpha: 0.6)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              // Passing a negative number to indicate a reset
              Navigator.pop(context, -1.0);
            },
            child: Text('Reset', style: TextStyle(color: Colors.redAccent.withValues(alpha: 0.8))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: palette.text.withValues(alpha: 0.6))),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: palette.primary, foregroundColor: palette.background),
            onPressed: () => Navigator.pop(context, double.tryParse(controller.text)),
            child: const Text('Log'),
          ),
        ],
      ),
    );
    
    if (result == null) return;
    
    final repo = ref.read(habitRepositoryProvider);
    if (result == -1.0) {
      await repo.resetLog(habit.id, selectedDate);
      return;
    }
    
    final goalAmount = habit.goalAmount ?? double.infinity;
    await repo.logProgress(
      habit.id,
      date: selectedDate,
      amount: result,
      isCompleted: result >= goalAmount,
    );
  }
}

class _StreakBadge extends StatelessWidget {
  const _StreakBadge({required this.streak, required this.color});

  final int streak;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (streak == 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.local_fire_department, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            '$streak',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
