import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/theme/theme_engine_provider.dart';
import '../../../core/theme/theme_palettes.dart';
import '../../../data/local/database.dart';
import '../application/habit_providers.dart';
import '../data/habit_repository.dart';
import '../domain/habit_metrics.dart';
import '../domain/habit_section.dart';
import 'habit_form_sheet.dart';

class HabitsScreen extends ConsumerWidget {
  const HabitsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final habitsAsync = ref.watch(habitsProvider);
    final palette = ref.watch(themeEngineProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text('Habits', style: TextStyle(color: palette.text, fontWeight: FontWeight.bold)),
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
            ).animate().fadeIn(duration: 500.ms);
          }
          final bySection = <String, List<Habit>>{};
          for (final habit in habits) {
            bySection.putIfAbsent(habit.section, () => []).add(habit);
          }
          
          int index = 0;
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
                ).animate().fadeIn(duration: 400.ms).slideX(begin: -0.1),
                for (final habit in entry.value) 
                  _HabitTile(habit: habit, palette: palette, delay: (index++ * 50).ms),
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

class _HabitTile extends ConsumerWidget {
  const _HabitTile({required this.habit, required this.palette, required this.delay});

  final Habit habit;
  final AppPalette palette;
  final Duration delay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metricsAsync = ref.watch(habitMetricsProvider(habit));
    final repo = ref.read(habitRepositoryProvider);
    final logsAsync = ref.watch(habitLogsProvider(habit.id));
    final today = DateTime.now();
    final todayNormalized = DateTime(today.year, today.month, today.day);
    final todayLog = _findTodayLog(logsAsync.value, todayNormalized);

    final isCompleted = habit.goalType == 'binary' 
        ? (todayLog?.isCompleted ?? false)
        : ((todayLog?.amount ?? 0) >= (habit.goalAmount ?? double.infinity));

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
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => showHabitFormSheet(context, existingHabit: habit),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                child: Row(
                  children: [
                    _buildActionWidget(repo, todayLog, isCompleted, context, ref),
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
                                ..._buildWeekStrip(metrics),
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
                          '${_formatAmount(todayLog?.amount ?? 0)} / ${_formatAmount(habit.goalAmount!)} ${habit.goalUnit ?? ''}',
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
    ).animate().fadeIn(duration: 400.ms, delay: delay).slideY(begin: 0.2, curve: Curves.easeOutCubic);
  }

  Widget _buildActionWidget(HabitRepository repo, HabitLog? todayLog, bool isCompleted, BuildContext context, WidgetRef ref) {
    if (habit.goalType == 'binary') {
      return GestureDetector(
        onTap: () => repo.toggleBinaryToday(habit.id),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isCompleted ? palette.primary : Colors.transparent,
            border: Border.all(
              color: isCompleted ? palette.primary : palette.text.withValues(alpha: 0.3),
              width: 2,
            ),
          ),
          child: isCompleted
              ? Icon(Icons.check, size: 18, color: palette.background)
              : null,
        ),
      );
    } else {
      return GestureDetector(
        onLongPress: () => _logAmount(context, ref, habit, todayLog),
        onTap: () => repo.quickLogToday(habit.id),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: palette.primary.withValues(alpha: 0.1),
          ),
          child: Icon(Icons.add, color: palette.primary, size: 20),
        ),
      );
    }
  }

  String _formatAmount(double amount) {
    return amount.truncateToDouble() == amount
        ? amount.toInt().toString()
        : amount.toStringAsFixed(1);
  }

  HabitLog? _findTodayLog(List<HabitLog>? logs, DateTime todayNormalized) {
    if (logs == null) return null;
    for (final log in logs) {
      if (DateTime(log.date.year, log.date.month, log.date.day) == todayNormalized) {
        return log;
      }
    }
    return null;
  }

  List<Widget> _buildWeekStrip(HabitMetrics metrics) {
    return [
      for (final status in metrics.last7Days)
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: AnimatedContainer(
            duration: 300.ms,
            width: 6,
            height: 18,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(3),
              color: switch (status) {
                HabitDayStatus.completed => palette.primary,
                HabitDayStatus.missed => Colors.redAccent.withValues(alpha: 0.6),
                HabitDayStatus.notDue => palette.text.withValues(alpha: 0.1),
                HabitDayStatus.future => Colors.transparent,
              },
            ),
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
    final controller = TextEditingController(text: todayLog?.amount.toString() ?? '');
    final result = await showDialog<double>(
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
    final goalAmount = habit.goalAmount ?? double.infinity;
    await ref.read(habitRepositoryProvider).logProgress(
      habit.id,
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.local_fire_department, size: 14, color: color)
            .animate(onPlay: (controller) => controller.repeat())
            .shimmer(duration: 2.seconds),
        const SizedBox(width: 4),
        Text('$streak', style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
      ],
    );
  }
}
