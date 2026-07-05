import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'nav_section.dart';
import '../../core/settings/shared_preferences_provider.dart'; // To get SharedPreferences instance

/// Returns the sections currently pinned to the bottom bar, in order.
/// Backed by SharedPreferences so the user's custom order persists.
class SectionsOrderNotifier extends Notifier<List<NavSection>> {
  static const _prefsKey = 'all_sections_order';

  @override
  List<NavSection> build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final saved = prefs.getStringList(_prefsKey);
    final allSections = NavSection.values;
    
    if (saved == null || saved.isEmpty) {
      return [...defaultPinnedSections, ...defaultOverflowSections];
    }
    
    // Parse saved strings back to enum values
    final parsed = saved.map((name) {
      return allSections.firstWhere(
        (e) => e.name == name,
        orElse: () => allSections.first,
      );
    }).toSet().toList();

    // If the saved list doesn't match the total length, fallback to default
    if (parsed.length != allSections.length) {
      return [...defaultPinnedSections, ...defaultOverflowSections];
    }
    return parsed;
  }

  Future<void> updateOrder(List<NavSection> newOrder) async {
    state = newOrder;
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setStringList(_prefsKey, newOrder.map((e) => e.name).toList());
  }
}

final allSectionsOrderProvider = NotifierProvider<SectionsOrderNotifier, List<NavSection>>(() {
  return SectionsOrderNotifier();
});

final pinnedSectionsProvider = Provider<List<NavSection>>((ref) {
  final all = ref.watch(allSectionsOrderProvider);
  return all.take(5).toList();
});

final overflowSectionsProvider = Provider<List<NavSection>>((ref) {
  final all = ref.watch(allSectionsOrderProvider);
  return all.skip(5).toList();
});
