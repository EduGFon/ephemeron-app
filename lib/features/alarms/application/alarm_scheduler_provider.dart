import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/alarm_scheduler.dart';
import 'alarm_foreground_service.dart';

final alarmForegroundServiceProvider = Provider<AlarmForegroundService>((ref) {
  return AlarmForegroundService(FlutterLocalNotificationsPlugin());
});

final alarmSchedulerProvider = Provider<AlarmScheduler>((ref) {
  final scheduler = AlarmScheduler();
  ref.onDispose(scheduler.dispose);
  return scheduler;
});

/// Call once at app startup (see main.dart) — separate from the plain
/// provider above so widgets can watch this to know initialization has
/// actually completed before, e.g., offering to schedule anything.
final alarmSchedulerInitProvider = FutureProvider<void>((ref) async {
  final scheduler = ref.watch(alarmSchedulerProvider);
  await scheduler.initialize();
});
