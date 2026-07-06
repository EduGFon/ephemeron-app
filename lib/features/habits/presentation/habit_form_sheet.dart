import 'dart:ui';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/theme/theme_engine_provider.dart';
import '../../../core/theme/theme_palettes.dart';
import '../../../data/local/database.dart';
import '../../alarms/domain/alarm_preset.dart';
import '../application/habit_providers.dart';
import '../domain/habit_frequency.dart';
import '../domain/habit_goal_unit.dart';
import '../domain/habit_section.dart';

Future<void> showHabitFormSheet(BuildContext context, {Habit? existingHabit, String? initialName}) {
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
              child: HabitFormSheet(existingHabit: existingHabit, initialName: initialName),
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

const _goalDurationOptions = ['forever', '7', '21', '30', '100', '365'];
const _weekdayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

class HabitFormSheet extends ConsumerStatefulWidget {
  const HabitFormSheet({this.initialName, this.existingHabit, this.unifiedHeader, super.key});

  final String? initialName;
  final Habit? existingHabit;
  final Widget? unifiedHeader;

  @override
  ConsumerState<HabitFormSheet> createState() => _HabitFormSheetState();
}

class _HabitFormSheetState extends ConsumerState<HabitFormSheet> {
  late final _nameController = TextEditingController(
    text: widget.existingHabit?.name ?? widget.initialName,
  );
  late TextEditingController _amountController;
  late final _intervalController = TextEditingController(text: '1');
  late TextEditingController _incrementController;

  late String _section = widget.existingHabit?.section ?? HabitSection.other.id;
  late HabitFrequencyType _frequencyType;
  late Set<int> _weekdays;
  int _timesPerWeek = 3;
  late String _goalType = widget.existingHabit?.goalType ?? 'binary';
  late String _goalDuration = widget.existingHabit?.goalDuration ?? 'forever';
  HabitGoalUnit _selectedUnit = HabitGoalUnit.times;
  int? _reminderHour;
  int? _reminderMinute;
  AlarmPreset? _alarmPreset;
  bool _isSaving = false;

  bool get _isEditing => widget.existingHabit != null;

  @override
  void initState() {
    super.initState();
    late final String _amountText;
    if (widget.existingHabit != null && widget.existingHabit!.goalAmount != null) {
      _amountText = widget.existingHabit!.goalAmount!.toInt().toString();
    } else {
      _amountText = '';
    }
    _amountController = TextEditingController(text: _amountText);

    late final String _incrementText;
    if (widget.existingHabit != null && widget.existingHabit!.logIncrement != null) {
      _incrementText = widget.existingHabit!.logIncrement!.toInt().toString();
    } else {
      _incrementText = '1';
    }
    _incrementController = TextEditingController(text: _incrementText);

    final habit = widget.existingHabit;
    final frequency = HabitFrequency.decode(habit?.frequencyConfig);
    _frequencyType = frequency.type;
    _weekdays = frequency.weekdays.toSet();
    _timesPerWeek = frequency.timesPerWeek ?? 3;
    _intervalController.text = (frequency.intervalDays ?? 1).toString();
    _selectedUnit = HabitGoalUnit.tryParse(habit?.goalUnit) ?? HabitGoalUnit.times;
    _reminderHour = habit?.reminderHour;
    _reminderMinute = habit?.reminderMinute;
    _alarmPreset = habit?.alarmPreset != null
        ? AlarmPreset.values.byName(habit!.alarmPreset!)
        : null;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    _intervalController.dispose();
    _incrementController.dispose();
    super.dispose();
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
                      child: TextField(
                        controller: _nameController,
                        autofocus: !_isEditing,
                        onChanged: (_) => setState(() {}),
                        style: TextStyle(color: palette.text, fontSize: 22, fontWeight: FontWeight.bold),
                        decoration: InputDecoration(
                          hintText: 'Habit Name',
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
                    Icon(Icons.repeat, color: palette.primary),
                    if (_isEditing) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        icon: Icon(Icons.delete_outline, color: Colors.redAccent.withValues(alpha: 0.8)),
                        onPressed: () async {
                          await ref.read(habitRepositoryProvider).deleteHabit(widget.existingHabit!.id);
                          if (context.mounted) Navigator.pop(context);
                        },
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 16),
                _buildSectionPicker(palette),
                const SizedBox(height: 16),
                _buildFrequencyPicker(palette),
                const SizedBox(height: 16),
                _buildGoalPicker(palette),
                const SizedBox(height: 16),
                _buildGoalDurationPicker(palette),
                const SizedBox(height: 16),
                _buildReminderPicker(palette),
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
                        onPressed: _isSaving || _nameController.text.trim().isEmpty ? null : _save,
                        child: _isSaving
                            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : Text(_isEditing ? 'Save' : 'Add habit', style: const TextStyle(fontWeight: FontWeight.bold)),
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

  Widget _buildSectionPicker(AppPalette palette) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: palette.text.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Text('Section', style: TextStyle(color: palette.text, fontWeight: FontWeight.w500)),
          const Spacer(),
          DropdownButton<String>(
            dropdownColor: palette.surface,
            style: TextStyle(color: palette.text),
            underline: const SizedBox.shrink(),
            value: _section,
            items: [
              for (final section in HabitSection.defaults)
                DropdownMenuItem(value: section.id, child: Text(section.label)),
            ],
            onChanged: (value) => setState(() {
              _section = value ?? _section;
              if (_reminderHour == null) {
                _reminderHour = HabitSection.resolve(_section).suggestedHour;
                _reminderMinute = 0;
              }
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildFrequencyPicker(AppPalette palette) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Frequency', style: TextStyle(color: palette.text, fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        SegmentedButton<HabitFrequencyType>(
          style: SegmentedButton.styleFrom(
            backgroundColor: palette.text.withValues(alpha: 0.05),
            foregroundColor: palette.text,
            selectedBackgroundColor: palette.primary.withValues(alpha: 0.2),
            selectedForegroundColor: palette.primary,
          ),
          segments: const [
            ButtonSegment(value: HabitFrequencyType.daily, label: Text('Daily')),
            ButtonSegment(value: HabitFrequencyType.weekly, label: Text('Weekly')),
            ButtonSegment(value: HabitFrequencyType.interval, label: Text('Interval')),
          ],
          selected: {_frequencyType},
          onSelectionChanged: (selection) => setState(() => _frequencyType = selection.first),
        ),
        const SizedBox(height: 12),
        switch (_frequencyType) {
          HabitFrequencyType.daily => Wrap(
            spacing: 6,
            children: [
              for (var i = 0; i < 7; i++)
                FilterChip(
                  label: Text(_weekdayLabels[i], style: TextStyle(color: _weekdays.contains(i + 1) ? palette.background : palette.text)),
                  selected: _weekdays.contains(i + 1),
                  selectedColor: palette.primary,
                  backgroundColor: palette.text.withValues(alpha: 0.05),
                  onSelected: (selected) => setState(() {
                    if (selected) {
                      _weekdays.add(i + 1);
                    } else {
                      _weekdays.remove(i + 1);
                    }
                  }),
                ),
            ],
          ),
          HabitFrequencyType.weekly => Row(
            children: [
              Text('Times per week:', style: TextStyle(color: palette.text)),
              Expanded(
                child: Slider(
                  activeColor: palette.primary,
                  inactiveColor: palette.text.withValues(alpha: 0.1),
                  value: _timesPerWeek.toDouble(),
                  min: 1,
                  max: 7,
                  divisions: 6,
                  label: '$_timesPerWeek',
                  onChanged: (value) => setState(() => _timesPerWeek = value.round()),
                ),
              ),
              Text('$_timesPerWeek', style: TextStyle(color: palette.text, fontWeight: FontWeight.bold)),
            ],
          ),
          HabitFrequencyType.interval => Row(
            children: [
              Text('Every', style: TextStyle(color: palette.text)),
              const SizedBox(width: 8),
              SizedBox(
                width: 60,
                child: TextField(
                  controller: _intervalController,
                  keyboardType: TextInputType.number,
                  style: TextStyle(color: palette.text),
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text('days', style: TextStyle(color: palette.text)),
            ],
          ),
        },
        if (_frequencyType == HabitFrequencyType.daily && _weekdays.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('No days selected = every day', style: TextStyle(color: palette.text.withValues(alpha: 0.6), fontSize: 12)),
          ),
      ],
    );
  }

  Widget _buildGoalPicker(AppPalette palette) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Goal', style: TextStyle(color: palette.text, fontWeight: FontWeight.w500)),
            const Spacer(),
            SegmentedButton<String>(
              style: SegmentedButton.styleFrom(
                backgroundColor: palette.text.withValues(alpha: 0.05),
                foregroundColor: palette.text,
                selectedBackgroundColor: palette.primary.withValues(alpha: 0.2),
                selectedForegroundColor: palette.primary,
              ),
              segments: const [
                ButtonSegment(value: 'binary', label: Text('Yes/No')),
                ButtonSegment(value: 'amount', label: Text('Amount')),
              ],
              selected: {_goalType},
              onSelectionChanged: (selection) => setState(() => _goalType = selection.first),
            ),
          ],
        ),
        if (_goalType == 'amount') ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _amountController,
                  keyboardType: TextInputType.number,
                  style: TextStyle(color: palette.text),
                  decoration: InputDecoration(
                    labelText: 'Goal amount',
                    labelStyle: TextStyle(color: palette.text.withValues(alpha: 0.6)),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<HabitGoalUnit>(
                  dropdownColor: palette.surface,
                  initialValue: _selectedUnit,
                  style: TextStyle(color: palette.text),
                  decoration: InputDecoration(
                    labelText: 'Unit',
                    labelStyle: TextStyle(color: palette.text.withValues(alpha: 0.6)),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  items: [
                    for (final unit in HabitGoalUnit.values)
                      DropdownMenuItem(value: unit, child: Text(unit.label)),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _selectedUnit = value;
                      });
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text('Each log adds', style: TextStyle(color: palette.text)),
              const SizedBox(width: 8),
              SizedBox(
                width: 80,
                child: TextField(
                  controller: _incrementController,
                  keyboardType: TextInputType.number,
                  style: TextStyle(color: palette.text),
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(_currentUnitLabel(), style: TextStyle(color: palette.text), overflow: TextOverflow.ellipsis)),
            ],
          ),
        ],
      ],
    );
  }

  String _currentUnitLabel() {
    if (_goalType == 'binary') return 'times';
    return _selectedUnit.label;
  }

  Widget _buildGoalDurationPicker(AppPalette palette) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: palette.text.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Text('Goal length', style: TextStyle(color: palette.text, fontWeight: FontWeight.w500)),
          const Spacer(),
          DropdownButton<String>(
            dropdownColor: palette.surface,
            underline: const SizedBox.shrink(),
            style: TextStyle(color: palette.text),
            value: _goalDuration,
            items: [
              for (final option in _goalDurationOptions)
                DropdownMenuItem(value: option, child: Text(option == 'forever' ? 'Forever' : '$option days')),
            ],
            onChanged: (value) => setState(() => _goalDuration = value ?? _goalDuration),
          ),
        ],
      ),
    );
  }

  Widget _buildReminderPicker(AppPalette palette) {
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
              Text('Reminder', style: TextStyle(color: palette.text, fontWeight: FontWeight.w500)),
              const Spacer(),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: palette.primary),
                onPressed: () async {
                  final time = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay(
                      hour: _reminderHour ?? 8,
                      minute: _reminderMinute ?? 0,
                    ),
                  );
                  if (time == null) return;
                  setState(() {
                    _reminderHour = time.hour;
                    _reminderMinute = time.minute;
                    _alarmPreset ??= AlarmPreset.light;
                  });
                },
                child: Text(
                  _reminderHour == null
                      ? 'Set time'
                      : '${_reminderHour!.toString().padLeft(2, '0')}:${_reminderMinute!.toString().padLeft(2, '0')}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              if (_reminderHour != null)
                IconButton(
                  icon: Icon(Icons.close, color: palette.text.withValues(alpha: 0.6)),
                  onPressed: () => setState(() {
                    _reminderHour = null;
                    _reminderMinute = null;
                    _alarmPreset = null;
                  }),
                ),
            ],
          ),
          if (_reminderHour != null)
            Row(
              children: [
                Text('Sound: ', style: TextStyle(color: palette.text.withValues(alpha: 0.6))),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButton<AlarmPreset>(
                    dropdownColor: palette.surface,
                    underline: const SizedBox.shrink(),
                    style: TextStyle(color: palette.text),
                    isExpanded: true,
                    value: _alarmPreset ?? AlarmPreset.light,
                    items: const [
                      DropdownMenuItem(value: AlarmPreset.light, child: Text('Light (Notification)')),
                      DropdownMenuItem(value: AlarmPreset.medium, child: Text('Medium (Full Screen)')),
                      DropdownMenuItem(value: AlarmPreset.strong, child: Text('Strong (Long Sound)')),
                      DropdownMenuItem(value: AlarmPreset.constant, child: Text('Constant Alert')),
                    ],
                    onChanged: (value) => setState(() => _alarmPreset = value),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  HabitFrequency _buildFrequency() {
    switch (_frequencyType) {
      case HabitFrequencyType.daily:
        return HabitFrequency.daily(weekdays: _weekdays.toList());
      case HabitFrequencyType.weekly:
        return HabitFrequency.weekly(timesPerWeek: _timesPerWeek);
      case HabitFrequencyType.interval:
        return HabitFrequency.interval(
          intervalDays: int.tryParse(_intervalController.text) ?? 1,
        );
    }
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    final repo = ref.read(habitRepositoryProvider);
    final frequency = _buildFrequency();
    final amount = double.tryParse(_amountController.text);
    final unit = _selectedUnit.label;
    final increment = double.tryParse(_incrementController.text) ?? 1;

    try {
      if (_isEditing) {
        await repo.updateHabit(
          widget.existingHabit!.id,
          name: _nameController.text.trim(),
          section: _section,
          frequency: frequency,
          goalType: _goalType,
          goalAmount: Value(_goalType == 'amount' ? amount : null),
          goalUnit: Value(
            _goalType == 'amount' && unit.isNotEmpty ? unit : null,
          ),
          logIncrement: _goalType == 'amount' ? increment : 1,
          goalDuration: _goalDuration,
          reminderHour: Value(_reminderHour),
          reminderMinute: Value(_reminderMinute),
          alarmPreset: Value(_alarmPreset),
        );
      } else {
        await repo.createHabit(
          name: _nameController.text.trim(),
          section: _section,
          frequency: frequency,
          goalType: _goalType,
          goalAmount: _goalType == 'amount' ? amount : null,
          goalUnit: _goalType == 'amount' && unit.isNotEmpty ? unit : null,
          logIncrement: _goalType == 'amount' ? increment : 1,
          goalDuration: _goalDuration,
          reminderHour: _reminderHour,
          reminderMinute: _reminderMinute,
          alarmPreset: _alarmPreset,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}
