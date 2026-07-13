import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/services.dart';

/// Thin Dart wrapper around the native MethodChannel that drives Android's
/// "promoted ongoing" (Live Update) pill notification for the focus timer.
///
/// On Android 16+ this shows a persistent chip in the status bar while the
/// timer is running — exactly what the stock Clock / Stopwatch apps show.
/// On older versions the channel still exists but `setRequestPromotedOngoing`
/// is a no-op inside MainActivity, so it just shows a normal ongoing
/// notification (same as the flutter_local_notifications fallback).
class PromotedNotificationChannel {
  static const _channel = MethodChannel('ephemeron/promoted_notification');

  static bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  /// Show (or update) the live timer pill.
  ///
  /// [whenMs] is [DateTime.now().millisecondsSinceEpoch] for a stopwatch,
  /// or [DateTime.now().add(remaining).millisecondsSinceEpoch] for a
  /// countdown. Android's Chronometer widget takes care of the ticking.
  static Future<void> show({
    required String title,
    required String body,
    required int whenMs,
    required bool isCountdown,
  }) async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod<void>('show', {
        'title': title,
        'body': body,
        'whenMs': whenMs,
        'isCountdown': isCountdown,
      });
    } on PlatformException catch (e) {
      // Non-fatal — the flutter_local_notifications fallback is still running.
      debugPrint('[PromotedNotification] show failed: ${e.message}');
    }
  }

  /// Cancel / dismiss the live timer pill.
  static Future<void> cancel() async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod<void>('cancel');
    } on PlatformException catch (e) {
      debugPrint('[PromotedNotification] cancel failed: ${e.message}');
    }
  }
}
