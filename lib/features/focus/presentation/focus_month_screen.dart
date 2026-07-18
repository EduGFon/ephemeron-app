import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/focus_metrics_providers.dart';
import 'package:ephemeron/core/widgets/app_loading_indicator.dart';

class FocusMonthScreen extends ConsumerStatefulWidget {
  const FocusMonthScreen({super.key});

  @override
  ConsumerState<FocusMonthScreen> createState() => _FocusMonthScreenState();
}

class _FocusMonthScreenState extends ConsumerState<FocusMonthScreen> {
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month, 1);

  @override
  Widget build(BuildContext context) {
    final dailyTotalsAsync = ref.watch(monthlyFocusTotalsProvider(_month));
    final monthTotalAsync = ref.watch(totalFocusedThisMonthProvider(_month));
    final yearTotalAsync = ref.watch(totalFocusedThisYearProvider(_month.year));
    final allTimeAsync = ref.watch(totalFocusedAllTimeProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: () => setState(
                () => _month = DateTime(_month.year, _month.month - 1, 1),
              ),
            ),
            Text('${_monthName(_month.month)} ${_month.year}'),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: () => setState(
                () => _month = DateTime(_month.year, _month.month + 1, 1),
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _TotalStat(
                  label: 'This month',
                  duration: monthTotalAsync.value,
                ),
                _TotalStat(
                  label: 'This year',
                  duration: yearTotalAsync.value,
                ),
                _TotalStat(
                  label: 'All time',
                  duration: allTimeAsync.value,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: dailyTotalsAsync.when(
              data: (totals) {
                final daysInMonth = DateTime(
                  _month.year,
                  _month.month + 1,
                  0,
                ).day;
                final entries = [
                  for (var day = 1; day <= daysInMonth; day++)
                    MapEntry(
                      DateTime(_month.year, _month.month, day),
                      totals[DateTime(_month.year, _month.month, day)],
                    ),
                ]
                    .where(
                      (e) => e.value != null && e.value! > Duration.zero,
                    )
                    .toList();

                if (entries.isEmpty) {
                  return Center(
                    child: Text(
                      'No focus sessions this month',
                      style: theme.textTheme.bodyMedium,
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    return ListTile(
                      title: Text(
                        '${entry.key.year}-${entry.key.month.toString().padLeft(2, '0')}-'
                        '${entry.key.day.toString().padLeft(2, '0')}',
                      ),
                      trailing: Text(_format(entry.value!)),
                    );
                  },
                );
              },
              loading: () => const Center(child: AppLoadingIndicator()),
              error: (error, _) =>
                  Center(child: Text('Could not load totals: $error')),
            ),
          ),
        ],
      ),
    );
  }

  String _format(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    return hours > 0 ? '${hours}h ${minutes}m' : '${minutes}m';
  }

  String _monthName(int month) {
    const names = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return names[month - 1];
  }
}

class _TotalStat extends StatelessWidget {
  const _TotalStat({required this.label, required this.duration});

  final String label;
  final Duration? duration;

  @override
  Widget build(BuildContext context) {
    final hours = duration?.inHours;
    final minutes = duration?.inMinutes.remainder(60);
    return Column(
      children: [
        Text(
          duration == null
              ? '...'
              : (hours! > 0 ? '${hours}h ${minutes}m' : '${minutes}m'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}
