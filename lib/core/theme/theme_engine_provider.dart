import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../settings/shared_preferences_provider.dart';
import 'theme_palettes.dart';

class ThemeEngineNotifier extends Notifier<AppPalette> {
  static const _paletteKey = 'settings.paletteType';

  @override
  AppPalette build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final savedTypeStr = prefs.getString(_paletteKey);
    if (savedTypeStr != null) {
      try {
        final type = AppPaletteType.values.byName(savedTypeStr);
        return AppPalette.values.firstWhere((p) => p.type == type);
      } catch (_) {}
    }
    return AppPalette.obsidian; // Default premium palette
  }

  Future<void> setPalette(AppPaletteType type) async {
    state = AppPalette.values.firstWhere((p) => p.type == type);
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(_paletteKey, type.name);
  }
}

final themeEngineProvider =
    NotifierProvider<ThemeEngineNotifier, AppPalette>(ThemeEngineNotifier.new);
