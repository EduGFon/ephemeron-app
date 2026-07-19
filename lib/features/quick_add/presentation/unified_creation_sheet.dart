import 'package:flutter/material.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/theme_engine_provider.dart';
import '../../../core/theme/theme_palettes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../presentation/shell/nav_section.dart';
import '../../../core/settings/session_restore.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_selector/file_selector.dart';
import 'package:pasteboard/pasteboard.dart';
import '../../../presentation/notes/markdown_syntax_highlighter.dart';
import '../../../presentation/notes/smart_list_formatter.dart';
import '../../calendar/application/calendar_providers.dart';
import '../../calendar/domain/calendar_event.dart';
import '../../tasks/application/task_providers.dart';
import '../../habits/application/habit_providers.dart';
import '../../habits/domain/habit_frequency.dart';
import '../../countdown/application/countdown_providers.dart';
import '../../countdown/domain/countdown_type.dart';
import '../../notes/data/notes_repository.dart';
import '../../../data/local/database.dart';
import 'quick_add_target.dart';

import '../../../presentation/widgets/keyboard_avoid_padding.dart';
import '../../../../presentation/widgets/confirmation_dialog.dart';
import 'package:go_router/go_router.dart';
import '../../calendar/presentation/event_form_sheet.dart';
import '../../calendar/presentation/date_time_config_sheet.dart';
import '../../alarms/domain/reminder_offset.dart';
import '../../auth/google/google_auth_provider.dart';


Future<void> showUnifiedCreationSheet(BuildContext context, {NavSection? currentSection, Object? entity}) {
  final sheet = SingleChildScrollView(
    child: Material(
      color: Colors.transparent,
      child: RepaintBoundary(
        child: UnifiedCreationSheet(currentSection: currentSection, entity: entity),
      ),
    ),
  );

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    elevation: 0,
    barrierColor: Colors.black54,
    builder: (context) {
      return KeyboardAvoidPadding(
        padding: const EdgeInsets.all(12),
        child: sheet,
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
  final _descController = MarkdownSyntaxHighlighter();
  final _titleFocusNode = FocusNode();
  final _descFocusNode = FocusNode();
  bool _isExpanded = false;

  late QuickAddTarget _target;
  int _priority = 0;
  // ignore: unused_field
  String? _selectedListId;
  late DateTime _startTime;
  // ignore: unused_field
  late DateTime _endTime;
  bool _isTaskCompleted = false;
  bool _hasChanges = false;

  // Metadata state for context buttons
  bool _isStarred = false;
  DateTime? _dueDate;
  TimeOfDay? _dueTime;
  List<String> _subtasks = [];
  bool _isBusy = true;
  String? _location;
  // ignore: unused_field
  String _calendarId = 'primary';
  // ignore: unused_field
  String _attendingStatus = 'accepted';
  DateTime? _targetDate;
  bool _showAge = false;
  String _habitFrequency = 'daily';
  int _habitGoalAmount = 1;
  DateTime? _habitStartDate;
  // ignore: unused_field
  final List<int> _habitGoalDays = [1, 2, 3, 4, 5, 6, 7];
  String _habitSection = 'default';

  // Advanced Event/Task fields
  RecurrenceConfig _recurrence = const RecurrenceConfig();
  Set<ReminderOffset> _selectedOffsets = {};
  final List<String> _attendees = [];

  void _insertMarkdownAtCursor(String prefix) {
    final text = _descController.text;
    final selection = _descController.selection;
    if (selection.isValid && selection.start >= 0) {
      final newText = text.replaceRange(selection.start, selection.end, prefix);
      _descController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: selection.start + prefix.length),
      );
    } else {
      _descController.text += prefix;
    }
    _markChanged();
  }

  String _initialTitle = '';
  String _initialDesc = '';

  void _markChanged() {
    final hasRealChanges = _titleController.text != _initialTitle || _descController.text != _initialDesc;
    if (hasRealChanges != _hasChanges) {
      setState(() => _hasChanges = hasRealChanges);
    }
  }

  @override
  void initState() {
    super.initState();
    _titleController.addListener(_markChanged);
    _descController.addListener(_markChanged);
    _target = switch (widget.currentSection) {
      NavSection.calendar => QuickAddTarget.event,
      NavSection.habits => QuickAddTarget.habit,
      NavSection.tasks => QuickAddTarget.task,
      NavSection.countdown => QuickAddTarget.countdown,
      NavSection.notes => QuickAddTarget.note,
      _ => QuickAddTarget.task,
    };
    
    _loadEntity();

    SessionRestore.saveOpenMenu('quick_add');
    
    final selectedDay = ref.read(selectedDayProvider);
    final now = DateTime.now();
    _startTime = DateTime(selectedDay.year, selectedDay.month, selectedDay.day, now.hour + 1, now.minute);
    _endTime = _startTime.add(const Duration(minutes: 30));
    
    Future.delayed(const Duration(milliseconds: 250), () {
      if (mounted && widget.entity == null) {
        _titleFocusNode.requestFocus();
      }
    });

    _descFocusNode.onKeyEvent = (node, event) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.keyV &&
          (HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed)) {
        _handleManualImagePaste();
      }
      return KeyEventResult.ignored;
    };
  }

  Future<void> _handleManualImagePaste() async {
    try {
      final imageBytes = await Pasteboard.image;
      if (imageBytes != null && imageBytes.isNotEmpty) {
        final appDir = await getApplicationDocumentsDirectory();
        final fileName = 'pasted_${DateTime.now().millisecondsSinceEpoch}.png';
        final savedImage = File('${appDir.path}/$fileName');
        await savedImage.writeAsBytes(imageBytes);
        final imageMarkdown = '\n![Image|250](file://${savedImage.path})\n';
        _insertAtCursor(imageMarkdown);
      }
    } catch (_) {}
  }

  void _insertAtCursor(String textToInsert) {
    final currentText = _descController.text;
    final selection = _descController.selection;
    if (selection.baseOffset >= 0) {
      final newText = currentText.replaceRange(selection.start, selection.end, textToInsert);
      _descController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: selection.start + textToInsert.length),
      );
    } else {
      _descController.text += textToInsert;
    }
  }

  Future<void> _attachImage() async {
    const typeGroup = XTypeGroup(
      label: 'Images',
      extensions: <String>['jpg', 'jpeg', 'png', 'gif', 'webp'],
    );
    final XFile? file = await openFile(acceptedTypeGroups: <XTypeGroup>[typeGroup]);
    if (file == null) return;
    
    final appDir = await getApplicationDocumentsDirectory();
    final fileName = '${DateTime.now().millisecondsSinceEpoch}_${file.name}';
    final savedImage = await File(file.path).copy('${appDir.path}/$fileName');
    final imageMarkdown = '\n![${file.name}|250](file://${savedImage.path})\n';
    
    _insertAtCursor(imageMarkdown);
  }

  @override
  void didUpdateWidget(UnifiedCreationSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entity != widget.entity) {
      _loadEntity();
    }
  }

  void _loadEntity() {
    if (widget.entity == null) {
      _titleController.clear();
      _descController.clear();
      _priority = 0;
      _selectedListId = null;
      _isTaskCompleted = false;
      _isStarred = false;
      _dueDate = null;
      _dueTime = null;
      _subtasks = [];
      _isBusy = true;
      _location = null;
      _targetDate = null;
      _showAge = false;
      _habitFrequency = 'daily';
      _habitGoalAmount = 1;
      _habitStartDate = null;
      _habitSection = 'default';
      return;
    }

    if (widget.entity is Task) {
      final task = widget.entity as Task;
      _target = QuickAddTarget.task;
      _titleController.text = task.title;
      _descController.text = task.description ?? '';
      _priority = task.priority;
      _selectedListId = task.listId;
      _isTaskCompleted = task.completedAt != null;
      _dueDate = task.dueDate;
      _isStarred = task.priority >= 3;
    } else if (widget.entity is CalendarEvent) {
      final ev = widget.entity as CalendarEvent;
      _target = QuickAddTarget.event;
      _titleController.text = ev.title;
      _descController.text = ev.description ?? '';
      _startTime = ev.start;
      _endTime = ev.end;
      _location = ev.location;
    } else if (widget.entity is Habit) {
      final h = widget.entity as Habit;
      _target = QuickAddTarget.habit;
      _titleController.text = h.name;
    } else if (widget.entity is Countdown) {
      final c = widget.entity as Countdown;
      _target = QuickAddTarget.countdown;
      _titleController.text = c.title;
      _targetDate = c.targetDate;
    } else if (widget.entity is Note) {
      final n = widget.entity as Note;
      _target = QuickAddTarget.note;
      _titleController.text = n.title;
      _descController.text = n.content;
    }
    
    _initialTitle = _titleController.text;
    _initialDesc = _descController.text;
    _hasChanges = false;
  }

  @override
  void dispose() {
    SessionRestore.clearOpenMenu();
    _titleController.removeListener(_markChanged);
    _descController.removeListener(_markChanged);
    _titleController.dispose();
    _descController.dispose();
    _titleFocusNode.dispose();
    _descFocusNode.dispose();
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
    final screenHeight = MediaQuery.sizeOf(context).height;

    return PopScope(
      canPop: !_hasChanges,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _closeSheet();
      },
      child: TapRegion(
        onTapOutside: (event) {
          _closeSheet();
        },
        child: AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      constraints: BoxConstraints(
        maxHeight: _isExpanded ? screenHeight : screenHeight * 0.75,
      ),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: _isExpanded ? BorderRadius.zero : BorderRadius.circular(28),
      ),
      padding: EdgeInsets.fromLTRB(24, _isExpanded ? 48 : 12, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          GestureDetector(
            onVerticalDragUpdate: (details) {
              if (details.primaryDelta! < -5) {
                if (!_isExpanded) setState(() => _isExpanded = true);
              } else if (details.primaryDelta! > 5) {
                _closeSheet();
              }
            },
            child: Container(
              color: Colors.transparent, // wider hit area
              padding: const EdgeInsets.only(bottom: 12, top: 4),
              child: Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: palette.text.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),
          Flexible(
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
              _buildTopBarContext(palette),
              const SizedBox(width: 4),
              _buildMoreMenuContext(palette),
            ],
          ),
          const SizedBox(height: 12),
          if (_target == QuickAddTarget.event)
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: palette.text.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.account_circle, size: 14, color: palette.text.withValues(alpha: 0.7)),
                        const SizedBox(width: 4),
                        Text(
                          ref.watch(googleAccountProvider).value?.email ?? 'No Account',
                          style: TextStyle(fontSize: 12, color: palette.text.withValues(alpha: 0.7)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: palette.text.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.calendar_month, size: 14, color: palette.text.withValues(alpha: 0.7)),
                        const SizedBox(width: 4),
                        Text(
                          (() {
                             final asyncCals = ref.watch(googleCalendarsProvider).value ?? [];
                             final c = asyncCals.where((c) => c['id'] == _calendarId).firstOrNull ?? {'name': 'Primary'};
                             return c['name'] ?? 'Primary Calendar';
                          })(),
                          style: TextStyle(fontSize: 12, color: palette.text.withValues(alpha: 0.7)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (widget.entity is Task) _buildTaskSpecificFeatures(widget.entity as Task, palette),
          TextField(
            controller: _titleController,
            focusNode: _titleFocusNode,
            autofocus: false,
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
            focusNode: _descFocusNode,
            style: TextStyle(color: palette.text, fontSize: 14),
            maxLines: null,
            expands: false,
            inputFormatters: [SmartListFormatter()],
              contentInsertionConfiguration: ContentInsertionConfiguration(
                allowedMimeTypes: const ['image/png', 'image/jpeg', 'image/gif', 'image/webp'],
                onContentInserted: (KeyboardInsertedContent content) async {
                  if (content.data != null) {
                    final appDir = await getApplicationDocumentsDirectory();
                    String ext = 'png';
                    if (content.mimeType.contains('jpeg')) ext = 'jpg';
                    if (content.mimeType.contains('gif')) ext = 'gif';
                    final fileName = 'pasted_${DateTime.now().millisecondsSinceEpoch}.$ext';
                    final savedImage = File('${appDir.path}/$fileName');
                    await savedImage.writeAsBytes(content.data!);
                    final imageMarkdown = '\n![Image|250](file://${savedImage.path})\n';
                    _insertAtCursor(imageMarkdown);
                  }
                },
              ),
              onTap: () {
                if (_descController.handleTapAtCursor()) {
                  setState(() {});
                }
              },
              onChanged: (text) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Description',
                hintStyle: TextStyle(color: palette.text.withValues(alpha: 0.5)),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.only(bottom: 16),
              ),
            ),
            if (_isExpanded && (_target == QuickAddTarget.event || _target == QuickAddTarget.task))
              _buildAdvancedSettings(palette),
          ],
        ),
      ),
    ),
    const SizedBox(height: 16),
    Row(
      children: [
        Expanded(child: _buildBottomBarContext(palette)),
        if (widget.entity == null || _hasChanges) ...[
          const SizedBox(width: 16),
          _buildSendButton(palette),
        ],
      ],
    ),
  ],
),
      ),
    ),
    );
  }

  Widget _buildTaskSpecificFeatures(Task task, AppPalette palette) {
    String? overdueText;
    if (task.dueDate != null && !task.isCompleted) {
      final now = DateTime.now();
      if (task.dueDate!.isBefore(now)) {
        final diff = now.difference(task.dueDate!).inDays;
        overdueText = diff > 0 ? '${diff}d overdue' : 'overdue';
      }
    }
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => setState(() => _isTaskCompleted = !_isTaskCompleted),
            child: Icon(
              _isTaskCompleted ? Icons.check_box : Icons.check_box_outline_blank,
              color: _isTaskCompleted ? palette.primary : palette.text.withValues(alpha: 0.5),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          if (overdueText != null)
            Expanded(
              child: Text(
                overdueText,
                style: const TextStyle(
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

  Widget _buildIconButton(IconData icon, AppPalette palette, {required VoidCallback onPressed, Color? iconColor}) {
    return IconButton(
      icon: Icon(icon, color: iconColor ?? palette.text.withValues(alpha: 0.7), size: 20),
      onPressed: onPressed,
      style: IconButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.all(8),
      ),
    );
  }



  Future<void> _saveEntity() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;
    final desc = _descController.text.trim();

    if (_target == QuickAddTarget.task) {
      final taskDueDate = _dueDate != null && _dueTime != null
          ? DateTime(_dueDate!.year, _dueDate!.month, _dueDate!.day, _dueTime!.hour, _dueTime!.minute)
          : _dueDate;
      final effectivePriority = _isStarred ? 3 : _priority;

      if (widget.entity != null && widget.entity is Task) {
        final task = widget.entity as Task;
        await ref.read(taskRepositoryProvider).updateTask(
          task.id,
          title: title,
          description: desc,
          priority: effectivePriority,
          dueDate: taskDueDate != null ? Value(taskDueDate) : const Value.absent(),
        );
      } else {
        await ref.read(taskRepositoryProvider).createTask(
          listId: _selectedListId ?? 'inbox',
          title: title,
          description: desc,
          priority: effectivePriority,
          dueDate: taskDueDate,
        );
      }
    } else if (_target == QuickAddTarget.event) {
      if (widget.entity != null && widget.entity is CalendarEvent) {
        final ev = widget.entity as CalendarEvent;
        await ref.read(calendarRepositoryProvider).updateEvent(
          ev.copyWith(
            title: title,
            description: desc,
            start: _startTime,
            end: _endTime,
            location: _location,
            attendees: _attendees,
            recurrence: _recurrence.toRruleList(_startTime),
            reminderMinutes: _selectedOffsets.map((o) => o.beforeDue.inMinutes).toList(),
          ),
        );
      } else {
        await ref.read(calendarRepositoryProvider).createEvent(
          CalendarEvent(
            id: '',
            calendarId: _calendarId,
            title: title,
            description: desc,
            start: _startTime,
            end: _endTime,
            isAllDay: false,
            location: _location,
            attendees: _attendees,
            recurrence: _recurrence.toRruleList(_startTime),
            reminderMinutes: _selectedOffsets.map((o) => o.beforeDue.inMinutes).toList(),
          ),
        );
      }
    } else if (_target == QuickAddTarget.habit) {
      final freq = switch (_habitFrequency) {
        'weekly' => const HabitFrequency.weekly(timesPerWeek: 1),
        'monthly' => const HabitFrequency.interval(intervalDays: 30),
        _ => const HabitFrequency.daily(),
      };
      if (widget.entity != null && widget.entity is Habit) {
        final h = widget.entity as Habit;
        await ref.read(habitRepositoryProvider).updateHabit(
          h.id,
          name: title,
          frequency: freq,
        );
      } else {
        await ref.read(habitRepositoryProvider).createHabit(
          name: title,
          section: _habitSection,
          frequency: freq,
          goalType: _habitGoalAmount > 1 ? 'amount' : 'binary',
          goalAmount: _habitGoalAmount.toDouble(),
        );
      }
    } else if (_target == QuickAddTarget.countdown) {
      final targetDate = _targetDate ?? DateTime.now().add(const Duration(days: 1));
      if (widget.entity != null && widget.entity is Countdown) {
        final c = widget.entity as Countdown;
        await ref.read(countdownRepositoryProvider).updateCountdown(
          c.id,
          title: title,
          targetDate: targetDate,
        );
      } else {
        await ref.read(countdownRepositoryProvider).createCountdown(
          title: title,
          type: CountdownType.custom,
          targetDate: targetDate,
        );
      }
    } else if (_target == QuickAddTarget.note) {
      if (widget.entity != null && widget.entity is Note) {
        final n = widget.entity as Note;
        await ref.read(notesRepositoryProvider).updateNote(
          NotesCompanion(
            id: Value(n.id),
            title: Value(title),
            content: Value(desc),
            folderId: Value(n.folderId),
            updatedAt: Value(DateTime.now()),
          )
        );
      } else {
        await ref.read(notesRepositoryProvider).createNote(
          NotesCompanion.insert(
            title: title,
            content: desc,
            folderId: const Value('default'),
            createdAt: Value(DateTime.now()),
            updatedAt: Value(DateTime.now()),
          )
        );
      }
    }

    if (widget.onClose != null) {
      widget.onClose!();
    } else {
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  Future<bool> _confirmDiscard() async {
    if (!_hasChanges) return true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('You have unsaved changes. Are you sure you want to discard them?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return discard == true;
  }

  Future<void> _closeSheet() async {
    final shouldClose = await _confirmDiscard();
    if (!shouldClose) return;

    if (widget.onClose != null) {
      widget.onClose!();
    } else {
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _deleteEntity() async {
    if (widget.entity == null) return;
    final entity = widget.entity!;
    
    final confirmed = await showConfirmationDialog(
      context: context,
      ref: ref,
      title: 'Delete?',
      content: 'Are you sure you want to delete this item? This action cannot be undone.',
      confirmLabel: 'Delete',
      isDestructive: true,
    );
    if (!confirmed) return;

    if (entity is Task) {
      await ref.read(taskRepositoryProvider).softDeleteTask(entity.id);
    } else if (entity is CalendarEvent) {
      await ref.read(calendarRepositoryProvider).deleteThisAndFutureEvents(entity);
    } else if (entity is Habit) {
      await ref.read(habitRepositoryProvider).deleteHabit(entity.id);
    } else if (entity is Countdown) {
      await ref.read(countdownRepositoryProvider).deleteCountdown(entity.id);
    } else if (entity is Note) {
      await ref.read(notesRepositoryProvider).deleteNote(entity.id);
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _pickDate(BuildContext context, DateTime? initial, ValueChanged<DateTime> onPicked) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: initial ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (picked != null) {
      onPicked(picked);
      _markChanged();
    }
  }

  Future<void> _pickTime(BuildContext context, TimeOfDay? initial, ValueChanged<TimeOfDay> onPicked) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: initial ?? TimeOfDay.now(),
    );
    if (picked != null) {
      onPicked(picked);
      _markChanged();
    }
  }

  Future<void> _showLocationDialog(BuildContext context) async {
    final controller = TextEditingController(text: _location ?? '');
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Event Location'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Enter location'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              setState(() => _location = controller.text.trim());
              _markChanged();
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickEventDateAndTime(AppPalette palette) async {
    final result = await showDateTimeConfigSheet(
      context: context,
      palette: palette,
      initialStart: _startTime,
      initialEnd: _endTime,
      initialRecurrence: _recurrence,
      initialReminderOffsets: _selectedOffsets,
    );
    if (result != null) {
      setState(() {
        _startTime = result.start;
        _endTime = result.end;
        _recurrence = result.recurrence;
        _selectedOffsets = result.reminderOffsets;
      });
      _markChanged();
    }
  }

  Future<void> _showAttendeesDialog(BuildContext context) async {
    final controller = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Attendees'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      decoration: const InputDecoration(hintText: 'Email address'),
                      keyboardType: TextInputType.emailAddress,
                      onSubmitted: (val) {
                        if (val.trim().isNotEmpty && val.contains('@')) {
                          setDialogState(() {
                            _attendees.add(val.trim());
                            controller.clear();
                          });
                          setState(() {});
                          _markChanged();
                        }
                      },
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: () {
                      if (controller.text.trim().isNotEmpty && controller.text.contains('@')) {
                        setDialogState(() {
                          _attendees.add(controller.text.trim());
                          controller.clear();
                        });
                        setState(() {});
                        _markChanged();
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ListView.builder(
                shrinkWrap: true,
                itemCount: _attendees.length,
                itemBuilder: (ctx, idx) {
                  final email = _attendees[idx];
                  return ListTile(
                    dense: true,
                    title: Text(email),
                    trailing: IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        setDialogState(() => _attendees.remove(email));
                        setState(() {});
                        _markChanged();
                      },
                    ),
                  );
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
          ],
        ),
      ),
    );
  }

  Widget _buildAdvancedSettings(AppPalette palette) {
    if (_target == QuickAddTarget.event) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Divider(height: 32),
          Text('Advanced Options', style: TextStyle(color: palette.text, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          // Start/End time
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.access_time, color: palette.primary),
            title: Text('Start: ${_startTime.toString().substring(0, 16)}', style: TextStyle(color: palette.text)),
            onTap: () => _pickEventDateAndTime(palette),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.access_time, color: palette.primary),
            title: Text('End: ${_endTime.toString().substring(0, 16)}', style: TextStyle(color: palette.text)),
            onTap: () async {
              await _pickDate(context, _endTime, (d) => setState(() => _endTime = DateTime(d.year, d.month, d.day, _endTime.hour, _endTime.minute)));
              if (mounted) await _pickTime(context, TimeOfDay.fromDateTime(_endTime), (t) => setState(() => _endTime = DateTime(_endTime.year, _endTime.month, _endTime.day, t.hour, t.minute)));
            },
          ),
          // Repeat
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.repeat, color: palette.primary),
            title: Text(_recurrence.label, style: TextStyle(color: _recurrence.type == RecurrenceType.none ? palette.text.withValues(alpha: 0.5) : palette.text)),
            onTap: () async {
               // Cycle through recurrence types
               setState(() {
                 switch (_recurrence.type) {
                   case RecurrenceType.none: _recurrence = _recurrence.copyWith(type: RecurrenceType.daily); break;
                   case RecurrenceType.daily: _recurrence = _recurrence.copyWith(type: RecurrenceType.weekly); break;
                   case RecurrenceType.weekly: _recurrence = _recurrence.copyWith(type: RecurrenceType.monthly); break;
                   case RecurrenceType.monthly: _recurrence = _recurrence.copyWith(type: RecurrenceType.yearly); break;
                   case RecurrenceType.yearly: _recurrence = _recurrence.copyWith(type: RecurrenceType.none); break;
                 }
               });
               _markChanged();
            },
          ),
          // Location
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.location_on_outlined, color: palette.primary),
            title: Text(_location?.isNotEmpty == true ? _location! : 'Add location', style: TextStyle(color: palette.text)),
            onTap: () => _showLocationDialog(context),
          ),
          // Attendees
          if (_attendees.isNotEmpty)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.people_outline, color: palette.primary),
              title: Text('${_attendees.length} attendees', style: TextStyle(color: palette.text)),
              onTap: () => _showAttendeesDialog(context),
            ),
        ],
      );
    } else if (_target == QuickAddTarget.task) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Divider(height: 32),
          Text('Advanced Options', style: TextStyle(color: palette.text, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.access_time, color: palette.primary),
            title: Text(_dueDate != null ? 'Due: ${_dueDate.toString().substring(0, 10)} ${_dueTime?.format(context) ?? ""}' : 'Set due date', style: TextStyle(color: palette.text)),
            onTap: () async {
              await _pickDate(context, _dueDate, (d) => setState(() => _dueDate = d));
              if (mounted && _dueDate != null) {
                await _pickTime(context, _dueTime, (t) => setState(() => _dueTime = t));
              }
            },
          ),
        ],
      );
    }
    return const SizedBox.shrink();
  }

  Future<void> _showSubtasksDialog(BuildContext context) async {
    final controller = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Subtasks'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      decoration: const InputDecoration(hintText: 'Add a subtask'),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: () {
                      if (controller.text.trim().isNotEmpty) {
                        setDialogState(() {
                          _subtasks.add(controller.text.trim());
                          controller.clear();
                        });
                        setState(() {});
                        _markChanged();
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ..._subtasks.map(
                (st) => ListTile(
                  title: Text(st),
                  trailing: IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () {
                      setDialogState(() {
                        _subtasks.remove(st);
                      });
                      setState(() {});
                      _markChanged();
                    },
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
          ],
        ),
      ),
    );
  }

  Future<void> _duplicateEntity() async {
    final title = '${_titleController.text.trim()} (Copy)';
    final desc = _descController.text.trim();

    if (_target == QuickAddTarget.task) {
      await ref.read(taskRepositoryProvider).createTask(
        listId: _selectedListId ?? 'inbox',
        title: title,
        description: desc,
        priority: _priority,
      );
    } else if (_target == QuickAddTarget.event) {
      await ref.read(calendarRepositoryProvider).createEvent(
        CalendarEvent(
          id: '',
          title: title,
          description: desc,
          start: _startTime,
          end: _endTime,
          isAllDay: false,
        ),
      );
    } else if (_target == QuickAddTarget.habit) {
      await ref.read(habitRepositoryProvider).createHabit(
        name: title,
        section: _habitSection,
        frequency: const HabitFrequency.daily(),
        goalType: 'binary',
      );
    } else if (_target == QuickAddTarget.countdown) {
      await ref.read(countdownRepositoryProvider).createCountdown(
        title: title,
        type: CountdownType.custom,
        targetDate: _targetDate ?? DateTime.now().add(const Duration(days: 1)),
      );
    } else if (_target == QuickAddTarget.note) {
      await ref.read(notesRepositoryProvider).createNote(
        NotesCompanion.insert(
          title: title,
          content: desc,
          folderId: const Value('default'),
          createdAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ),
      );
    }
    if (mounted) Navigator.of(context).pop();
  }

  Widget _buildTopBarContext(AppPalette palette) {
    switch (_target) {
      case QuickAddTarget.note:
      case QuickAddTarget.countdown:
        return IconButton(
          icon: Icon(
            _isStarred ? Icons.star : Icons.star_border,
            color: _isStarred ? Colors.amber : palette.text.withValues(alpha: 0.6),
          ),
          onPressed: () {
            setState(() => _isStarred = !_isStarred);
            _markChanged();
          },
        );
      case QuickAddTarget.task:
        return _buildPrioritySelector(palette);
      case QuickAddTarget.event:
        return GestureDetector(
          onTap: () {
            setState(() => _isBusy = !_isBusy);
            _markChanged();
          },
          child: _buildIconWrapper(
            palette,
            Center(
              child: Text(
                _isBusy ? 'Busy' : 'Free',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: _isBusy ? Colors.redAccent : Colors.green,
                ),
              ),
            ),
          ),
        );
      case QuickAddTarget.habit:
        return IconButton(
          icon: Icon(Icons.center_focus_strong_outlined, color: palette.text.withValues(alpha: 0.6)),
          onPressed: () {},
        );
    }
  }

  Widget _buildMoreMenuContext(AppPalette palette) {
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert, color: palette.text.withValues(alpha: 0.6)),
      color: palette.surface,
      onSelected: (val) {
        if (val == 'delete') {
          _deleteEntity();
        } else if (val == 'duplicate') {
          _duplicateEntity();
        } else if (val == 'date_time') {
          _pickDate(context, _dueDate, (d) => setState(() => _dueDate = d));
        } else if (val == 'focus') {
          if (widget.entity != null) {
            context.push('/focus', extra: widget.entity);
          }
        } else if (val == 'wont_do') {
          if (widget.entity is Task) {
            ref.read(taskRepositoryProvider).softDeleteTask((widget.entity as Task).id);
            if (mounted) Navigator.of(context).pop();
          }
        }
      },
      itemBuilder: (context) {
        final items = <PopupMenuEntry<String>>[];
        if (_target == QuickAddTarget.note) {
          items.add(PopupMenuItem(value: 'date_time', child: Row(children: [Icon(Icons.access_time_rounded, color: palette.text, size: 20), const SizedBox(width: 12), Text('Date/Time', style: TextStyle(color: palette.text))])));
          items.add(PopupMenuItem(value: 'focus', child: Row(children: [Icon(Icons.center_focus_strong, color: palette.text, size: 20), const SizedBox(width: 12), Text('Focus', style: TextStyle(color: palette.text))])));
          items.add(PopupMenuItem(value: 'duplicate', child: Row(children: [Icon(Icons.copy, color: palette.text, size: 20), const SizedBox(width: 12), Text('Duplicate', style: TextStyle(color: palette.text))])));
        } else if (_target == QuickAddTarget.task) {
          items.add(PopupMenuItem(value: 'wont_do', child: Row(children: [Icon(Icons.block, color: palette.text, size: 20), const SizedBox(width: 12), Text('Won\'t Do', style: TextStyle(color: palette.text))])));
          items.add(PopupMenuItem(value: 'focus', child: Row(children: [Icon(Icons.center_focus_strong, color: palette.text, size: 20), const SizedBox(width: 12), Text('Focus', style: TextStyle(color: palette.text))])));
          items.add(PopupMenuItem(value: 'duplicate', child: Row(children: [Icon(Icons.copy, color: palette.text, size: 20), const SizedBox(width: 12), Text('Duplicate', style: TextStyle(color: palette.text))])));
        } else if (_target == QuickAddTarget.event) {
          items.add(PopupMenuItem(value: 'focus', child: Row(children: [Icon(Icons.center_focus_strong, color: palette.text, size: 20), const SizedBox(width: 12), Text('Focus', style: TextStyle(color: palette.text))])));
          items.add(PopupMenuItem(value: 'duplicate', child: Row(children: [Icon(Icons.copy, color: palette.text, size: 20), const SizedBox(width: 12), Text('Duplicate', style: TextStyle(color: palette.text))])));
        } else if (_target == QuickAddTarget.countdown) {
          items.add(PopupMenuItem(value: 'focus', child: Row(children: [Icon(Icons.center_focus_strong, color: palette.text, size: 20), const SizedBox(width: 12), Text('Focus', style: TextStyle(color: palette.text))])));
          items.add(PopupMenuItem(value: 'duplicate', child: Row(children: [Icon(Icons.copy, color: palette.text, size: 20), const SizedBox(width: 12), Text('Duplicate', style: TextStyle(color: palette.text))])));
        } else if (_target == QuickAddTarget.habit) {
          items.add(PopupMenuItem(value: 'archive', child: Row(children: [Icon(Icons.archive_outlined, color: palette.text, size: 20), const SizedBox(width: 12), Text('Archive', style: TextStyle(color: palette.text))])));
        }

        if (widget.entity != null) {
          items.add(const PopupMenuDivider());
          items.add(const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline, color: Colors.redAccent, size: 20), SizedBox(width: 12), Text('Delete', style: TextStyle(color: Colors.redAccent))])));
        }
        return items;
      },
    );
  }

  Widget _buildBottomBarContext(AppPalette palette) {
    List<Widget> children = [];
    if (_target == QuickAddTarget.note) {
      children = [
        _buildIconButton(Icons.check_box_outlined, palette, onPressed: () => _insertMarkdownAtCursor('- [ ] ')),
        const SizedBox(width: 8),
        _buildIconButton(Icons.format_list_bulleted, palette, onPressed: () => _insertMarkdownAtCursor('- ')),
        const SizedBox(width: 8),
        _buildIconButton(Icons.format_list_numbered, palette, onPressed: () => _insertMarkdownAtCursor('1. ')),
        const SizedBox(width: 8),
        _buildIconButton(Icons.attach_file, palette, onPressed: _attachImage),
        const SizedBox(width: 8),
        _buildTagSelector(palette),
      ];
    } else if (_target == QuickAddTarget.task) {
      children = [
        _buildIconButton(
          Icons.access_time_rounded,
          palette,
          onPressed: () async {
            await _pickDate(context, _dueDate, (d) => setState(() => _dueDate = d));
            if (mounted && _dueDate != null) {
              await _pickTime(context, _dueTime, (t) => setState(() => _dueTime = t));
            }
          },
        ),
        const SizedBox(width: 8),
        _buildTagSelector(palette),
        const SizedBox(width: 8),
        _buildListSelector(palette),
        const SizedBox(width: 8),
        _buildIconButton(Icons.account_tree_outlined, palette, onPressed: () => _showSubtasksDialog(context)),
        const SizedBox(width: 8),
        _buildIconButton(Icons.attach_file, palette, onPressed: _attachImage),
        const SizedBox(width: 8),
        _buildIconButton(
          _isStarred ? Icons.star : Icons.star_border,
          palette,
          onPressed: () {
            setState(() => _isStarred = !_isStarred);
            _markChanged();
          },
        ),
      ];
    } else if (_target == QuickAddTarget.event) {
      final googleCalendarsAsync = ref.watch(googleCalendarsProvider);
      final googleCalendars = googleCalendarsAsync.value ?? [{'id': 'primary', 'name': 'Primary Calendar'}];
      
      children = [
        _buildIconButton(
          Icons.access_time_rounded,
          palette,
          onPressed: () => _pickEventDateAndTime(palette),
          iconColor: (_startTime.day != DateTime.now().day || _selectedOffsets.isNotEmpty || _recurrence.type != RecurrenceType.none) ? palette.primary : null,
        ),
        const SizedBox(width: 8),
        PopupMenuButton<String>(
          icon: Icon(Icons.account_circle_outlined, color: _calendarId != 'primary' ? palette.primary : palette.text.withValues(alpha: 0.7), size: 20),
          color: palette.surface,
          onSelected: (cal) => setState(() => _calendarId = cal),
          itemBuilder: (ctx) => googleCalendars.map((c) => 
            PopupMenuItem(value: c['id'], child: Text(c['name'] ?? '', style: TextStyle(color: palette.text)))
          ).toList(),
        ),
        const SizedBox(width: 8),
        _buildIconButton(
          Icons.group_add_outlined, 
          palette, 
          onPressed: () => _showAttendeesDialog(context),
          iconColor: _attendees.isNotEmpty ? palette.primary : null,
        ),
        const SizedBox(width: 8),
        PopupMenuButton<String>(
          icon: Icon(Icons.event_available_outlined, color: palette.text.withValues(alpha: 0.7), size: 20),
          color: palette.surface,
          onSelected: (status) => setState(() => _attendingStatus = status),
          itemBuilder: (ctx) => [
            PopupMenuItem(value: 'accepted', child: Text('Yes', style: TextStyle(color: palette.text))),
            PopupMenuItem(value: 'tentative', child: Text('Maybe', style: TextStyle(color: palette.text))),
            PopupMenuItem(value: 'declined', child: Text('No', style: TextStyle(color: palette.text))),
          ],
        ),
        const SizedBox(width: 8),
        _buildIconButton(Icons.location_on_outlined, palette, onPressed: () => _showLocationDialog(context)),
      ];
    } else if (_target == QuickAddTarget.countdown) {
      children = [
        _buildIconButton(
          Icons.access_time_rounded,
          palette,
          onPressed: () => _pickDate(context, _targetDate, (d) => setState(() => _targetDate = d)),
        ),
        const SizedBox(width: 8),
        _buildIconButton(
          _showAge ? Icons.cake : Icons.cake_outlined,
          palette,
          onPressed: () {
            setState(() => _showAge = !_showAge);
            _markChanged();
          },
        ),
        const SizedBox(width: 8),
        _buildTagSelector(palette),
        const SizedBox(width: 8),
        _buildIconButton(Icons.attach_file, palette, onPressed: _attachImage),
      ];
    } else if (_target == QuickAddTarget.habit) {
      children = [
        PopupMenuButton<String>(
          icon: Icon(Icons.repeat, color: palette.text.withValues(alpha: 0.7), size: 20),
          color: palette.surface,
          onSelected: (freq) => setState(() => _habitFrequency = freq),
          itemBuilder: (ctx) => [
            PopupMenuItem(value: 'daily', child: Text('Daily', style: TextStyle(color: palette.text))),
            PopupMenuItem(value: 'weekly', child: Text('Weekly', style: TextStyle(color: palette.text))),
            PopupMenuItem(value: 'monthly', child: Text('Monthly', style: TextStyle(color: palette.text))),
          ],
        ),
        const SizedBox(width: 8),
        PopupMenuButton<int>(
          icon: Icon(Icons.flag_outlined, color: palette.text.withValues(alpha: 0.7), size: 20),
          color: palette.surface,
          onSelected: (amt) => setState(() => _habitGoalAmount = amt),
          itemBuilder: (ctx) => [1, 2, 3, 5, 10].map((amt) => PopupMenuItem(value: amt, child: Text('$amt times', style: TextStyle(color: palette.text)))).toList(),
        ),
        const SizedBox(width: 8),
        _buildIconButton(
          Icons.calendar_today,
          palette,
          onPressed: () => _pickDate(context, _habitStartDate, (d) => setState(() => _habitStartDate = d)),
        ),
        const SizedBox(width: 8),
        _buildIconButton(Icons.check_circle_outline, palette, onPressed: () {}),
        const SizedBox(width: 8),
        _buildIconButton(Icons.folder_outlined, palette, onPressed: () {}),
      ];
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: children),
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
          _saveEntity();
        },
        padding: EdgeInsets.zero,
      ),
    );
  }
}
