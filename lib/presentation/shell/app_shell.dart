import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/quick_add/presentation/quick_add_sheet.dart';
import '../../features/settings/presentation/settings_screen.dart';
import 'nav_section.dart';
import 'pinned_sections_provider.dart';

/// Shell wrapping every section branch. Router config (app_router.dart)
/// always defines all 7 branches so StatefulShellRoute can preserve each
/// one's state uniformly; this widget is where the "only show some of
/// them, and let the set be customized" behavior actually lives, since
/// that's a presentation concern, not a routing one.
///
/// Also hosts the single global "+" quick-add button (Step 5) — this
/// replaced separate per-screen FABs in TasksScreen and CalendarScreen,
/// matching the brainstorm's "Create button on task related sections
/// (Lists, Calendar, Matrix)" behavior: one button, shown wherever a
/// creation flow exists, not a different one bolted onto every screen.
class AppShell extends ConsumerWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  // Matches NavSection's branchIndex for all 7 sections.
  // The quick-add flow now covers all creations contextually based on the branch.
  static const _sectionsWithQuickAdd = {0, 1, 2, 3, 4, 5, 6};

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pinned = ref.watch(pinnedSectionsProvider);
    final overflow = ref.watch(overflowSectionsProvider);
    // Always shown now — it hosts Settings unconditionally, regardless
    // of whether there happen to be any overflowed nav sections.
    const hasMoreSlot = true;

    final currentPinnedIndex = pinned.indexWhere(
      (s) => s.branchIndex == navigationShell.currentIndex,
    );
    // -1 (no pinned tab matches) means the current branch is one of the
    // overflow sections, reached via the More sheet.
    final selectedIndex = currentPinnedIndex == -1
        ? pinned.length // the synthetic "More" slot
        : currentPinnedIndex;

    final showQuickAdd = _sectionsWithQuickAdd.contains(navigationShell.currentIndex);
    return Scaffold(
      body: navigationShell,
      floatingActionButton: showQuickAdd
          ? FloatingActionButton(
              onPressed: () {
                final currentSection = pinned.firstWhere(
                  (s) => s.branchIndex == navigationShell.currentIndex,
                  orElse: () => overflow.firstWhere(
                    (s) => s.branchIndex == navigationShell.currentIndex,
                  ),
                );
                showQuickAddSheet(context, currentSection: currentSection);
              },
              child: const Icon(Icons.add),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) {
          if (index < pinned.length) {
            navigationShell.goBranch(
              pinned[index].branchIndex,
              initialLocation: pinned[index].branchIndex == navigationShell.currentIndex,
            );
          } else {
            _showOverflowSheet(context, ref, overflow, navigationShell);
          }
        },
        destinations: [
          for (final section in pinned)
            NavigationDestination(
              icon: Icon(section.icon),
              selectedIcon: Icon(section.selectedIcon),
              label: section.label,
            ),
          if (hasMoreSlot)
            const NavigationDestination(
              icon: Icon(Icons.more_horiz),
              label: 'More',
            ),
        ],
      ),
    );
  }

  void _showOverflowSheet(
    BuildContext context,
    WidgetRef ref,
    List<NavSection> overflow,
    StatefulNavigationShell navigationShell,
  ) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final section in overflow)
                ListTile(
                  leading: Icon(section.icon),
                  title: Text(section.label),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    navigationShell.goBranch(section.branchIndex);
                  },
                ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.settings_outlined),
                title: const Text('Settings'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
