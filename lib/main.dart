import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/routing/app_router.dart';
import 'core/settings/app_settings_provider.dart';
import 'core/theme/app_theme.dart';
import 'features/alarms/application/alarm_action_manager_provider.dart';
import 'features/alarms/application/alarm_scheduler_provider.dart';
import 'features/countdown/application/countdown_providers.dart';
import 'features/habits/application/habit_providers.dart';

void main() {
  runApp(const ProviderScope(child: EphemeronApp()));
}

class EphemeronApp extends ConsumerWidget {
  const EphemeronApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final router = ref.watch(appRouterProvider);
    // Fire-and-forget: kicks off channel setup/timezone resolution at
    // startup without blocking the first frame on it. Permission prompts
    // are a separate, deliberately-not-automatic step — see
    // AlarmScheduler.requestPermissions's doc comment.
    ref.watch(alarmSchedulerInitProvider);
    // Catches up weekly/interval habit reminders whose last-computed
    // one-shot occurrence already fired — see HabitRepository
    // .refreshOneShotAlarms's doc comment for why daily habits don't
    // need this (they're genuinely OS-recurring).
    ref.watch(habitAlarmsRefreshProvider);
    // Same idea for yearly countdowns rolling forward past their date.
    ref.watch(countdownAlarmsRefreshProvider);
    // Handles notification done/snooze actions while the app is alive.
    ref.watch(alarmActionManagerProvider);

    final themeMode = switch (settings.themeMode) {
      ThemeModeOption.system => ThemeMode.system,
      ThemeModeOption.light => ThemeMode.light,
      ThemeModeOption.dark => ThemeMode.dark,
    };

    return MaterialApp.router(
      title: 'Ephemeron',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: AppTheme.light(reducedMotion: settings.shouldReduceMotion),
      darkTheme: AppTheme.dark(reducedMotion: settings.shouldReduceMotion),
      routerConfig: router,
    );
  }
}
