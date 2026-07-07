import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/theme_engine_provider.dart';
import '../../../core/theme/theme_palettes.dart';
import '../../../data/local/database.dart';
import '../application/countdown_providers.dart';
import '../domain/countdown_status.dart';
import '../domain/countdown_type.dart';
import 'countdown_form_sheet.dart';
import 'countdown_template_picker.dart';
import 'package:ephemeron/presentation/widgets/glassmorphic_wrapper.dart';

class CountdownScreen extends ConsumerWidget {
  const CountdownScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final countdownsAsync = ref.watch(countdownsProvider);
    final palette = ref.watch(themeEngineProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text('Countdown', style: TextStyle(color: palette.text, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: countdownsAsync.when(
        data: (countdowns) {
          if (countdowns.isEmpty) {
            return Center(
              child: Text(
                'No countdowns yet',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: palette.text),
              ),
            );
          }
          final withStatus = [
            for (final countdown in countdowns)
              (
                countdown: countdown,
                status: CountdownStatus.compute(
                  targetDate: countdown.targetDate,
                  isYearly: countdown.isYearly,
                  showAge: countdown.showAge,
                ),
              ),
          ]..sort((a, b) => a.status.days.compareTo(b.status.days));

          return ListView.builder(
            padding: const EdgeInsets.only(top: 16, bottom: 120),
            itemCount: withStatus.length,
            itemBuilder: (context, index) {
              final entry = withStatus[index];
              return _CountdownTile(
                countdown: entry.countdown,
                status: entry.status,
                palette: palette,
              );
            },
          );
        },
        loading: () => Center(child: CircularProgressIndicator(color: palette.primary)),
        error: (error, _) =>
            Center(child: Text('Could not load countdowns: $error', style: TextStyle(color: palette.text))),
      ),
    );
  }
}

class _CountdownTile extends ConsumerWidget {
  const _CountdownTile({
    required this.countdown, 
    required this.status, 
    required this.palette,
  });

  final Countdown countdown;
  final CountdownStatus status;
  final AppPalette palette;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final type = CountdownType.values.byName(countdown.type);

    final daysLabel = status.days == 0
        ? 'Today'
        : status.isFuture
        ? '${status.days} day${status.days == 1 ? '' : 's'} left'
        : '${status.days} day${status.days == 1 ? '' : 's'} since';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Dismissible(
        key: ValueKey(countdown.id),
        direction: DismissDirection.endToStart,
        background: Container(
          decoration: BoxDecoration(
            color: Colors.redAccent,
            borderRadius: BorderRadius.circular(20),
          ),
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: const Icon(Icons.delete_outline, color: Colors.white),
        ),
        onDismissed: (_) =>
            ref.read(countdownRepositoryProvider).deleteCountdown(countdown.id),
        child: Container(
          decoration: BoxDecoration(
            color: palette.surface.withValues(alpha: palette.isAmoled ? 1.0 : 0.4),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: palette.text.withValues(alpha: 0.1)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: GlassmorphicWrapper(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => showCountdownFormSheet(
                    context,
                    type: type,
                    existingCountdown: countdown,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: palette.primary.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                            border: Border.all(color: palette.primary.withValues(alpha: 0.5)),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '${status.days}',
                            style: TextStyle(
                              fontSize: status.days > 999 ? 12 : 16, 
                              color: palette.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                countdown.title,
                                style: TextStyle(
                                  color: palette.text,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                status.age != null
                                    ? '$daysLabel · ${status.isFuture ? "turns" : "age"} ${status.age}'
                                    : daysLabel,
                                style: TextStyle(color: palette.text.withValues(alpha: 0.6)),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: palette.text.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            type.label, 
                            style: TextStyle(
                              color: palette.text.withValues(alpha: 0.5), 
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
