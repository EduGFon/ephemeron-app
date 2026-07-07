import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Small, frequently-read app settings. Deliberately kept out of the Drift
/// database — this is the kind of data every screen touches on every
/// build (e.g. to decide whether to animate), so it lives in memory with
/// SharedPreferences as the persistence backstop, not in a SQL query path.
class AppSettings {
  const AppSettings({
    this.reducedMotion = false,
    this.powerSavingMode = false,
    this.osBatterySaverActive = false,
    this.usePillNavigation = true,
    this.calendarStartDay = 7, // Sunday by default (1=Mon..7=Sun)
    this.autoSync = true,
    this.syncIntervalMinutes = 30,
    this.alarmShortSoundPath = '/usr/share/sounds/ocean/stereo/alarm-clock-elapsed.oga',
    this.alarmLongSoundPath = '/usr/share/sounds/ocean/stereo/phone-incoming-call.oga',
    this.alarmBackground = '#005F73', // Petrol default hex color
    this.glassmorphismEnabled = false,
  });

  final bool reducedMotion;

  /// Manual user override — independent of what the OS itself reports.
  final bool powerSavingMode;

  /// Live-detected from the OS (see AppSettingsNotifier.refreshBatteryState)
  /// — never persisted, since it should reflect the device's *current*
  /// state each session, not whatever it happened to be last time the
  /// app ran.
  final bool osBatterySaverActive;

  final bool usePillNavigation;

  /// First day of the week for the Calendar view.
  /// Uses ISO weekday values: 1=Monday ... 7=Sunday.
  final int calendarStartDay;

  final bool autoSync;
  final int syncIntervalMinutes;

  final String alarmShortSoundPath;
  final String alarmLongSoundPath;
  final String alarmBackground;
  final bool glassmorphismEnabled;

  /// Effective "should we skip decorative animation" flag: the user's
  /// explicit toggle, their manual power-saving override, OR the OS
  /// actually reporting battery saver is on. Every animated widget in
  /// the app should check this, not [reducedMotion] alone.
  bool get shouldReduceMotion => reducedMotion || powerSavingMode || osBatterySaverActive;

  AppSettings copyWith({
    bool? reducedMotion,
    bool? powerSavingMode,
    bool? osBatterySaverActive,
    bool? usePillNavigation,
    int? calendarStartDay,
    bool? autoSync,
    int? syncIntervalMinutes,
    String? alarmShortSoundPath,
    String? alarmLongSoundPath,
    String? alarmBackground,
    bool? glassmorphismEnabled,
  }) {
    return AppSettings(
      reducedMotion: reducedMotion ?? this.reducedMotion,
      powerSavingMode: powerSavingMode ?? this.powerSavingMode,
      osBatterySaverActive: osBatterySaverActive ?? this.osBatterySaverActive,
      usePillNavigation: usePillNavigation ?? this.usePillNavigation,
      calendarStartDay: calendarStartDay ?? this.calendarStartDay,
      autoSync: autoSync ?? this.autoSync,
      syncIntervalMinutes: syncIntervalMinutes ?? this.syncIntervalMinutes,
      alarmShortSoundPath: alarmShortSoundPath ?? this.alarmShortSoundPath,
      alarmLongSoundPath: alarmLongSoundPath ?? this.alarmLongSoundPath,
      alarmBackground: alarmBackground ?? this.alarmBackground,
      glassmorphismEnabled: glassmorphismEnabled ?? this.glassmorphismEnabled,
    );
  }
}

class AppSettingsNotifier extends Notifier<AppSettings> {
  static const _reducedMotionKey = 'settings.reducedMotion';
  static const _powerSavingKey = 'settings.powerSavingMode';
  static const _usePillNavigationKey = 'settings.usePillNavigation';
  static const _calendarStartDayKey = 'settings.calendarStartDay';
  static const _autoSyncKey = 'settings.autoSync';
  static const _syncIntervalMinutesKey = 'settings.syncIntervalMinutes';
  static const _alarmShortSoundPathKey = 'settings.alarmShortSoundPath';
  static const _alarmLongSoundPathKey = 'settings.alarmLongSoundPath';
  static const _alarmBackgroundKey = 'settings.alarmBackground';
  static const _glassmorphismEnabledKey = 'settings.glassmorphismEnabled';
  final _battery = Battery();

  @override
  AppSettings build() {
    // Kick off async hydration; state starts at defaults until this
    // resolves, so first frame is never blocked on disk I/O.
    _hydrate();
    refreshBatteryState();
    return const AppSettings();
  }

  Future<void> _hydrate() async {
    final prefs = await SharedPreferences.getInstance();
    state = state.copyWith(
      reducedMotion: prefs.getBool(_reducedMotionKey) ?? false,
      powerSavingMode: prefs.getBool(_powerSavingKey) ?? false,
      usePillNavigation: prefs.getBool(_usePillNavigationKey) ?? true,
      calendarStartDay: prefs.getInt(_calendarStartDayKey) ?? 7,
      autoSync: prefs.getBool(_autoSyncKey) ?? true,
      syncIntervalMinutes: prefs.getInt(_syncIntervalMinutesKey) ?? 30,
      alarmShortSoundPath: prefs.getString(_alarmShortSoundPathKey) ?? '/usr/share/sounds/ocean/stereo/alarm-clock-elapsed.oga',
      alarmLongSoundPath: prefs.getString(_alarmLongSoundPathKey) ?? '/usr/share/sounds/ocean/stereo/phone-incoming-call.oga',
      alarmBackground: prefs.getString(_alarmBackgroundKey) ?? '#005F73',
      glassmorphismEnabled: prefs.getBool(_glassmorphismEnabledKey) ?? false,
    );
  }

  /// Checks the OS's actual battery-saver state. Not available on every
  /// platform (notably web) — fails silently into "not active" rather
  /// than surfacing a platform-support error to the user over what's
  /// meant to be a quiet background convenience.
  Future<void> refreshBatteryState() async {
    if (kIsWeb) return;
    try {
      final isActive = await _battery.isInBatterySaveMode;
      state = state.copyWith(osBatterySaverActive: isActive);
    } catch (_) {
      // Unsupported on this platform/device — leave at the default
      // (false) rather than treat an unknown as "active".
    }
  }

  Future<void> setReducedMotion(bool value) async {
    state = state.copyWith(reducedMotion: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_reducedMotionKey, value);
  }

  Future<void> setPowerSavingMode(bool value) async {
    state = state.copyWith(powerSavingMode: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_powerSavingKey, value);
  }

  Future<void> setUsePillNavigation(bool value) async {
    state = state.copyWith(usePillNavigation: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_usePillNavigationKey, value);
  }

  Future<void> setCalendarStartDay(int value) async {
    state = state.copyWith(calendarStartDay: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_calendarStartDayKey, value);
  }

  Future<void> setAutoSync(bool value) async {
    state = state.copyWith(autoSync: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoSyncKey, value);
  }

  Future<void> setSyncIntervalMinutes(int value) async {
    state = state.copyWith(syncIntervalMinutes: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_syncIntervalMinutesKey, value);
  }

  Future<void> setAlarmShortSoundPath(String value) async {
    state = state.copyWith(alarmShortSoundPath: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_alarmShortSoundPathKey, value);
  }

  Future<void> setAlarmLongSoundPath(String value) async {
    state = state.copyWith(alarmLongSoundPath: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_alarmLongSoundPathKey, value);
  }

  Future<void> setAlarmBackground(String value) async {
    state = state.copyWith(alarmBackground: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_alarmBackgroundKey, value);
  }

  Future<void> setGlassmorphismEnabled(bool value) async {
    state = state.copyWith(glassmorphismEnabled: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_glassmorphismEnabledKey, value);
  }
}

final appSettingsProvider =
    NotifierProvider<AppSettingsNotifier, AppSettings>(AppSettingsNotifier.new);
