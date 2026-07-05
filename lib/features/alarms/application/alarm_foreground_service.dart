import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../domain/alarm_preset.dart';

class AlarmForegroundService {
  final FlutterLocalNotificationsPlugin _plugin;
  Timer? _autoDismissTimer;

  AlarmForegroundService(this._plugin);

  /// Starts a native foreground service with an ongoing notification.
  /// Used for the "constant" alarm preset to ensure the OS doesn't kill
  /// the app while it's ringing for 10 minutes.
  Future<void> startConstantAlarm({
    required int id,
    required String title,
    required String body,
    required String payload,
  }) async {
    if (kIsWeb || !Platform.isAndroid) return;

    final android = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;

    final details = AndroidNotificationDetails(
      'constant_alarms',
      'Constant Alarms',
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.alarm,
      fullScreenIntent: true,
      additionalFlags: Int32List.fromList([4]), // FLAG_INSISTENT
      ongoing: true,
      actions: const [
        AndroidNotificationAction('snooze', 'Snooze'),
        AndroidNotificationAction('done', 'Mark done', cancelNotification: true),
      ],
    );

    try {
      await android.startForegroundService(
        1, // Must be positive for FGS
        title,
        body,
        notificationDetails: details,
        payload: payload,
      );
      
      _autoDismissTimer?.cancel();
      _autoDismissTimer = Timer(const Duration(minutes: 10), () {
        stopForegroundService();
      });
    } catch (e) {
      debugPrint('Failed to start foreground service: $e');
    }
  }

  Future<void> stopForegroundService() async {
    _autoDismissTimer?.cancel();
    if (kIsWeb || !Platform.isAndroid) return;
    final android = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.stopForegroundService();
  }
}
