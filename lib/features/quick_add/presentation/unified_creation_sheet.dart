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

  void _markChanged() {
    if (!_hasChanges) setState(() => _hasChanges = true);
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
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
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
    } else if (widget.entity is CalendarEvent) {
      final ev = widget.entity as CalendarEvent;
      _target = QuickAddTarget.event;
      _titleController.text = ev.title;
      _descController.text = ev.description ?? '';
      _startTime = ev.start;
      _endTime = ev.end;
    } else if (widget.entity is Habit) {
      final h = widget.entity as Habit;
      _target = QuickAddTarget.habit;
      _titleController.text = h.name;
    } else if (widget.entity is Countdown) {
      final c = widget.entity as Countdown;
      _target = QuickAddTarget.countdown;
      _titleController.text = c.title;
    } else if (widget.entity is Note) {
      final n = widget.entity as Note;
      _target = QuickAddTarget.note;
      _titleController.text = n.title;
      _descController.text = n.content;
    }
    
    // Reset changes flag after initial load
    _hasChanges = false;
  }

  @override
  void dispose() {
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
    final screenHeight = MediaQuery.of(context).size.height;
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final fullScreenHeight = screenHeight - keyboardHeight;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      height: _isExpanded ? fullScreenHeight : null,
      constraints: BoxConstraints(
        maxHeight: _isExpanded ? fullScreenHeight : screenHeight * 0.5,
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
                if (_isExpanded) setState(() => _isExpanded = false);
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
          if (widget.entity is Task) _buildTaskSpecificFeatures(widget.entity as Task, palette),
          TextField(
            controller: _titleController,
            focusNode: _titleFocusNode,
            autofocus: widget.entity == null,
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

  Future<void> _saveEntity() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;
    final desc = _descController.text.trim();

    if (_target == QuickAddTarget.task) {
      if (widget.entity != null && widget.entity is Task) {
        final task = widget.entity as Task;
        await ref.read(taskRepositoryProvider).updateTask(
          task.id,
          title: title,
          description: desc,
          priority: _priority,
        );
      } else {
        await ref.read(taskRepositoryProvider).createTask(
          listId: 'inbox',
          title: title,
          description: desc,
          priority: _priority,
        );
      }
    } else if (_target == QuickAddTarget.event) {
      if (widget.entity != null && widget.entity is CalendarEvent) {
        final ev = widget.entity as CalendarEvent;
        await ref.read(calendarRepositoryProvider).updateEvent(
          ev.copyWith(
            title: title,
            description: desc,
          ),
        );
      } else {
        _startTime = DateTime.now();
        _endTime = DateTime.now().add(const Duration(hours: 1));

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _titleFocusNode.requestFocus();
          }
        });
        await ref.read(calendarRepositoryProvider).createEvent(
          CalendarEvent(
            id: '',
            title: title,
            description: desc,
            start: DateTime.now(),
            end: DateTime.now().add(const Duration(hours: 1)),
            isAllDay: false,
          ),
        );
      }
    } else if (_target == QuickAddTarget.habit) {
      if (widget.entity != null && widget.entity is Habit) {
        final h = widget.entity as Habit;
        await ref.read(habitRepositoryProvider).updateHabit(
          h.id,
          name: title,
        );
      } else {
        await ref.read(habitRepositoryProvider).createHabit(
          name: title,
          section: 'default',
          frequency: const HabitFrequency.daily(),
          goalType: 'binary',
        );
      }
    } else if (_target == QuickAddTarget.countdown) {
      if (widget.entity != null && widget.entity is Countdown) {
        final c = widget.entity as Countdown;
        await ref.read(countdownRepositoryProvider).updateCountdown(
          c.id,
          title: title,
        );
      } else {
        await ref.read(countdownRepositoryProvider).createCountdown(
          title: title,
          type: CountdownType.custom,
          targetDate: DateTime.now().add(const Duration(days: 1)),
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

  Future<void> _deleteEntity() async {
    if (widget.entity == null) return;
    final entity = widget.entity!;
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

  Widget _buildTopBarContext(AppPalette palette) {
    switch (_target) {
      case QuickAddTarget.note:
      case QuickAddTarget.countdown:
        return IconButton(icon: Icon(Icons.star_border, color: palette.text.withValues(alpha: 0.6)), onPressed: () {});
      case QuickAddTarget.task:
        return _buildPrioritySelector(palette);
      case QuickAddTarget.event:
        return _buildIconWrapper(palette, const Center(child: Text('Free', style: TextStyle(fontSize: 12))));
      case QuickAddTarget.habit:
        return IconButton(icon: Icon(Icons.center_focus_strong_outlined, color: palette.text.withValues(alpha: 0.6)), onPressed: () {});
    }
  }

  Widget _buildMoreMenuContext(AppPalette palette) {
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert, color: palette.text.withValues(alpha: 0.6)),
      color: palette.surface,
      onSelected: (val) {
        if (val == 'delete') _deleteEntity();
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
        _buildIconButton(Icons.check_box_outlined, palette, onPressed: () {}),
        const SizedBox(width: 8),
        _buildIconButton(Icons.format_list_bulleted, palette, onPressed: () {}),
        const SizedBox(width: 8),
        _buildIconButton(Icons.format_list_numbered, palette, onPressed: () {}),
        const SizedBox(width: 8),
        _buildIconButton(Icons.attach_file, palette, onPressed: _attachImage),
        const SizedBox(width: 8),
        _buildTagSelector(palette),
      ];
    } else if (_target == QuickAddTarget.task) {
      children = [
        _buildIconButton(Icons.access_time_rounded, palette, onPressed: () {}),
        const SizedBox(width: 8),
        _buildTagSelector(palette),
        const SizedBox(width: 8),
        _buildListSelector(palette),
        const SizedBox(width: 8),
        _buildIconButton(Icons.account_tree_outlined, palette, onPressed: () {}), // Subtask
        const SizedBox(width: 8),
        _buildIconButton(Icons.attach_file, palette, onPressed: _attachImage),
        const SizedBox(width: 8),
        _buildIconButton(Icons.star_border, palette, onPressed: () {}),
      ];
    } else if (_target == QuickAddTarget.event) {
      children = [
        _buildIconButton(Icons.access_time_rounded, palette, onPressed: () {}),
        const SizedBox(width: 8),
        _buildIconButton(Icons.account_circle_outlined, palette, onPressed: () {}), // Calendar/Account
        const SizedBox(width: 8),
        _buildIconButton(Icons.group_add_outlined, palette, onPressed: () {}), // People/Video
        const SizedBox(width: 8),
        _buildIconButton(Icons.event_available_outlined, palette, onPressed: () {}), // Attending options
        const SizedBox(width: 8),
        _buildIconButton(Icons.location_on_outlined, palette, onPressed: () {}),
      ];
    } else if (_target == QuickAddTarget.countdown) {
      children = [
        _buildIconButton(Icons.access_time_rounded, palette, onPressed: () {}),
        const SizedBox(width: 8),
        _buildIconButton(Icons.cake_outlined, palette, onPressed: () {}), // Toggle age
        const SizedBox(width: 8),
        _buildTagSelector(palette),
        const SizedBox(width: 8),
        _buildIconButton(Icons.attach_file, palette, onPressed: _attachImage),
      ];
    } else if (_target == QuickAddTarget.habit) {
      children = [
        _buildIconButton(Icons.repeat, palette, onPressed: () {}), // Frequency
        const SizedBox(width: 8),
        _buildIconButton(Icons.flag_outlined, palette, onPressed: () {}), // Goal amount
        const SizedBox(width: 8),
        _buildIconButton(Icons.calendar_today, palette, onPressed: () {}), // Start date
        const SizedBox(width: 8),
        _buildIconButton(Icons.check_circle_outline, palette, onPressed: () {}), // Goal days
        const SizedBox(width: 8),
        _buildIconButton(Icons.folder_outlined, palette, onPressed: () {}), // Section
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
