import 'dart:async';
import 'dart:ui';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

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
              child: TaskFormSheet(listId: listId, existingTask: existingTask),
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
    }
    SessionRestore.saveOpenMenu('task', entityId: widget.existingTask?.id, extra: widget.listId);
  }

  @override
  void dispose() {
    SessionRestore.clearOpenMenu();
    _titleController.dispose();
    _descriptionController.dispose();
    _descriptionFocusNode.dispose();
    _descriptionTypingTimer?.cancel();
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
        child: BackdropFilter(
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
                          final navigator = Navigator.of(context);
                          await ref.read(taskRepositoryProvider).softDeleteTask(widget.existingTask!.id);
                          navigator.pop();
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
                      onSelected: (val) => setState(() => _priority = val),
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
                          '${_dueDate!.year}-${_dueDate!.month.toString().padLeft(2, '0')}-${_dueDate!.day.toString().padLeft(2, '0')}' +
                          (_dueHasTime ? ' ${_dueDate!.hour.toString().padLeft(2, '0')}:${_dueDate!.minute.toString().padLeft(2, '0')}' : ''),
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

    await showDialog(
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
              child: BackdropFilter(
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
                            activeColor: palette.primary,
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
                                    for (int m = 0; m < 60; m += 5)
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

    setState(() {
      _dueDate = tempDate;
      _dueHasTime = tempHasTime;
      _alarmPreset = tempPreset;
      _selectedOffsets = tempOffsets;
    });
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
              child: BackdropFilter(
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
              child: BackdropFilter(
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
          alarmPreset: Value(_alarmPreset),
          reminderOffsets: _selectedOffsets.toList(),
        );
      } else {
        await repo.createTask(
          listId: widget.listId,
          title: title,
          description: description.isEmpty ? null : description,
          priority: _priority,
          dueDate: _dueDate,
          dueHasTime: _dueHasTime,
          recurrence: TaskRecurrence.none,
          alarmPreset: _alarmPreset,
          reminderOffsets: _selectedOffsets.toList(),
        );
      }
      navigator.pop();
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}
