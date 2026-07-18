import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:ephemeron/data/local/database.dart';
import 'package:ephemeron/features/countdown/data/countdown_repository.dart';
import 'package:ephemeron/features/countdown/domain/countdown_status.dart';
import 'package:ephemeron/features/countdown/domain/countdown_type.dart';
import 'package:ephemeron/features/alarms/data/alarm_scheduler.dart';
import 'package:ephemeron/features/alarms/domain/alarm_preset.dart';
import 'package:ephemeron/features/alarms/domain/reminder_offset.dart';

class FakeAlarmScheduler extends Fake implements AlarmScheduler {
  @override
  Future<List<int>> scheduleAlarmsForOffsets({
    required String entityId,
    required String title,
    required String body,
    required DateTime dueAt,
    required List<ReminderOffset> offsets,
    required AlarmPreset preset,
  }) async {
    return [];
  }

  @override
  Future<void> cancelByIds(List<int> ids) async {}
}

void main() {
  group('Countdown Age on Conclusion Tests', () {
    test('computes age correctly for yearly and non-yearly countdowns when showAge is true', () {
      final now = DateTime.now();

      // Non-yearly countdown concluded in the past (e.g. 5 years ago)
      final targetPast = DateTime(now.year - 5, now.month, now.day);
      final statusPast = CountdownStatus.compute(
        targetDate: targetPast,
        isYearly: false,
        showAge: true,
      );
      expect(statusPast.age, 5);
      expect(statusPast.isFuture, false);

      // Non-yearly countdown with showAge: false
      final statusPastNoAge = CountdownStatus.compute(
        targetDate: targetPast,
        isYearly: false,
        showAge: false,
      );
      expect(statusPastNoAge.age, isNull);

      // Yearly countdown (e.g. next occurrence)
      final targetYearly = DateTime(now.year - 10, now.month, now.day);
      final statusYearly = CountdownStatus.compute(
        targetDate: targetYearly,
        isYearly: true,
        showAge: true,
      );
      // It should calculate age based on target date year
      expect(statusYearly.age, isNotNull);
      expect(statusYearly.age! >= 10, isTrue);
    });

    test('saving custom countdown with showAge is preserved in repository', () async {
      final db = AppDatabase(NativeDatabase.memory());
      final repo = CountdownRepository(db, FakeAlarmScheduler());

      final cd = await repo.createCountdown(
        title: 'Launch Day',
        type: CountdownType.custom,
        targetDate: DateTime(2020, 1, 1),
        isYearly: false,
        showAge: true,
      );

      expect(cd.showAge, isTrue);

      // Verify update preserves/modifies showAge
      await repo.updateCountdown(cd.id, showAge: false);
      final updated = await (db.select(db.countdowns)..where((c) => c.id.equals(cd.id))).getSingle();
      expect(updated.showAge, isFalse);

      await db.close();
    });
  });
}
