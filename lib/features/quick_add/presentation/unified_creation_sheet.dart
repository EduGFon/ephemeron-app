import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/theme_engine_provider.dart';
import '../../tasks/presentation/task_form_sheet.dart';
import '../../calendar/presentation/event_form_sheet.dart';
import '../../habits/presentation/habit_form_sheet.dart';
import '../../countdown/presentation/countdown_form_sheet.dart';
import '../../countdown/domain/countdown_type.dart';
import '../../tasks/application/task_providers.dart';
import '../../../presentation/shell/nav_section.dart';
import 'quick_add_target.dart';

Future<void> showUnifiedCreationSheet(BuildContext context, {NavSection? currentSection}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (context, animation, secondaryAnimation) {
      return Center(
        child: SingleChildScrollView(
          child: Material(
            color: Colors.transparent,
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: UnifiedCreationSheet(currentSection: currentSection),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curve = CurvedAnimation(parent: animation, curve: Curves.easeOutBack);
      return ScaleTransition(
        scale: curve,
        child: FadeTransition(
          opacity: animation,
          child: child,
        ),
      );
    },
  );
}

class UnifiedCreationSheet extends ConsumerStatefulWidget {
  const UnifiedCreationSheet({this.currentSection, super.key});
  final NavSection? currentSection;

  @override
  ConsumerState<UnifiedCreationSheet> createState() => _UnifiedCreationSheetState();
}

class _UnifiedCreationSheetState extends ConsumerState<UnifiedCreationSheet> {
  late QuickAddTarget _target;

  @override
  void initState() {
    super.initState();
    _target = switch (widget.currentSection) {
      NavSection.calendar => QuickAddTarget.event,
      NavSection.habits => QuickAddTarget.habit,
      NavSection.tasks => QuickAddTarget.task,
      NavSection.countdown => QuickAddTarget.countdown,
      _ => QuickAddTarget.task,
    };
  }

  @override
  Widget build(BuildContext context) {
    final palette = ref.watch(themeEngineProvider);
    final listsAsync = ref.watch(listsProvider);
    final defaultListId = listsAsync.value?.firstWhere(
      (l) => l.isInbox, 
      orElse: () => listsAsync.value!.first
    ).id ?? '';

    final header = Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: SegmentedButton<QuickAddTarget>(
        segments: const [
          ButtonSegment(value: QuickAddTarget.task, label: Text('Task')),
          ButtonSegment(value: QuickAddTarget.event, label: Text('Event')),
          ButtonSegment(value: QuickAddTarget.habit, label: Text('Habit')),
          ButtonSegment(value: QuickAddTarget.countdown, label: Text('Cdwn')),
        ],
        selected: {_target},
        onSelectionChanged: (set) {
          setState(() {
            _target = set.first;
          });
        },
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return palette.primary.withValues(alpha: 0.2);
            }
            return Colors.transparent;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return palette.primary;
            }
            return palette.text.withValues(alpha: 0.7);
          }),
        ),
      ),
    );

    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      child: switch (_target) {
        QuickAddTarget.task => TaskFormSheet(listId: defaultListId, unifiedHeader: header),
        QuickAddTarget.event => EventFormSheet(unifiedHeader: header),
        QuickAddTarget.habit => HabitFormSheet(unifiedHeader: header),
        QuickAddTarget.countdown => CountdownFormSheet(type: CountdownType.custom, unifiedHeader: header),
        _ => const SizedBox.shrink(),
      },
    );
  }
}
