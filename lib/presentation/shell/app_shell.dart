import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

import '../../features/quick_add/application/quick_add_provider.dart';
import '../../features/quick_add/presentation/unified_creation_sheet.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../core/settings/app_settings_provider.dart';
import '../../core/theme/theme_engine_provider.dart';
import '../../core/theme/theme_palettes.dart';
import '../../data/local/database_provider.dart';
import '../../data/local/database.dart';
import '../../features/calendar/application/calendar_providers.dart';
import '../../features/calendar/presentation/event_form_sheet.dart';
import '../../features/tasks/presentation/task_form_sheet.dart';
import '../../features/habits/presentation/habit_form_sheet.dart';
import '../../features/countdown/presentation/countdown_form_sheet.dart';
import '../../features/countdown/domain/countdown_type.dart';
import '../notes/note_form_sheet.dart';
import 'nav_section.dart';
import 'pinned_sections_provider.dart';
import 'package:ephemeron/presentation/widgets/glassmorphic_wrapper.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  static const _sectionsWithQuickAdd = {0, 1, 2, 3, 4, 6}; // Removed 5 (Focus)

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final prefs = await SharedPreferences.getInstance();
      
      // 1. Restore last screen if different from current branch
      final lastScreen = prefs.getString('settings.lastScreen');
      if (lastScreen != null) {
        final paths = ['/calendar', '/tasks', '/matrix', '/habits', '/countdown', '/focus', '/notes'];
        final targetIndex = paths.indexOf(lastScreen);
        if (targetIndex != -1 && targetIndex != widget.navigationShell.currentIndex) {
          widget.navigationShell.goBranch(targetIndex);
        }
      }

      // 2. Restore open menu
      final menu = prefs.getString('session.openMenu') ?? 'none';
      if (menu == 'none') return;
      
      // Clear it so it doesn't loop
      await prefs.setString('session.openMenu', 'none');
      
      final entityId = prefs.getString('session.openMenuEntityId') ?? '';
      final extra = prefs.getString('session.openMenuExtra') ?? '';

      if (!mounted) return;

      if (menu == 'quick_add') {
        unawaited(showUnifiedCreationSheet(context));
      } else if (menu == 'task') {
        if (entityId.isNotEmpty) {
          final db = ref.read(appDatabaseProvider);
          final task = await (db.select(db.tasks)..where((t) => t.id.equals(entityId))).getSingleOrNull();
          if (task != null && mounted) {
            unawaited(showTaskFormSheet(context, listId: extra, existingTask: task));
          }
        } else {
          unawaited(showTaskFormSheet(context, listId: extra));
        }
      } else if (menu == 'event') {
        if (entityId.isNotEmpty) {
          final repo = ref.read(calendarRepositoryProvider);
          final event = await repo.getEvent('primary', entityId);
          if (event != null && mounted) {
            unawaited(showEventFormSheet(context, initialDay: event.start, existingEvent: event));
          }
        } else {
          final day = DateTime.tryParse(extra) ?? DateTime.now();
          unawaited(showEventFormSheet(context, initialDay: day));
        }
      } else if (menu == 'habit') {
        if (entityId.isNotEmpty) {
          final db = ref.read(appDatabaseProvider);
          final habit = await (db.select(db.habits)..where((h) => h.id.equals(entityId))).getSingleOrNull();
          if (habit != null && mounted) {
            unawaited(showHabitFormSheet(context, existingHabit: habit));
          }
        } else {
          unawaited(showHabitFormSheet(context));
        }
      } else if (menu == 'countdown') {
        final type = CountdownType.values.firstWhere((t) => t.name == extra, orElse: () => CountdownType.custom);
        if (entityId.isNotEmpty) {
          final db = ref.read(appDatabaseProvider);
          final cd = await (db.select(db.countdowns)..where((c) => c.id.equals(entityId))).getSingleOrNull();
          if (cd != null && mounted) {
            unawaited(showCountdownFormSheet(context, type: type, existingCountdown: cd));
          }
        } else {
          unawaited(showCountdownFormSheet(context, type: type));
        }
      } else if (menu == 'note') {
        if (entityId.isNotEmpty) {
          final db = ref.read(appDatabaseProvider);
          final note = await (db.select(db.notes)..where((n) => n.id.equals(entityId))).getSingleOrNull();
          if (note != null && mounted) {
            _showNoteFormSheet(context, note);
          }
        } else {
          _showNoteFormSheet(context, null);
        }
      }
    });
  }

  void _showNoteFormSheet(BuildContext context, Note? existingNote) {
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (context, anim1, anim2) {
        return Center(
          child: SingleChildScrollView(
            child: Material(
              color: Colors.transparent,
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom,
                ),
                child: RepaintBoundary(child: NoteFormSheet(existingNote: existingNote)),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, anim1, anim2, child) {
        final curve = CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic);
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.0, 1.0),
            end: Offset.zero,
          ).animate(curve),
          child: child,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final pinned = ref.watch(pinnedSectionsProvider);
    final overflow = ref.watch(overflowSectionsProvider);
    final settings = ref.watch(appSettingsProvider);
    final palette = ref.watch(themeEngineProvider);

    final currentPinnedIndex = pinned.indexWhere(
      (s) => s.branchIndex == widget.navigationShell.currentIndex,
    );
    final selectedIndex = currentPinnedIndex == -1 ? pinned.length : currentPinnedIndex;
    final showQuickAdd = _sectionsWithQuickAdd.contains(widget.navigationShell.currentIndex);
    ref.listen<QuickAddData>(quickAddProvider, (prev, next) {
      if (next.state == QuickAddState.expanded && (prev == null || prev.state != QuickAddState.expanded)) {
        final currentSection = pinned.firstWhere(
          (s) => s.branchIndex == widget.navigationShell.currentIndex,
          orElse: () => overflow.firstWhere(
            (s) => s.branchIndex == widget.navigationShell.currentIndex,
          ),
        );
        showUnifiedCreationSheet(context, currentSection: currentSection, entity: next.entity).then((_) {
          if (mounted) {
            ref.read(quickAddProvider.notifier).close();
          }
        });
      }
    });

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.transparent, // Background handled by PremiumBackground
      extendBody: false, // Content is padded to fit above the bottom navigation bar
      body: widget.navigationShell,
      floatingActionButton: showQuickAdd
          ? _QuickAddPill(
              currentSection: pinned.firstWhere(
                (s) => s.branchIndex == widget.navigationShell.currentIndex,
                orElse: () => overflow.firstWhere(
                  (s) => s.branchIndex == widget.navigationShell.currentIndex,
                ),
              ),
            )
          : null,
      floatingActionButtonLocation: const _KeyboardAttachedFabLocation(),
      bottomNavigationBar: _PremiumNavigationBar(
        isPill: settings.usePillNavigation,
        pinned: pinned,
        selectedIndex: selectedIndex,
        palette: palette,
        onDestinationSelected: (index) {
          if (index < pinned.length) {
            widget.navigationShell.goBranch(
              pinned[index].branchIndex,
              initialLocation: pinned[index].branchIndex == widget.navigationShell.currentIndex,
            );
          } else {
            _showOverflowSheet(context, ref, overflow, widget.navigationShell, palette);
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
          child: GlassmorphicWrapper(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 8),
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
                    ),
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
                  ),
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
        child: GlassmorphicWrapper(
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
      );
    } else {
      return Padding(
        padding: EdgeInsets.only(bottom: bottomPadding),
        child: navBar,
      );
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

class _KeyboardAttachedFabLocation extends FloatingActionButtonLocation {
  const _KeyboardAttachedFabLocation();

  @override
  Offset getOffset(ScaffoldPrelayoutGeometry scaffoldGeometry) {
    final double fabX = (scaffoldGeometry.scaffoldSize.width - scaffoldGeometry.floatingActionButtonSize.width) / 2.0;
    final isKeyboardOpen = scaffoldGeometry.minInsets.bottom > 0;
    final double margin = isKeyboardOpen ? 0.0 : 16.0;
    final double fabY = scaffoldGeometry.contentBottom - scaffoldGeometry.floatingActionButtonSize.height - margin;
    return Offset(fabX, fabY);
  }
}

class _QuickAddPill extends ConsumerWidget {
  final NavSection currentSection;
  const _QuickAddPill({required this.currentSection});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = ref.watch(themeEngineProvider);
    final selectedDay = ref.watch(selectedDayProvider);
    
    String getPillText() {
      if (currentSection == NavSection.calendar) {
        final monthStr = [
          '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
        ][selectedDay.month];
        return 'Add on $monthStr ${selectedDay.day}';
      }
      return 'Add ${currentSection.label}';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48.0),
      child: Material(
        color: palette.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(32),
        elevation: 6,
        child: InkWell(
          borderRadius: BorderRadius.circular(32),
          onTap: () {
            showUnifiedCreationSheet(context, currentSection: currentSection);
          },
          child: Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(32),
              border: Border.all(
                color: palette.text.withValues(alpha: 0.1),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  getPillText(),
                  style: TextStyle(
                    color: palette.text.withValues(alpha: 0.8),
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Icon(
                  Icons.add,
                  color: palette.text.withValues(alpha: 0.8),
                  size: 24,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
