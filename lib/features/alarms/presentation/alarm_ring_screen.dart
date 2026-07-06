import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/settings/app_settings_provider.dart';
import '../application/alarm_scheduler_provider.dart';
import '../domain/alarm_payload.dart';

/// Shown full-screen when a medium-preset alarm genuinely fires (device
/// locked/screen-off) — see AlarmScheduler's foreground response handler
/// for how this gets pushed. Auto-snoozes after 30 seconds of no
/// interaction, matching the brainstorm's "the full screen alarm
/// snoozes itself in 5min about 30s after start ringing" behavior.
class AlarmRingScreen extends ConsumerStatefulWidget {
  const AlarmRingScreen({required this.payload, super.key});

  final AlarmPayload payload;

  @override
  ConsumerState<AlarmRingScreen> createState() => _AlarmRingScreenState();
}

class _AlarmRingScreenState extends ConsumerState<AlarmRingScreen> {
  static const _autoSnoozeAfter = Duration(seconds: 30);

  Timer? _autoSnoozeTimer;
  bool _resolved = false;
  int _snoozeMinutes = 5; // Default snooze is 5 min

  @override
  void initState() {
    super.initState();
    _autoSnoozeTimer = Timer(_autoSnoozeAfter, _autoSnooze);
  }

  @override
  void dispose() {
    _autoSnoozeTimer?.cancel();
    super.dispose();
  }

  Color _parseColor(String hex) {
    try {
      final c = hex.replaceAll('#', '');
      return Color(int.parse('FF$c', radix: 16));
    } catch (_) {
      return AppColors.petrol;
    }
  }

  void _autoSnooze() {
    if (_resolved) return;
    _resolve(() => ref.read(alarmSchedulerProvider).snooze(widget.payload, snoozeFor: Duration(minutes: _snoozeMinutes)));
  }

  void _onSnoozePressed() {
    _resolve(() => ref.read(alarmSchedulerProvider).snooze(widget.payload, snoozeFor: Duration(minutes: _snoozeMinutes)));
  }

  void _onDonePressed() {
    _resolve(() => ref.read(alarmSchedulerProvider).markDone(widget.payload));
  }

  /// Guards against both the timer and a button tap firing (or two rapid
  /// taps) resolving this screen twice, and always cancels the pending
  /// timer once any resolution happens.
  void _resolve(Future<void> Function() action) {
    if (_resolved) return;
    _resolved = true;
    _autoSnoozeTimer?.cancel();
    action();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);
    final bgColor = _parseColor(settings.alarmBackground);

    return PopScope(
      // Swiping back shouldn't silently dismiss a ringing alarm — it
      // must be resolved via Snooze or Done, same as a real alarm clock.
      canPop: false,
      child: Scaffold(
        backgroundColor: bgColor,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.alarm, size: 64, color: AppColors.amber),
                const SizedBox(height: 16),
                Text(
                  widget.payload.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'Fraunces',
                    fontWeight: FontWeight.w600,
                    fontSize: 28,
                    color: Colors.white,
                  ),
                ),
                if (widget.payload.body.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    widget.payload.body,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 16,
                      color: Colors.white70,
                    ),
                  ),
                ],
                const SizedBox(height: 32),

                // ── Snooze Time Adjustment Row ──
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline, color: Colors.white70, size: 28),
                      onPressed: _snoozeMinutes > 1
                          ? () {
                              setState(() {
                                if (_snoozeMinutes <= 5) {
                                  _snoozeMinutes = 1;
                                } else {
                                  _snoozeMinutes = (_snoozeMinutes - 5).clamp(1, 60);
                                }
                              });
                            }
                          : null,
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$_snoozeMinutes min',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Inter',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline, color: Colors.white70, size: 28),
                      onPressed: _snoozeMinutes < 60
                          ? () {
                              setState(() {
                                if (_snoozeMinutes == 1) {
                                  _snoozeMinutes = 5;
                                } else {
                                  _snoozeMinutes = (_snoozeMinutes + 5).clamp(1, 60);
                                }
                              });
                            }
                          : null,
                    ),
                  ],
                ),
                const SizedBox(height: 32),

                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white54),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: _onSnoozePressed,
                        child: Text('Snooze ($_snoozeMinutes min)'),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.amber,
                          foregroundColor: AppColors.textLight,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: _onDonePressed,
                        child: const Text('Mark done', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  'Auto-snoozing if left untouched...',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
