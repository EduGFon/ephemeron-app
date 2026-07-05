import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_settings_provider.dart';

/// Listens to app lifecycle changes and refreshes the battery save mode state
/// automatically when the app comes back to the foreground.
class PowerSavingManager extends WidgetsBindingObserver {
  PowerSavingManager(this.ref) {
    WidgetsBinding.instance.addObserver(this);
    // Initial check
    ref.read(appSettingsProvider.notifier).refreshBatteryState();
  }

  final Ref ref;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(appSettingsProvider.notifier).refreshBatteryState();
    }
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
  }
}

final powerSavingManagerProvider = Provider<PowerSavingManager>((ref) {
  final manager = PowerSavingManager(ref);
  ref.onDispose(manager.dispose);
  return manager;
});
