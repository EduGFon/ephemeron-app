import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/theme_engine_provider.dart';
import '../../../core/theme/theme_palettes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../presentation/shell/nav_section.dart';
import '../../../core/settings/session_restore.dart';
import '../../calendar/application/calendar_providers.dart';
import '../../tasks/application/task_providers.dart';
import '../../../data/local/database.dart';
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
              child: RepaintBoundary(child: UnifiedCreationSheet(currentSection: currentSection)),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curve = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
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

class UnifiedCreationSheet extends ConsumerStatefulWidget {
  const UnifiedCreationSheet({this.currentSection, this.entity, this.onClose, super.key});
  final NavSection? currentSection;
  final Object? entity;
  final VoidCallback? onClose;

  @override
  ConsumerState<UnifiedCreationSheet> createState() => _UnifiedCreationSheetState();
}

class _UnifiedCreationSheetState extends ConsumerState<UnifiedCreationSheet> {
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  final _titleFocusNode = FocusNode();

  late QuickAddTarget _target;
  int _priority = 0;
  // ignore: unused_field
  String? _selectedListId;
  late DateTime _startTime;
  // ignore: unused_field
  late DateTime _endTime;

  @override
  void initState() {
    super.initState();
    _target = switch (widget.currentSection) {
      NavSection.calendar => QuickAddTarget.event,
      NavSection.habits => QuickAddTarget.habit,
      NavSection.tasks => QuickAddTarget.task,
      NavSection.countdown => QuickAddTarget.countdown,
      NavSection.notes => QuickAddTarget.note,
      _ => QuickAddTarget.task,
    };
    
    if (widget.entity is Task) {
      final task = widget.entity as Task;
      _target = QuickAddTarget.task;
      _titleController.text = task.title;
      _descController.text = task.description ?? '';
      _priority = task.priority;
      _selectedListId = task.listId;
    }
    
    SessionRestore.saveOpenMenu('quick_add');
    
    final selectedDay = ref.read(selectedDayProvider);
    final now = DateTime.now();
    _startTime = DateTime(selectedDay.year, selectedDay.month, selectedDay.day, now.hour + 1, now.minute);
    _endTime = _startTime.add(const Duration(minutes: 30));
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _titleFocusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _titleFocusNode.dispose();
    SessionRestore.clearOpenMenu();
    super.dispose();
  }

  String _getTargetLabel(QuickAddTarget t) {
    switch (t) {
      case QuickAddTarget.event: return 'Event';
      case QuickAddTarget.task: return 'Task';
      case QuickAddTarget.habit: return 'Habit';
      case QuickAddTarget.countdown: return 'Countdown';
      case QuickAddTarget.note: return 'Note';
    }
  }

  IconData _getTargetIcon(QuickAddTarget t) {
    switch (t) {
      case QuickAddTarget.event: return Icons.calendar_today_outlined;
      case QuickAddTarget.task: return Icons.check_circle_outline;
      case QuickAddTarget.habit: return Icons.loop;
      case QuickAddTarget.countdown: return Icons.timer_outlined;
      case QuickAddTarget.note: return Icons.sticky_note_2_outlined;
    }
  }

  String get _titleHint {
    switch (_target) {
      case QuickAddTarget.event: return 'Event title';
      case QuickAddTarget.task: return 'Task title';
      case QuickAddTarget.note: return 'Note title';
      case QuickAddTarget.habit: return 'Habit name';
      case QuickAddTarget.countdown: return 'Countdown title';
    }
  }

  Color _getPriorityColor() {
    switch (_priority) {
      case 3: return AppColors.priorityHigh;
      case 2: return AppColors.priorityMedium;
      case 1: return AppColors.priorityLow;
      default: return ref.read(themeEngineProvider).text.withValues(alpha: 0.7);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = ref.watch(themeEngineProvider);

    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(28),
      ),
      padding: const EdgeInsets.all(24),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.90, // Allow filling most of the screen
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              PopupMenuButton<QuickAddTarget>(
                color: palette.surface,
                offset: const Offset(0, 30),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _getTargetLabel(_target),
                      style: TextStyle(color: palette.text, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    Icon(Icons.unfold_more, color: palette.text, size: 20),
                  ],
                ),
                onSelected: (val) => setState(() => _target = val),
                itemBuilder: (context) => QuickAddTarget.values.map((t) => 
                  PopupMenuItem(
                    value: t,
                    child: Row(
                      children: [
                        Icon(_getTargetIcon(t), color: palette.text, size: 20),
                        const SizedBox(width: 12),
                        Text(_getTargetLabel(t), style: TextStyle(color: palette.text)),
                      ],
                    ),
                  )
                ).toList(),
              ),
              const Spacer(),
              _buildPrioritySelector(palette),
              const SizedBox(width: 4),
              _buildIconButton(Icons.more_vert, palette, onPressed: () {}),
            ],
          ),
          const SizedBox(height: 12),
          if (widget.entity is Task) _buildTaskSpecificFeatures(widget.entity as Task, palette),
          TextField(
            controller: _titleController,
            focusNode: _titleFocusNode,
            autofocus: true,
            style: TextStyle(color: palette.text, fontSize: 18, fontWeight: FontWeight.w500),
            decoration: InputDecoration(
              hintText: _titleHint,
              hintStyle: TextStyle(color: palette.text.withValues(alpha: 0.5)),
              border: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.only(bottom: 8),
            ),
          ),
          TextField(
            controller: _descController,
            style: TextStyle(color: palette.text, fontSize: 14),
            maxLines: null, // Allow multiline
            decoration: InputDecoration(
              hintText: 'Description',
              hintStyle: TextStyle(color: palette.text.withValues(alpha: 0.5)),
              border: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.only(bottom: 16),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildTagSelector(palette),
              const SizedBox(width: 8),
              _buildListSelector(palette),
              const SizedBox(width: 8),
              _buildIconButton(Icons.attach_file, palette, onPressed: () {}),
              const Spacer(),
              _buildSendButton(palette),
            ],
          ),
        ],
        ),
      ),
    );
  }

  Widget _buildTaskSpecificFeatures(Task task, AppPalette palette) {
    // This replicates the image style with a checkbox and red overdue date
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        children: [
          Icon(
            task.completedAt != null ? Icons.check_box : Icons.check_box_outline_blank,
            color: task.completedAt != null ? palette.primary : palette.text.withValues(alpha: 0.5),
            size: 20,
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Jul 1, 21:15 - 21:45, 18d overdue', // Mock text matching image
              style: TextStyle(
                color: AppColors.priorityHigh, // Red color
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrioritySelector(AppPalette palette) {
    return _buildIconWrapper(
      palette,
      PopupMenuButton<int>(
        icon: Icon(Icons.flag_outlined, size: 20, color: _getPriorityColor()),
        color: palette.surface,
        padding: EdgeInsets.zero,
        offset: const Offset(0, -200),
        onSelected: (val) => setState(() => _priority = val),
        itemBuilder: (context) => [
          PopupMenuItem(
            value: 3, 
            child: Row(children: [const Icon(Icons.flag_outlined, color: AppColors.priorityHigh), const SizedBox(width: 12), Text('High Priority', style: TextStyle(color: palette.text))])
          ),
          PopupMenuItem(
            value: 2, 
            child: Row(children: [const Icon(Icons.flag_outlined, color: AppColors.priorityMedium), const SizedBox(width: 12), Text('Medium Priority', style: TextStyle(color: palette.text))])
          ),
          PopupMenuItem(
            value: 1, 
            child: Row(children: [const Icon(Icons.flag_outlined, color: AppColors.priorityLow), const SizedBox(width: 12), Text('Low Priority', style: TextStyle(color: palette.text))])
          ),
          PopupMenuItem(
            value: 0, 
            child: Row(children: [Icon(Icons.flag_outlined, color: palette.text.withValues(alpha: 0.5)), const SizedBox(width: 12), Text('No Priority', style: TextStyle(color: palette.text))])
          ),
        ],
      ),
    );
  }

  Widget _buildTagSelector(AppPalette palette) {
    final tagsAsync = ref.watch(allTagsProvider);
    final tags = tagsAsync.value ?? [];
    
    return _buildIconWrapper(
      palette,
      PopupMenuButton<String>(
        icon: Icon(Icons.local_offer_outlined, size: 20, color: palette.text.withValues(alpha: 0.7)),
        color: palette.surface,
        padding: EdgeInsets.zero,
        offset: const Offset(0, -150),
        onSelected: (tagName) {
          final currentText = _titleController.text;
          final newText = currentText.isEmpty ? '#$tagName ' : '$currentText #$tagName ';
          _titleController.value = TextEditingValue(
            text: newText,
            selection: TextSelection.collapsed(offset: newText.length),
          );
        },
        itemBuilder: (context) => tags.isEmpty 
          ? [PopupMenuItem(value: '', child: Text('No tags', style: TextStyle(color: palette.text)))]
          : tags.map((t) => 
              PopupMenuItem(
                value: t.name,
                child: Text('#${t.name}', style: TextStyle(color: palette.text)),
              )
            ).toList(),
      ),
    );
  }

  Widget _buildListSelector(AppPalette palette) {
    final listsAsync = ref.watch(listsProvider);
    final lists = listsAsync.value ?? [];
    
    return _buildIconWrapper(
      palette,
      PopupMenuButton<String>(
        icon: Icon(Icons.drive_file_move_outlined, size: 20, color: palette.text.withValues(alpha: 0.7)),
        color: palette.surface,
        padding: EdgeInsets.zero,
        offset: const Offset(0, -200),
        onSelected: (val) => setState(() => _selectedListId = val),
        itemBuilder: (context) => lists.map((l) => 
          PopupMenuItem(
            value: l.id,
            child: Row(
              children: [
                Icon(Icons.folder_outlined, color: palette.text, size: 20),
                const SizedBox(width: 12),
                Text(l.name, style: TextStyle(color: palette.text)),
              ],
            ),
          )
        ).toList(),
      ),
    );
  }

  Widget _buildIconWrapper(AppPalette palette, Widget child) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: palette.text.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }

  Widget _buildIconButton(IconData icon, AppPalette palette, {required VoidCallback onPressed}) {
    return _buildIconWrapper(
      palette,
      IconButton(
        icon: Icon(icon, size: 20),
        color: palette.text.withValues(alpha: 0.7),
        onPressed: onPressed,
        padding: EdgeInsets.zero,
      ),
    );
  }

  Widget _buildSendButton(AppPalette palette) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: palette.primary,
        shape: BoxShape.circle,
      ),
      child: IconButton(
        icon: Icon(Icons.send, color: palette.background, size: 20),
        onPressed: () {
          // Future: Parse input and save entity
          if (widget.onClose != null) {
            widget.onClose!();
          } else {
            Navigator.of(context).pop();
          }
        },
        padding: EdgeInsets.zero,
      ),
    );
  }
}
