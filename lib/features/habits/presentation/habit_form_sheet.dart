// `show Value` only — see task_form_sheet.dart's identical comment for
// why importing the whole drift library breaks here.
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/database.dart';
import '../../alarms/domain/alarm_preset.dart';
import '../application/habit_providers.dart';
import '../domain/habit_frequency.dart';
import '../domain/habit_goal_unit.dart';
import '../domain/habit_section.dart';

Future<void> showHabitFormSheet(BuildContext context, {Habit? existingHabit}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => HabitFormSheet(existingHabit: existingHabit),
  );
}

const _goalDurationOptions = ['forever', '7', '21', '30', '100', '365'];
const _weekdayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

class HabitFormSheet extends ConsumerStatefulWidget {
  const HabitFormSheet({this.existingHabit, super.key});

  final Habit? existingHabit;

  @override
  ConsumerState<HabitFormSheet> createState() => _HabitFormSheetState();
}

class _HabitFormSheetState extends ConsumerState<HabitFormSheet> {
  late final _nameController = TextEditingController(
    text: widget.existingHabit?.name,
  );
  late final _amountController = TextEditingController(
    text: widget.existingHabit?.goalAmount?.toString() ?? '',
  );
  late final _unitController = TextEditingController(
    text: widget.existingHabit?.goalUnit,
  );
  late final _intervalController = TextEditingController(text: '1');
  late final _incrementController = TextEditingController(
    text: (widget.existingHabit?.logIncrement ?? 1).toString(),
  );

  late String _section = widget.existingHabit?.section ?? HabitSection.other.id;
  late HabitFrequencyType _frequencyType;
  late Set<int> _weekdays;
  int _timesPerWeek = 3;
  late String _goalType = widget.existingHabit?.goalType ?? 'binary';
  late String _goalDuration = widget.existingHabit?.goalDuration ?? 'forever';
  // Null means "Custom..." — falls back to the free-text _unitController.
  // Non-null means one of the curated dropdown options was matched.
  HabitGoalUnit? _selectedUnit;
  bool _isCustomUnit = false;
  int? _reminderHour;
  int? _reminderMinute;
  AlarmPreset? _alarmPreset;
  bool _isSaving = false;

  bool get _isEditing => widget.existingHabit != null;

  @override
  void initState() {
    super.initState();
    final habit = widget.existingHabit;
    final frequency = HabitFrequency.decode(habit?.frequencyConfig);
    _frequencyType = frequency.type;
    _weekdays = frequency.weekdays.toSet();
    _timesPerWeek = frequency.timesPerWeek ?? 3;
    _intervalController.text = (frequency.intervalDays ?? 1).toString();
    final parsedUnit = HabitGoalUnit.tryParse(habit?.goalUnit);
    _selectedUnit = parsedUnit;
    _isCustomUnit = habit?.goalUnit != null && parsedUnit == null;
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
    _unitController.dispose();
    _intervalController.dispose();
    _incrementController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _isEditing ? 'Edit habit' : 'New habit',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameController,
              autofocus: !_isEditing,
              decoration: const InputDecoration(labelText: 'Name'),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 16),
            _buildSectionPicker(theme),
            const SizedBox(height: 16),
            _buildFrequencyPicker(theme),
            const SizedBox(height: 16),
            _buildGoalPicker(theme),
            const SizedBox(height: 16),
            _buildGoalDurationPicker(theme),
            const SizedBox(height: 16),
            _buildReminderPicker(theme),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _isSaving || _nameController.text.trim().isEmpty
                  ? null
                  : _save,
              child: _isSaving
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_isEditing ? 'Save' : 'Add habit'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionPicker(ThemeData theme) {
    return Row(
      children: [
        Text('Section', style: theme.textTheme.bodyMedium),
        const Spacer(),
        DropdownButton<String>(
          value: _section,
          items: [
            for (final section in HabitSection.defaults)
              DropdownMenuItem(value: section.id, child: Text(section.label)),
          ],
          onChanged: (value) => setState(() {
            _section = value ?? _section;
            // Pre-fill a sensible reminder time for this section if none
            // set yet — a UI convenience, not a persisted section default
            // (see HabitSection's doc comment).
            if (_reminderHour == null) {
              _reminderHour = HabitSection.resolve(_section).suggestedHour;
              _reminderMinute = 0;
            }
          }),
        ),
      ],
    );
  }

  Widget _buildFrequencyPicker(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Frequency', style: theme.textTheme.bodyMedium),
        const SizedBox(height: 8),
        SegmentedButton<HabitFrequencyType>(
          segments: const [
            ButtonSegment(
              value: HabitFrequencyType.daily,
              label: Text('Daily'),
            ),
            ButtonSegment(
              value: HabitFrequencyType.weekly,
              label: Text('Weekly'),
            ),
            ButtonSegment(
              value: HabitFrequencyType.interval,
              label: Text('Interval'),
            ),
          ],
          selected: {_frequencyType},
          onSelectionChanged: (selection) =>
              setState(() => _frequencyType = selection.first),
        ),
        const SizedBox(height: 8),
        switch (_frequencyType) {
          HabitFrequencyType.daily => Wrap(
            spacing: 6,
            children: [
              for (var i = 0; i < 7; i++)
                FilterChip(
                  label: Text(_weekdayLabels[i]),
                  selected: _weekdays.contains(i + 1),
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
              const Text('Times per week:'),
              Expanded(
                child: Slider(
                  value: _timesPerWeek.toDouble(),
                  min: 1,
                  max: 7,
                  divisions: 6,
                  label: '$_timesPerWeek',
                  onChanged: (value) =>
                      setState(() => _timesPerWeek = value.round()),
                ),
              ),
              Text('$_timesPerWeek'),
            ],
          ),
          HabitFrequencyType.interval => Row(
            children: [
              const Text('Every'),
              const SizedBox(width: 8),
              SizedBox(
                width: 60,
                child: TextField(
                  controller: _intervalController,
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 8),
              const Text('days'),
            ],
          ),
        },
        if (_frequencyType == HabitFrequencyType.daily && _weekdays.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'No days selected = every day',
              style: theme.textTheme.labelSmall,
            ),
          ),
      ],
    );
  }

  Widget _buildGoalPicker(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Goal', style: theme.textTheme.bodyMedium),
            const Spacer(),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'binary', label: Text('Yes/No')),
                ButtonSegment(value: 'amount', label: Text('Amount')),
              ],
              selected: {_goalType},
              onSelectionChanged: (selection) =>
                  setState(() => _goalType = selection.first),
            ),
          ],
        ),
        if (_goalType == 'amount') ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Goal amount'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<HabitGoalUnit?>(
                  initialValue: _selectedUnit,
                  decoration: const InputDecoration(labelText: 'Unit'),
                  items: [
                    for (final unit in HabitGoalUnit.values)
                      DropdownMenuItem(value: unit, child: Text(unit.label)),
                    const DropdownMenuItem(
                      value: null,
                      child: Text('Custom...'),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _selectedUnit = value;
                      _isCustomUnit = value == null;
                    });
                  },
                ),
              ),
            ],
          ),
          if (_isCustomUnit) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _unitController,
              decoration: const InputDecoration(
                labelText: 'Custom unit (e.g. laps, chapters...)',
              ),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('Each log adds'),
              const SizedBox(width: 8),
              SizedBox(
                width: 80,
                child: TextField(
                  controller: _incrementController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(_currentUnitLabel()),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'e.g. goal 2 hours, each log adds 1 → tap twice to reach the goal',
              style: theme.textTheme.labelSmall,
            ),
          ),
        ],
      ],
    );
  }

  String _currentUnitLabel() {
    if (_isCustomUnit) return _unitController.text.trim();
    return _selectedUnit?.label ?? '';
  }

  Widget _buildGoalDurationPicker(ThemeData theme) {
    return Row(
      children: [
        Text('Goal length', style: theme.textTheme.bodyMedium),
        const Spacer(),
        DropdownButton<String>(
          value: _goalDuration,
          items: [
            for (final option in _goalDurationOptions)
              DropdownMenuItem(
                value: option,
                child: Text(option == 'forever' ? 'Forever' : '$option days'),
              ),
          ],
          onChanged: (value) =>
              setState(() => _goalDuration = value ?? _goalDuration),
        ),
      ],
    );
  }

  Widget _buildReminderPicker(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Reminder', style: theme.textTheme.bodyMedium),
            const Spacer(),
            TextButton(
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
              ),
            ),
            if (_reminderHour != null)
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() {
                  _reminderHour = null;
                  _reminderMinute = null;
                  _alarmPreset = null;
                }),
              ),
          ],
        ),
        if (_reminderHour != null)
          DropdownButton<AlarmPreset>(
            value: _alarmPreset ?? AlarmPreset.light,
            items: const [
              DropdownMenuItem(value: AlarmPreset.light, child: Text('Light')),
              DropdownMenuItem(
                value: AlarmPreset.medium,
                child: Text('Medium'),
              ),
            ],
            onChanged: (value) => setState(() => _alarmPreset = value),
          ),
      ],
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
    final unit = _isCustomUnit
        ? _unitController.text.trim()
        : (_selectedUnit?.label ?? '');
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
