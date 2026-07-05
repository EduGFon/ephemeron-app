import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../features/quick_add/presentation/unified_creation_sheet.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../core/settings/app_settings_provider.dart';
import '../../core/theme/theme_engine_provider.dart';
import '../../core/theme/theme_palettes.dart';
import 'nav_section.dart';
import 'pinned_sections_provider.dart';

class AppShell extends ConsumerWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  static const _sectionsWithQuickAdd = {0, 1, 2, 3, 4, 6}; // Removed 5 (Focus)

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pinned = ref.watch(pinnedSectionsProvider);
    final overflow = ref.watch(overflowSectionsProvider);
    final settings = ref.watch(appSettingsProvider);
    final palette = ref.watch(themeEngineProvider);

    final currentPinnedIndex = pinned.indexWhere(
      (s) => s.branchIndex == navigationShell.currentIndex,
    );
    final selectedIndex = currentPinnedIndex == -1 ? pinned.length : currentPinnedIndex;
    final showQuickAdd = _sectionsWithQuickAdd.contains(navigationShell.currentIndex);

    return Scaffold(
      backgroundColor: Colors.transparent, // Background handled by PremiumBackground
      extendBody: true, // Content flows under the transparent navigation bar
      body: navigationShell,
      floatingActionButton: showQuickAdd
          ? Container(
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: palette.primary.withValues(alpha: 0.4),
                    blurRadius: 20,
                    spreadRadius: 2,
                    offset: const Offset(0, 8),
                  )
                ],
                borderRadius: BorderRadius.circular(24),
              ),
              child: FloatingActionButton(
                backgroundColor: palette.primary,
                foregroundColor: palette.background,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                onPressed: () {
                  final currentSection = pinned.firstWhere(
                    (s) => s.branchIndex == navigationShell.currentIndex,
                    orElse: () => overflow.firstWhere(
                      (s) => s.branchIndex == navigationShell.currentIndex,
                    ),
                  );
                  showUnifiedCreationSheet(context, currentSection: currentSection);
                },
                child: const Icon(Icons.add, size: 28),
              ),
            ).animate().scale(curve: Curves.easeOutBack, duration: 400.ms)
          : null,
      floatingActionButtonLocation: settings.usePillNavigation 
          ? FloatingActionButtonLocation.endFloat
          : FloatingActionButtonLocation.endContained,
      bottomNavigationBar: _PremiumNavigationBar(
        isPill: settings.usePillNavigation,
        pinned: pinned,
        selectedIndex: selectedIndex,
        palette: palette,
        onDestinationSelected: (index) {
          if (index < pinned.length) {
            navigationShell.goBranch(
              pinned[index].branchIndex,
              initialLocation: pinned[index].branchIndex == navigationShell.currentIndex,
            );
          } else {
            _showOverflowSheet(context, ref, overflow, navigationShell, palette);
          }
        },
      ),
    );
  }

  void _showOverflowSheet(
    BuildContext context,
    WidgetRef ref,
    List<NavSection> overflow,
    StatefulNavigationShell navigationShell,
    AppPalette palette,
  ) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: palette.surface.withValues(alpha: 0.8),
      barrierColor: Colors.black54,
      elevation: 0,
      builder: (sheetContext) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 12),
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: palette.text.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  for (int i = 0; i < overflow.length; i++)
                    ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: palette.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(overflow[i].icon, color: palette.primary, size: 20),
                      ),
                      title: Text(overflow[i].label, style: TextStyle(color: palette.text, fontWeight: FontWeight.w500)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        navigationShell.goBranch(overflow[i].branchIndex);
                      },
                    ).animate().fadeIn(delay: (i * 50).ms).slideX(begin: -0.1),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                    child: Divider(height: 1, color: palette.text.withValues(alpha: 0.1)),
                  ),
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: palette.text.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.settings_outlined, color: palette.text.withValues(alpha: 0.7), size: 20),
                    ),
                    title: Text('Settings', style: TextStyle(color: palette.text, fontWeight: FontWeight.w500)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const SettingsScreen()),
                      );
                    },
                  ).animate().fadeIn(delay: (overflow.length * 50).ms).slideX(begin: -0.1),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PremiumNavigationBar extends StatelessWidget {
  final bool isPill;
  final List<NavSection> pinned;
  final int selectedIndex;
  final Function(int) onDestinationSelected;
  final AppPalette palette;

  const _PremiumNavigationBar({
    required this.isPill,
    required this.pinned,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    
    Widget navBar = Container(
      height: 72,
      decoration: BoxDecoration(
        color: palette.surface.withValues(alpha: palette.isAmoled ? 1.0 : 0.6),
        borderRadius: isPill ? BorderRadius.circular(36) : BorderRadius.zero,
        border: Border.all(
          color: palette.text.withValues(alpha: palette.isAmoled ? 0.0 : 0.1),
          width: 1,
        ),
        boxShadow: isPill
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                )
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: isPill ? BorderRadius.circular(36) : BorderRadius.zero,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              for (int i = 0; i < pinned.length; i++)
                _NavItem(
                  icon: pinned[i].icon,
                  selectedIcon: pinned[i].selectedIcon,
                  label: pinned[i].label,
                  isSelected: selectedIndex == i,
                  palette: palette,
                  onTap: () => onDestinationSelected(i),
                ),
              _NavItem(
                icon: Icons.more_horiz,
                selectedIcon: Icons.more_horiz,
                label: 'More',
                isSelected: selectedIndex == pinned.length,
                palette: palette,
                onTap: () => onDestinationSelected(pinned.length),
              ),
            ],
          ),
        ),
      ),
    );

    if (isPill) {
      return Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: bottomPadding > 0 ? bottomPadding : 16,
        ),
        child: navBar,
      ).animate().slideY(begin: 1, curve: Curves.easeOutCubic, duration: 600.ms);
    } else {
      return Padding(
        padding: EdgeInsets.only(bottom: bottomPadding),
        child: navBar,
      ).animate().fadeIn(duration: 400.ms);
    }
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool isSelected;
  final AppPalette palette;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.isSelected,
    required this.palette,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSelected ? selectedIcon : icon,
              color: isSelected ? palette.primary : palette.text.withValues(alpha: 0.6),
            ).animate(target: isSelected ? 1 : 0).scale(
                  begin: const Offset(1, 1),
                  end: const Offset(1.2, 1.2),
                  curve: Curves.elasticOut,
                  duration: 500.ms,
                ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? palette.primary : palette.text.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
