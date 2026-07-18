import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/routing/app_router.dart';
import 'core/settings/app_settings_provider.dart';
import 'core/settings/power_saving_manager.dart';
import 'core/settings/shared_preferences_provider.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_engine_provider.dart';

import 'features/alarms/application/alarm_action_manager_provider.dart';
import 'features/alarms/application/alarm_scheduler_provider.dart';
import 'features/auth/google/google_auth_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'features/countdown/application/countdown_providers.dart';
import 'features/habits/application/habit_providers.dart';
import 'features/sync/application/sync_service.dart';
import 'features/calendar/application/calendar_providers.dart';
import 'features/tasks/application/task_providers.dart';
import 'features/notes/application/notes_providers.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  sharedPrefs = await SharedPreferences.getInstance();
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
    // Listens to app lifecycle changes to refresh battery state
    ref.watch(powerSavingManagerProvider);
    // Initialize Google Auth — this silently restores a previous session
    // so Calendar/Tasks sync work immediately without visiting auth screen.
    ref.watch(googleAuthInitProvider);
    // Initialize sync service (kick off background periodic timer based on settings)
    ref.watch(syncServiceProvider);

    // Pre-warm primary providers so tabs load instantly on first click
    final now = DateTime.now();
    ref.read(monthEventsProvider(DateTime(now.year, now.month, 1)));
    ref.read(listsProvider);
    ref.read(allActiveTasksProvider);
    ref.read(habitsProvider);
    ref.read(countdownsProvider);
    ref.read(notesStreamProvider);
    ref.read(foldersStreamProvider);

    final palette = ref.watch(themeEngineProvider);
    final isReducedMotion = settings.shouldReduceMotion;

    return MaterialApp.router(
      title: 'Ephemeron',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.light, // We control the palette directly now
      theme: AppTheme.build(palette, reducedMotion: isReducedMotion),
      routerConfig: router,
      builder: (context, child) => child ?? const SizedBox.shrink(),
    );
  }
}
