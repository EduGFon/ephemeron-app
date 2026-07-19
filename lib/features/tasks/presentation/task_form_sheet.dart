import 'dart:async';
import 'dart:ui';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../../core/theme/theme_engine_provider.dart';
import '../../../core/theme/theme_palettes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/local/database.dart';
import '../../alarms/domain/alarm_preset.dart';
import '../../alarms/domain/reminder_offset.dart';
import '../../tags/presentation/tag_autocomplete_field.dart' hide allTagsProvider;
import '../../alarms/application/alarm_permissions_helper.dart';
import '../../../core/settings/session_restore.dart';
import '../application/task_providers.dart';
import '../domain/task_recurrence.dart';
import 'package:ephemeron/presentation/widgets/glassmorphic_wrapper.dart';
import '../../../../presentation/widgets/confirmation_dialog.dart';
import '../../../../presentation/widgets/recurrence_delete_dialog.dart';

Future<void> showTaskFormSheet(
  BuildContext context, {
  required String listId,
  Task? existingTask,
}) {
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
              child: RepaintBoundary(child: TaskFormSheet(listId: listId, existingTask: existingTask)),
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

class TaskFormSheet extends ConsumerStatefulWidget {
  const TaskFormSheet({required this.listId, this.existingTask, this.unifiedHeader, super.key});

  final String listId;
  final Task? existingTask;
  final Widget? unifiedHeader;

  @override
  ConsumerState<TaskFormSheet> createState() => _TaskFormSheetState();
}

class _TaskFormSheetState extends ConsumerState<TaskFormSheet> {
  late final _titleController = TextEditingController(
    text: widget.existingTask?.title,
  );
  late final _descriptionController = TextEditingController(
    text: widget.existingTask?.description,
  );

  final FocusNode _descriptionFocusNode = FocusNode();
  Timer? _descriptionTypingTimer;
  bool _descriptionPreviewMode = false;

  late int _priority = widget.existingTask?.priority ?? 0;
  DateTime? _dueDate;
  bool _dueHasTime = false;
  AlarmPreset? _alarmPreset;
  late Set<ReminderOffset> _selectedOffsets = {};
  bool _isSaving = false;

  late int _durationMinutes = widget.existingTask?.durationMinutes ?? 30;
  late TaskRecurrence _recurrence = widget.existingTask != null
      ? TaskRecurrence.decode(widget.existingTask!.recurrenceRule)
      : TaskRecurrence.none;
  late bool _isWontDo = widget.existingTask?.isWontDo ?? false;
  final TextEditingController _subtaskController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _descriptionFocusNode.addListener(() {
      if (mounted) {
        setState(() {
          _descriptionPreviewMode = !_descriptionFocusNode.hasFocus;
        });
      }
    });
    final task = widget.existingTask;
    if (task != null) {
      _dueDate = task.dueDate?.toLocal();
      _dueHasTime = task.dueHasTime;
      _alarmPreset = task.alarmPreset != null
          ? AlarmPreset.values.byName(task.alarmPreset!)
          : null;
      if (task.reminderOffsetsMinutes != null) {
        _selectedOffsets = _decodeOffsets(task.reminderOffsetsMinutes!).toSet();
      }
    } else {
      if (widget.listId == 'smart:today') {
        _dueDate = DateTime.now();
      } else if (widget.listId == 'smart:tomorrow') {
        _dueDate = DateTime.now().add(const Duration(days: 1));
      } else if (widget.listId == 'smart:next7Days') {
        _dueDate = DateTime.now();
      } else if (widget.listId.startsWith('custom_smart:')) {
        final id = widget.listId.substring(13);
        final smartLists = ref.read(customSmartListsProvider).value;
        if (smartLists != null) {
          final smartList = smartLists.firstWhere(
            (s) => s.id == id,
            orElse: () => null as dynamic,
          );
          if (smartList.minPriority != null) {
            _priority = smartList.minPriority!;
          }
          final now = DateTime.now();
          if (smartList.dateFilter == 'today') {
            _dueDate = now;
          } else if (smartList.dateFilter == 'tomorrow') {
            _dueDate = now.add(const Duration(days: 1));
          } else if (smartList.dateFilter == 'thisWeek' || smartList.dateFilter == 'next7Days') {
            _dueDate = now;
          }
          if (smartList.tagId != null) {
            final tags = ref.read(allTagsProvider).value;
            if (tags != null) {
              final tag = tags.firstWhere(
                (t) => t.id == smartList.tagId,
                orElse: () => null as dynamic,
              );
              _titleController.text = '#${tag.name} ';
            }
          }
        }
      }
    }
    SessionRestore.saveOpenMenu('task', entityId: widget.existingTask?.id, extra: widget.listId);
    _titleController.addListener(_onTitleChanged);
    _descriptionController.addListener(_onDescriptionChanged);
    _restoreDrafts();
  }

  void _onTitleChanged() {
    SessionRestore.saveDraftValue('task', widget.existingTask?.id, 'title', _titleController.text);
  }

  void _onDescriptionChanged() {
    SessionRestore.saveDraftValue('task', widget.existingTask?.id, 'description', _descriptionController.text);
  }

  void _restoreDrafts() async {
    final t = await SessionRestore.getDraftValue('task', widget.existingTask?.id, 'title');
    final d = await SessionRestore.getDraftValue('task', widget.existingTask?.id, 'description');
    final p = await SessionRestore.getDraftValue('task', widget.existingTask?.id, 'priority');
    final du = await SessionRestore.getDraftValue('task', widget.existingTask?.id, 'dueDate');
    final ht = await SessionRestore.getDraftValue('task', widget.existingTask?.id, 'dueHasTime');
    final ap = await SessionRestore.getDraftValue('task', widget.existingTask?.id, 'alarmPreset');
    if (mounted) {
      setState(() {
        if (t != null) {
          _titleController.removeListener(_onTitleChanged);
          _titleController.text = t;
          _titleController.addListener(_onTitleChanged);
        }
        if (d != null) {
          _descriptionController.removeListener(_onDescriptionChanged);
          _descriptionController.text = d;
          _descriptionController.addListener(_onDescriptionChanged);
        }
        if (p != null) _priority = int.parse(p);
        if (du != null) _dueDate = DateTime.tryParse(du);
        if (ht != null) _dueHasTime = ht == 'true';
        if (ap != null) _alarmPreset = ap == 'none' ? null : AlarmPreset.values.byName(ap);
      });
    }
  }

  @override
  void dispose() {
    SessionRestore.clearOpenMenu();
    _titleController.dispose();
    _descriptionController.dispose();
    _descriptionFocusNode.dispose();
    _descriptionTypingTimer?.cancel();
    _subtaskController.dispose();
    super.dispose();
  }

  bool get _isEditing => widget.existingTask != null;

  List<ReminderOffset> _decodeOffsets(String raw) {
    if (raw.isEmpty) return [];
    try {
      return raw.split(',').map((s) => ReminderOffset.fromMinutes(int.parse(s))).toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = ref.watch(themeEngineProvider);
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      constraints: const BoxConstraints(maxWidth: 580),
      decoration: BoxDecoration(
        color: palette.surface.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: palette.text.withValues(alpha: 0.1), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 40,
            offset: const Offset(0, 20),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: GlassmorphicWrapper(
          filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.unifiedHeader != null) widget.unifiedHeader!,
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: TagAutocompleteField(
                        controller: _titleController,
                        autofocus: !_isEditing,
                        onChanged: (_) => setState(() {}),
                        style: TextStyle(color: palette.text, fontSize: 22, fontWeight: FontWeight.bold),
                        decoration: InputDecoration(
                          hintText: 'Task Title',
                          hintStyle: TextStyle(color: palette.text.withValues(alpha: 0.3), fontSize: 22, fontWeight: FontWeight.bold),
                          border: InputBorder.none,
                          enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: palette.text.withValues(alpha: 0.15))),
                          focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: palette.primary, width: 2)),
                          contentPadding: const EdgeInsets.symmetric(vertical: 6),
                        ),
                        textCapitalization: TextCapitalization.sentences,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (_isEditing) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        icon: Icon(Icons.delete_outline, color: Colors.redAccent.withValues(alpha: 0.8)),
                        onPressed: () async {
                          final recurrence = TaskRecurrence.decode(widget.existingTask?.recurrenceRule);
                          if (recurrence.isRecurring) {
                            final choice = await showRecurrenceDeleteDialog(
                              context: context,
                              ref: ref,
                              title: 'Delete Recurring Task?',
                            );
                            if (choice != null && mounted) {
                              final navigator = Navigator.of(context); // ignore: use_build_context_synchronously
                              if (choice == RecurrenceDeleteType.onlyThis) {
                                final nextDue = recurrence.nextOccurrence(widget.existingTask!.dueDate!);
                                if (nextDue != null) {
                                  await ref.read(taskRepositoryProvider).updateTask(
                                    widget.existingTask!.id,
                                    dueDate: Value(nextDue),
                                  );
                                }
                              } else {
                                await ref.read(taskRepositoryProvider).softDeleteTask(widget.existingTask!.id);
                              }
                              await SessionRestore.clearDraftValues('task', widget.existingTask?.id);
                              navigator.pop();
                            }
                          } else {
                            final confirmed = await showConfirmationDialog(
                              context: context,
                              ref: ref,
                              title: 'Delete task?',
                              content: 'Are you sure you want to delete this task? It will be moved to Trash.',
                              confirmLabel: 'Delete',
                              isDestructive: true,
                            );
                            if (confirmed && mounted) {
                              final navigator = Navigator.of(context); // ignore: use_build_context_synchronously
                              await ref.read(taskRepositoryProvider).softDeleteTask(widget.existingTask!.id);
                              await SessionRestore.clearDraftValues('task', widget.existingTask?.id);
                              navigator.pop();
                            }
                          }
                        },
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 16),

                // Description field with Markdown Preview
                if (_descriptionPreviewMode)
                  Container(
                    constraints: const BoxConstraints(maxHeight: 120),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: GestureDetector(
                        onTap: () {
                          setState(() => _descriptionPreviewMode = false);
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            _descriptionFocusNode.requestFocus();
                          });
                        },
                        child: _descriptionController.text.trim().isEmpty
                            ? Text(
                                'Add description (supports markdown)...',
                                style: TextStyle(color: palette.text.withValues(alpha: 0.3), fontStyle: FontStyle.italic, fontSize: 14),
                              )
                            : MarkdownBody(
                                data: _descriptionController.text,
                                softLineBreak: true,
                                styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                                  p: TextStyle(color: palette.text, fontSize: 14),
                                ),
                              ),
                      ),
                    ),
                  )
                else
                  TextField(
                    controller: _descriptionController,
                    focusNode: _descriptionFocusNode,
                    style: TextStyle(color: palette.text),
                    onChanged: (text) {
                      _descriptionTypingTimer?.cancel();
                      _descriptionTypingTimer = Timer(const Duration(seconds: 1), () {
                        if (mounted && _descriptionFocusNode.hasFocus) {
                          _descriptionFocusNode.unfocus();
                          setState(() => _descriptionPreviewMode = true);
                        }
                      });
                      setState(() {});
                    },
                    decoration: InputDecoration(
                      labelText: 'Description (optional)',
                      labelStyle: TextStyle(color: palette.text.withValues(alpha: 0.6)),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: palette.text.withValues(alpha: 0.2)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: palette.primary, width: 2),
                      ),
                    ),
                    minLines: 1,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                  ),
                const SizedBox(height: 4),
                Text(
                  '✨ Supports Markdown formatting.',
                  style: TextStyle(color: palette.text.withValues(alpha: 0.45), fontSize: 10),
                ),
                const SizedBox(height: 12),

                // ── Icon Action Bar ──
                Row(
                  children: [
                    // Time/Duration Selector
                    IconButton(
                      icon: Icon(
                        Icons.access_time_rounded,
                        color: _dueDate != null ? palette.primary : palette.text.withValues(alpha: 0.6),
                      ),
                      tooltip: 'Date, Time & Alarm',
                      onPressed: () => _showDateTimeAlarmDialog(context, palette),
                    ),
                    // Priority flag dropdown
                    PopupMenuButton<int>(
                      icon: Icon(
                        Icons.flag_rounded,
                        color: switch (_priority) {
                          3 => AppColors.priorityHigh,
                          2 => AppColors.priorityMedium,
                          1 => AppColors.priorityLow,
                          _ => palette.text.withValues(alpha: 0.6),
                        },
                      ),
                      tooltip: 'Set Priority',
                      onSelected: (val) {
                        setState(() => _priority = val);
                        SessionRestore.saveDraftValue('task', widget.existingTask?.id, 'priority', val.toString());
                      },
                      itemBuilder: (ctx) => [
                        PopupMenuItem(value: 3, child: Row(children: [const Icon(Icons.flag_rounded, color: AppColors.priorityHigh), const SizedBox(width: 8), Text('High Priority', style: TextStyle(color: palette.text))])),
                        PopupMenuItem(value: 2, child: Row(children: [const Icon(Icons.flag_rounded, color: AppColors.priorityMedium), const SizedBox(width: 8), Text('Medium Priority', style: TextStyle(color: palette.text))])),
                        PopupMenuItem(value: 1, child: Row(children: [const Icon(Icons.flag_rounded, color: AppColors.priorityLow), const SizedBox(width: 8), Text('Low Priority', style: TextStyle(color: palette.text))])),
                        PopupMenuItem(value: 0, child: Row(children: [Icon(Icons.flag_rounded, color: palette.text.withValues(alpha: 0.4)), const SizedBox(width: 8), Text('No Priority', style: TextStyle(color: palette.text))])),
                      ],
                    ),
                    // Tag selection button
                    IconButton(
                      icon: Icon(Icons.tag_rounded, color: palette.text.withValues(alpha: 0.6)),
                      tooltip: 'Insert hashtag',
                      onPressed: () => _onTagIconPressed(context, palette),
                    ),
                    // List selection button
                    IconButton(
                      icon: Icon(Icons.list_alt_rounded, color: palette.text.withValues(alpha: 0.6)),
                      tooltip: 'Insert list token',
                      onPressed: () => _onListIconPressed(context, palette),
                    ),
                    IconButton(
                      icon: Icon(
                        _isWontDo ? Icons.block : Icons.block_flipped,
                        color: _isWontDo ? Colors.redAccent : palette.text.withValues(alpha: 0.6),
                      ),
                      tooltip: "Toggle 'Won't Do'",
                      onPressed: () {
                        setState(() {
                          _isWontDo = !_isWontDo;
                        });
                      },
                    ),
                  ],
                ),
                
                // Status chips under the icons
                if (_dueDate != null) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      Chip(
                        backgroundColor: palette.primary.withValues(alpha: 0.1),
                        side: BorderSide.none,
                        avatar: Icon(Icons.calendar_today, size: 12, color: palette.primary),
                        label: Text(
                          '${_dueDate!.year}-${_dueDate!.month.toString().padLeft(2, '0')}-${_dueDate!.day.toString().padLeft(2, '0')}${_dueHasTime ? ' ${_dueDate!.hour.toString().padLeft(2, '0')}:${_dueDate!.minute.toString().padLeft(2, '0')}' : ''}',
                          style: TextStyle(color: palette.primary, fontSize: 11),
                        ),
                        onDeleted: () => setState(() {
                          _dueDate = null;
                          _alarmPreset = null;
                          _selectedOffsets = {};
                        }),
                      ),
                      if (_alarmPreset != null)
                        Chip(
                          backgroundColor: palette.primary.withValues(alpha: 0.1),
                          side: BorderSide.none,
                          avatar: Icon(Icons.notifications_active, size: 12, color: palette.primary),
                          label: Text(
                            _alarmPreset!.name.toUpperCase(),
                            style: TextStyle(color: palette.primary, fontSize: 11),
                          ),
                        ),
                    ],
                  ),
                ],

                if (_isEditing) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Subtasks',
                    style: TextStyle(color: palette.text, fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  ref.watch(subtasksProvider(widget.existingTask!.id)).when(
                        data: (subtasks) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (subtasks.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                                  child: Text(
                                    'No subtasks yet',
                                    style: TextStyle(color: palette.text.withValues(alpha: 0.4), fontSize: 12),
                                  ),
                                ),
                              ...subtasks.map((subtask) {
                                return Row(
                                  children: [
                                    Checkbox(
                                      value: subtask.isCompleted,
                                      activeColor: palette.primary,
                                      onChanged: (val) {
                                        if (val == true) {
                                          ref.read(taskRepositoryProvider).completeTask(subtask.id);
                                        } else {
                                          ref.read(taskRepositoryProvider).uncompleteTask(subtask.id);
                                        }
                                      },
                                    ),
                                    Expanded(
                                      child: Text(
                                        subtask.title,
                                        style: TextStyle(
                                          color: subtask.isCompleted ? palette.text.withValues(alpha: 0.4) : palette.text,
                                          decoration: subtask.isCompleted ? TextDecoration.lineThrough : null,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      icon: Icon(Icons.delete_outline, color: palette.text.withValues(alpha: 0.4), size: 18),
                                      onPressed: () => ref.read(taskRepositoryProvider).softDeleteTask(subtask.id),
                                    ),
                                  ],
                                );
                              }),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _subtaskController,
                                      style: TextStyle(color: palette.text, fontSize: 13),
                                      decoration: InputDecoration(
                                        hintText: 'Add subtask...',
                                        hintStyle: TextStyle(color: palette.text.withValues(alpha: 0.4)),
                                        isDense: true,
                                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                                        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: palette.text.withValues(alpha: 0.1))),
                                        focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: palette.primary)),
                                      ),
                                      onSubmitted: (value) {
                                        final text = value.trim();
                                        if (text.isNotEmpty) {
                                          ref.read(taskRepositoryProvider).createTask(
                                                parentTaskId: widget.existingTask!.id,
                                                listId: widget.existingTask!.listId,
                                                title: text,
                                              );
                                          _subtaskController.clear();
                                        }
                                      },
                                    ),
                                  ),
                                  IconButton(
                                    icon: Icon(Icons.add_circle, color: palette.primary, size: 22),
                                    onPressed: () {
                                      final text = _subtaskController.text.trim();
                                      if (text.isNotEmpty) {
                                        ref.read(taskRepositoryProvider).createTask(
                                              parentTaskId: widget.existingTask!.id,
                                              listId: widget.existingTask!.listId,
                                              title: text,
                                            );
                                        _subtaskController.clear();
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ],
                          );
                        },
                        loading: () => const Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))),
                        error: (e, s) => const Text('Error loading subtasks', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                      ),
                ],

                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: palette.text,
                          side: BorderSide(color: palette.text.withValues(alpha: 0.2)),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: palette.primary,
                          foregroundColor: palette.background,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        onPressed: _isSaving || _titleController.text.trim().isEmpty ? null : _save,
                        child: _isSaving
                            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : Text(_isEditing ? 'Save' : 'Add task', style: const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Flying menu: Date, Time & Alarm dialog ──
  Future<void> _showDateTimeAlarmDialog(BuildContext context, AppPalette palette) async {
    final now = DateTime.now();
    DateTime tempDate = _dueDate ?? now;
    bool tempHasTime = _dueHasTime;
    AlarmPreset? tempPreset = _alarmPreset;
    Set<ReminderOffset> tempOffsets = Set.from(_selectedOffsets);
    int tempDuration = _durationMinutes;
    RecurrenceType tempRecurrenceType = _recurrence.type;
    List<int> tempRecurrenceWeekdays = List<int>.from(_recurrence.weekdays);

    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            decoration: BoxDecoration(
              color: palette.surface.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: palette.text.withValues(alpha: 0.1)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: GlassmorphicWrapper(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: StatefulBuilder(
                  builder: (ctx, setDlgState) {
                    return SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('Due Date & Time', style: TextStyle(color: palette.text, fontSize: 18, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 12),
                          // Calendar Day view
                          Theme(
                            data: Theme.of(ctx).copyWith(
                              colorScheme: ColorScheme.dark(
                                primary: palette.primary,
                                onPrimary: palette.background,
                                surface: palette.surface,
                                onSurface: palette.text,
                              ),
                            ),
                            child: CalendarDatePicker(
                              initialDate: tempDate,
                              firstDate: now.subtract(const Duration(days: 365)),
                              lastDate: now.add(const Duration(days: 365 * 5)),
                              onDateChanged: (d) {
                                setDlgState(() {
                                  tempDate = DateTime(d.year, d.month, d.day, tempDate.hour, tempDate.minute);
                                });
                              },
                            ),
                          ),
                          const SizedBox(height: 8),
                          // Time switch + inline Clock selectors
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text('Include Specific Time', style: TextStyle(color: palette.text, fontSize: 14)),
                            value: tempHasTime,
                            activeThumbColor: palette.primary,
                            onChanged: (val) {
                              setDlgState(() {
                                tempHasTime = val;
                              });
                            },
                          ),
                          if (tempHasTime) ...[
                            const SizedBox(height: 4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                // Hour Dropdown
                                DropdownButton<int>(
                                  dropdownColor: palette.surface,
                                  value: tempDate.hour,
                                  style: TextStyle(color: palette.text),
                                  items: [
                                    for (int h = 0; h < 24; h++)
                                      DropdownMenuItem(value: h, child: Text(h.toString().padLeft(2, '0'))),
                                  ],
                                  onChanged: (h) {
                                    if (h != null) {
                                      setDlgState(() {
                                        tempDate = DateTime(tempDate.year, tempDate.month, tempDate.day, h, tempDate.minute);
                                      });
                                    }
                                  },
                                ),
                                Text(' : ', style: TextStyle(color: palette.text, fontWeight: FontWeight.bold)),
                                // Minute Dropdown
                                DropdownButton<int>(
                                  dropdownColor: palette.surface,
                                  value: tempDate.minute,
                                  style: TextStyle(color: palette.text),
                                  items: [
                                    for (int m = 0; m < 60; m++)
                                      DropdownMenuItem(value: m, child: Text(m.toString().padLeft(2, '0'))),
                                  ],
                                  onChanged: (m) {
                                    if (m != null) {
                                      setDlgState(() {
                                        tempDate = DateTime(tempDate.year, tempDate.month, tempDate.day, tempDate.hour, m);
                                      });
                                    }
                                  },
                                ),
                              ],
                            ),
                          ],
                          const Divider(),
                          // Alarmpreset
                          Row(
                            children: [
                              Text('Alarm Mode', style: TextStyle(color: palette.text, fontSize: 14)),
                              const Spacer(),
                              DropdownButton<AlarmPreset?>(
                                dropdownColor: palette.surface,
                                underline: const SizedBox.shrink(),
                                style: TextStyle(color: palette.text),
                                value: tempPreset,
                                hint: Text('None', style: TextStyle(color: palette.text.withValues(alpha: 0.5))),
                                items: const [
                                  DropdownMenuItem(value: null, child: Text('None')),
                                  DropdownMenuItem(value: AlarmPreset.light, child: Text('Light (Notification)')),
                                  DropdownMenuItem(value: AlarmPreset.medium, child: Text('Medium (Full Screen)')),
                                  DropdownMenuItem(value: AlarmPreset.strong, child: Text('Strong (Long Sound)')),
                                  DropdownMenuItem(value: AlarmPreset.constant, child: Text('Constant Alert')),
                                ],
                                onChanged: (value) => setDlgState(() => tempPreset = value),
                              ),
                            ],
                          ),
                          if (tempPreset != null) ...[
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                for (final offset in ReminderOffset.presets)
                                  FilterChip(
                                    label: Text(offset.label, style: TextStyle(color: tempOffsets.contains(offset) ? palette.background : palette.text, fontSize: 11)),
                                    selected: tempOffsets.contains(offset),
                                    selectedColor: palette.primary,
                                    backgroundColor: palette.text.withValues(alpha: 0.05),
                                    onSelected: (selected) => setDlgState(() {
                                      if (selected) {
                                        tempOffsets.add(offset);
                                      } else {
                                        tempOffsets.remove(offset);
                                      }
                                    }),
                                  ),
                              ],
                            ),
                          ],
                          const Divider(),
                          // Duration
                          Row(
                            children: [
                              Text('Task Duration', style: TextStyle(color: palette.text, fontSize: 14)),
                              const Spacer(),
                              DropdownButton<int>(
                                dropdownColor: palette.surface,
                                underline: const SizedBox.shrink(),
                                style: TextStyle(color: palette.text),
                                value: tempDuration,
                                items: const [
                                  DropdownMenuItem(value: 15, child: Text('15 min')),
                                  DropdownMenuItem(value: 30, child: Text('30 min')),
                                  DropdownMenuItem(value: 45, child: Text('45 min')),
                                  DropdownMenuItem(value: 60, child: Text('1 hour')),
                                  DropdownMenuItem(value: 90, child: Text('1.5 hours')),
                                  DropdownMenuItem(value: 120, child: Text('2 hours')),
                                  DropdownMenuItem(value: 180, child: Text('3 hours')),
                                  DropdownMenuItem(value: 240, child: Text('4 hours')),
                                ],
                                onChanged: (value) => setDlgState(() {
                                  if (value != null) tempDuration = value;
                                }),
                              ),
                            ],
                          ),
                          const Divider(),
                          // Recurrence
                          Row(
                            children: [
                              Text('Repeat Pattern', style: TextStyle(color: palette.text, fontSize: 14)),
                              const Spacer(),
                              DropdownButton<RecurrenceType>(
                                dropdownColor: palette.surface,
                                underline: const SizedBox.shrink(),
                                style: TextStyle(color: palette.text),
                                value: tempRecurrenceType,
                                items: const [
                                  DropdownMenuItem(value: RecurrenceType.none, child: Text('None')),
                                  DropdownMenuItem(value: RecurrenceType.daily, child: Text('Daily')),
                                  DropdownMenuItem(value: RecurrenceType.weekly, child: Text('Weekly')),
                                  DropdownMenuItem(value: RecurrenceType.yearly, child: Text('Yearly')),
                                ],
                                onChanged: (value) => setDlgState(() {
                                  if (value != null) tempRecurrenceType = value;
                                }),
                              ),
                            ],
                          ),
                          if (tempRecurrenceType == RecurrenceType.weekly) ...[
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                for (int d = 1; d <= 7; d++)
                                  GestureDetector(
                                    onTap: () => setDlgState(() {
                                      if (tempRecurrenceWeekdays.contains(d)) {
                                        tempRecurrenceWeekdays.remove(d);
                                      } else {
                                        tempRecurrenceWeekdays.add(d);
                                      }
                                    }),
                                    child: Container(
                                      width: 32,
                                      height: 32,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: tempRecurrenceWeekdays.contains(d) ? palette.primary : Colors.transparent,
                                        border: Border.all(
                                          color: tempRecurrenceWeekdays.contains(d) ? palette.primary : palette.text.withValues(alpha: 0.2),
                                        ),
                                      ),
                                      alignment: Alignment.center,
                                      child: Text(
                                        switch (d) {
                                          1 => 'M',
                                          2 => 'T',
                                          3 => 'W',
                                          4 => 'T',
                                          5 => 'F',
                                          6 => 'S',
                                          _ => 'S',
                                        },
                                        style: TextStyle(
                                          color: tempRecurrenceWeekdays.contains(d) ? palette.background : palette.text,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 16),
                          FilledButton(
                            style: FilledButton.styleFrom(backgroundColor: palette.primary, foregroundColor: palette.background),
                            onPressed: () {
                              Navigator.pop(ctx, true);
                            },
                            child: const Text('Done', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );

    if (res == true) {
      setState(() {
        _dueDate = tempDate;
        _dueHasTime = tempHasTime;
        _alarmPreset = tempPreset;
        _selectedOffsets = tempOffsets;
        _durationMinutes = tempDuration;
        _recurrence = TaskRecurrence(type: tempRecurrenceType, weekdays: tempRecurrenceWeekdays);
      });

      SessionRestore.saveDraftValue('task', widget.existingTask?.id, 'dueDate', tempDate.toIso8601String()); // ignore: unawaited_futures
      SessionRestore.saveDraftValue('task', widget.existingTask?.id, 'dueHasTime', tempHasTime.toString()); // ignore: unawaited_futures
      SessionRestore.saveDraftValue('task', widget.existingTask?.id, 'alarmPreset', (tempPreset ?? AlarmPreset.light).name); // ignore: unawaited_futures
    }
  }

  // ── Flying menu: Tag search & creation dialog ──
  Future<void> _onTagIconPressed(BuildContext context, AppPalette palette) async {
    // Insert hashtag symbol
    final text = _titleController.text;
    final cursor = _titleController.selection.baseOffset.clamp(0, text.length).toInt();
    final before = text.substring(0, cursor);
    final after = text.substring(cursor);
    _titleController.value = TextEditingValue(
      text: '$before #$after',
      selection: TextSelection.collapsed(offset: cursor + 2),
    );

    // Fetch tags list for menu
    final tagsList = ref.read(allTagsProvider).value ?? [];
    String searchQuery = '';

    await showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 320, maxHeight: 400),
            decoration: BoxDecoration(
              color: palette.surface.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: palette.text.withValues(alpha: 0.1)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: GlassmorphicWrapper(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: StatefulBuilder(
                  builder: (ctx, setDlgState) {
                    final filtered = searchQuery.isEmpty
                        ? tagsList
                        : tagsList.where((t) => t.name.toLowerCase().contains(searchQuery.toLowerCase())).toList();
                    final exactMatch = tagsList.any((t) => t.name.toLowerCase() == searchQuery.trim().toLowerCase());

                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('Select Tag', style: TextStyle(color: palette.text, fontSize: 16, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          TextField(
                            autofocus: true,
                            style: TextStyle(color: palette.text, fontSize: 14),
                            onChanged: (q) => setDlgState(() => searchQuery = q),
                            decoration: InputDecoration(
                              hintText: 'Search or create...',
                              hintStyle: TextStyle(color: palette.text.withValues(alpha: 0.4)),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Expanded(
                            child: filtered.isEmpty && searchQuery.trim().isEmpty
                                ? Center(child: Text('No tags found', style: TextStyle(color: palette.text.withValues(alpha: 0.4))))
                                : ListView.builder(
                                    shrinkWrap: true,
                                    itemCount: filtered.length,
                                    itemBuilder: (ctx, i) {
                                      final t = filtered[i];
                                      return ListTile(
                                        title: Text('#${t.name}', style: TextStyle(color: palette.text)),
                                        dense: true,
                                        onTap: () {
                                          final fullText = _titleController.text;
                                          final cur = _titleController.selection.baseOffset.clamp(0, fullText.length).toInt();
                                          final hashIdx = fullText.substring(0, cur).lastIndexOf('#');
                                          if (hashIdx != -1) {
                                            _titleController.value = TextEditingValue(
                                              text: '${fullText.substring(0, hashIdx)}#${t.name} ${fullText.substring(cur)}',
                                              selection: TextSelection.collapsed(offset: hashIdx + t.name.length + 2),
                                            );
                                          }
                                          Navigator.pop(ctx);
                                        },
                                      );
                                    },
                                  ),
                          ),
                          if (searchQuery.trim().isNotEmpty && !exactMatch) ...[
                            const SizedBox(height: 8),
                            FilledButton(
                              style: FilledButton.styleFrom(backgroundColor: palette.primary, foregroundColor: palette.background),
                              onPressed: () async {
                                final newTagName = searchQuery.trim();
                                final newTag = await ref.read(taskRepositoryProvider).createTag(name: newTagName);
                                final fullText = _titleController.text;
                                final cur = _titleController.selection.baseOffset.clamp(0, fullText.length).toInt();
                                final hashIdx = fullText.substring(0, cur).lastIndexOf('#');
                                if (hashIdx != -1) {
                                  _titleController.value = TextEditingValue(
                                    text: '${fullText.substring(0, hashIdx)}#${newTag.name} ${fullText.substring(cur)}',
                                    selection: TextSelection.collapsed(offset: hashIdx + newTag.name.length + 2),
                                  );
                                }
                                if (ctx.mounted) Navigator.pop(ctx);
                              },
                              child: Text('Create tag "#${searchQuery.trim()}"'),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ── Flying menu: List selection & creation dialog ──
  Future<void> _onListIconPressed(BuildContext context, AppPalette palette) async {
    // Insert list symbol
    final text = _titleController.text;
    final cursor = _titleController.selection.baseOffset.clamp(0, text.length).toInt();
    final before = text.substring(0, cursor);
    final after = text.substring(cursor);
    _titleController.value = TextEditingValue(
      text: '$before ~$after',
      selection: TextSelection.collapsed(offset: cursor + 2),
    );

    // Fetch lists
    final listsList = ref.read(listsProvider).value ?? [];

    await showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 320, maxHeight: 400),
            decoration: BoxDecoration(
              color: palette.surface.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: palette.text.withValues(alpha: 0.1)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: GlassmorphicWrapper(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: StatefulBuilder(
                  builder: (ctx, setDlgState) {
                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('Select List', style: TextStyle(color: palette.text, fontSize: 16, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Expanded(
                            child: ListView.builder(
                              shrinkWrap: true,
                              itemCount: listsList.length,
                              itemBuilder: (ctx, i) {
                                final list = listsList[i];
                                return ListTile(
                                  title: Text('~${list.name}', style: TextStyle(color: palette.text)),
                                  dense: true,
                                  onTap: () {
                                    final fullText = _titleController.text;
                                    final cur = _titleController.selection.baseOffset.clamp(0, fullText.length).toInt();
                                    final listIdx = fullText.substring(0, cur).lastIndexOf('~');
                                    if (listIdx != -1) {
                                      _titleController.value = TextEditingValue(
                                        text: '${fullText.substring(0, listIdx)}~${list.name} ${fullText.substring(cur)}',
                                        selection: TextSelection.collapsed(offset: listIdx + list.name.length + 2),
                                      );
                                    }
                                    Navigator.pop(ctx);
                                  },
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(foregroundColor: palette.primary, side: BorderSide(color: palette.primary)),
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('New list...'),
                            onPressed: () async {
                              // Open a quick inline name prompt
                              final nameCtrl = TextEditingController();
                              final newList = await showDialog<TaskList>(
                                context: ctx,
                                builder: (c2) => AlertDialog(
                                  backgroundColor: palette.surface,
                                  title: Text('New list', style: TextStyle(color: palette.text)),
                                  content: TextField(
                                    controller: nameCtrl,
                                    autofocus: true,
                                    style: TextStyle(color: palette.text),
                                    decoration: const InputDecoration(hintText: 'List name'),
                                  ),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(c2), child: const Text('Cancel')),
                                    FilledButton(
                                      onPressed: () async {
                                        final list = await ref.read(taskRepositoryProvider).createList(name: nameCtrl.text.trim());
                                        if (c2.mounted) Navigator.pop(c2, list);
                                      },
                                      child: const Text('Create'),
                                    ),
                                  ],
                                ),
                              );
                              if (newList != null) {
                                final fullText = _titleController.text;
                                final cur = _titleController.selection.baseOffset.clamp(0, fullText.length).toInt();
                                final listIdx = fullText.substring(0, cur).lastIndexOf('~');
                                if (listIdx != -1) {
                                  _titleController.value = TextEditingValue(
                                    text: '${fullText.substring(0, listIdx)}~${newList.name} ${fullText.substring(cur)}',
                                    selection: TextSelection.collapsed(offset: listIdx + newList.name.length + 2),
                                  );
                                }
                                if (ctx.mounted) Navigator.pop(ctx);
                              }
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;

    final navigator = Navigator.of(context);
    setState(() => _isSaving = true);
    final repo = ref.read(taskRepositoryProvider);
    final description = _descriptionController.text.trim();

    try {
      if (_alarmPreset != null) {
        await requestAlarmPermissions(_alarmPreset!);
      }
      if (_isEditing) {
        await repo.updateTask(
          widget.existingTask!.id,
          title: title,
          description: description.isEmpty ? null : description,
          priority: _priority,
          dueDate: Value(_dueDate),
          dueHasTime: _dueHasTime,
          recurrence: _recurrence,
          durationMinutes: _durationMinutes,
          isWontDo: _isWontDo,
          alarmPreset: Value(_alarmPreset),
          reminderOffsets: _selectedOffsets.toList(),
        );
      } else {
        var targetListId = widget.listId;
        if (targetListId.startsWith('smart:') || targetListId.startsWith('custom_smart:')) {
          final lists = ref.read(listsProvider).value ?? [];
          final inbox = lists.firstWhere((l) => l.isInbox, orElse: () => lists.first);
          targetListId = inbox.id;
        }
        await repo.createTask(
          listId: targetListId,
          title: title,
          description: description.isEmpty ? null : description,
          priority: _priority,
          dueDate: _dueDate,
          dueHasTime: _dueHasTime,
          recurrence: _recurrence,
          durationMinutes: _durationMinutes,
          isWontDo: _isWontDo,
          alarmPreset: _alarmPreset,
          reminderOffsets: _selectedOffsets.toList(),
        );
      }
      await SessionRestore.clearDraftValues('task', widget.existingTask?.id);
      navigator.pop();
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}
