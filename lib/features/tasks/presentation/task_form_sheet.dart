import 'dart:ui';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/theme_engine_provider.dart';
import '../../../core/theme/theme_palettes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/local/database.dart';
import '../../alarms/domain/alarm_preset.dart';
import '../../alarms/domain/reminder_offset.dart';
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

  late int _priority = widget.existingTask?.priority ?? 0;
  DateTime? _dueDate;
  bool _dueHasTime = false;
  AlarmPreset? _alarmPreset;
  late Set<ReminderOffset> _selectedOffsets = {};
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final task = widget.existingTask;
    if (task != null) {
      _dueDate = task.dueDate?.toLocal();
      _dueHasTime = task.dueHasTime;
      _alarmPreset = task.alarmPreset != null
          ? AlarmPreset.values.byName(task.alarmPreset!)
          : null;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  bool get _isEditing => widget.existingTask != null;

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
                      child: TextField(
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
                    Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: switch (_priority) {
                          3 => AppColors.priorityHigh,
                          2 => AppColors.priorityMedium,
                          1 => AppColors.priorityLow,
                          _ => palette.text.withValues(alpha: 0.2),
                        },
                      ),
                    ),
                    if (_isEditing) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        icon: Icon(Icons.delete_outline, color: Colors.redAccent.withValues(alpha: 0.8)),
                        onPressed: () async {
                          await ref.read(taskRepositoryProvider).softDeleteTask(widget.existingTask!.id);
                          if (context.mounted) Navigator.pop(context);
                        },
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _descriptionController,
                  style: TextStyle(color: palette.text),
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
                const SizedBox(height: 16),
                _buildPriorityPicker(palette),
                const SizedBox(height: 16),
                _buildDuePicker(context, palette),
                if (_dueDate != null) ...[
                  const SizedBox(height: 16),
                  _buildAlarmPicker(palette),
                ],
                const SizedBox(height: 24),
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

  Widget _buildPriorityPicker(AppPalette palette) {
    const labels = ['None', 'Low', 'Medium', 'High'];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: palette.text.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Priority', style: TextStyle(color: palette.text, fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            style: SegmentedButton.styleFrom(
              backgroundColor: palette.surface,
              foregroundColor: palette.text,
              selectedBackgroundColor: palette.primary.withValues(alpha: 0.2),
              selectedForegroundColor: palette.primary,
            ),
            segments: [
              for (var i = 0; i < labels.length; i++)
                ButtonSegment(value: i, label: Text(labels[i])),
            ],
            selected: {_priority},
            onSelectionChanged: (selection) => setState(() => _priority = selection.first),
          ),
        ],
      ),
    );
  }

  Widget _buildDuePicker(BuildContext context, AppPalette palette) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: palette.text.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _dueDate == null
                  ? 'No due date'
                  : '${_dueDate!.year}-${_dueDate!.month.toString().padLeft(2, '0')}-'
                        '${_dueDate!.day.toString().padLeft(2, '0')}'
                        '${_dueHasTime ? ' ${_dueDate!.hour.toString().padLeft(2, '0')}:'
                                  '${_dueDate!.minute.toString().padLeft(2, '0')}' : ''}',
              style: TextStyle(color: palette.text, fontWeight: FontWeight.w500),
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: palette.primary),
            onPressed: _pickDate, 
            child: const Text('Set date', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          if (_dueDate != null)
            IconButton(
              icon: Icon(Icons.close, color: palette.text.withValues(alpha: 0.6)),
              onPressed: () => setState(() {
                _dueDate = null;
                _alarmPreset = null;
                _selectedOffsets = {};
              }),
            ),
        ],
      ),
    );
  }

  Widget _buildAlarmPicker(AppPalette palette) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: palette.text.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Alarm', style: TextStyle(color: palette.text, fontWeight: FontWeight.w500)),
              const Spacer(),
              DropdownButton<AlarmPreset?>(
                dropdownColor: palette.surface,
                underline: const SizedBox.shrink(),
                style: TextStyle(color: palette.text),
                value: _alarmPreset,
                hint: Text('None', style: TextStyle(color: palette.text.withValues(alpha: 0.6))),
                items: const [
                  DropdownMenuItem(value: null, child: Text('None')),
                  DropdownMenuItem(value: AlarmPreset.light, child: Text('Light (Notification)')),
                  DropdownMenuItem(value: AlarmPreset.medium, child: Text('Medium (Full Screen)')),
                  DropdownMenuItem(value: AlarmPreset.strong, child: Text('Strong (Long Sound)')),
                  DropdownMenuItem(value: AlarmPreset.constant, child: Text('Constant Alert')),
                ],
                onChanged: (value) => setState(() => _alarmPreset = value),
              ),
            ],
          ),
          if (_alarmPreset != null) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final offset in ReminderOffset.presets)
                  FilterChip(
                    label: Text(offset.label, style: TextStyle(color: _selectedOffsets.contains(offset) ? palette.background : palette.text)),
                    selected: _selectedOffsets.contains(offset),
                    selectedColor: palette.primary,
                    backgroundColor: palette.text.withValues(alpha: 0.05),
                    onSelected: (selected) => setState(() {
                      if (selected) {
                        _selectedOffsets.add(offset);
                      } else {
                        _selectedOffsets.remove(offset);
                      }
                    }),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? now,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365 * 5)),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_dueDate ?? now),
    );

    setState(() {
      _dueHasTime = time != null;
      _dueDate = time == null
          ? date
          : DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    final repo = ref.read(taskRepositoryProvider);
    final title = _titleController.text.trim();
    final description = _descriptionController.text.trim();

    try {
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
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}
