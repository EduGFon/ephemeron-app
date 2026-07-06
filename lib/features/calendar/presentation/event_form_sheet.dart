import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/theme_engine_provider.dart';
import '../../../core/theme/theme_palettes.dart';
import '../../alarms/domain/reminder_offset.dart';
import '../application/calendar_providers.dart';
import '../domain/calendar_event.dart';

Future<void> showEventFormSheet(
  BuildContext context, {
  required DateTime initialDay,
  CalendarEvent? existingEvent,
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
              child: EventFormSheet(initialDay: initialDay, existingEvent: existingEvent),
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

class EventFormSheet extends ConsumerStatefulWidget {
  const EventFormSheet({this.initialDay, this.existingEvent, this.unifiedHeader, super.key});

  final DateTime? initialDay;
  final CalendarEvent? existingEvent;
  final Widget? unifiedHeader;

  @override
  ConsumerState<EventFormSheet> createState() => _EventFormSheetState();
}

class _EventFormSheetState extends ConsumerState<EventFormSheet> {
  late final _titleController = TextEditingController(text: widget.existingEvent?.title);
  late final _descriptionController = TextEditingController(text: widget.existingEvent?.description);
  late final _locationController = TextEditingController(text: widget.existingEvent?.location);

  late DateTime _start;
  late DateTime _end;
  late bool _isAllDay;
  String? _colorId;
  late Set<ReminderOffset> _selectedOffsets;
  bool _isSaving = false;

  bool get _isEditing => widget.existingEvent != null;

  @override
  void initState() {
    super.initState();
    final event = widget.existingEvent;
    final day = widget.initialDay ?? DateTime.now();
    _start = event?.start ?? DateTime(day.year, day.month, day.day, 9);
    _end = event?.end ?? _start.add(const Duration(hours: 1));
    _isAllDay = event?.isAllDay ?? false;
    _colorId = event?.colorId;
    _selectedOffsets = (event?.reminderMinutes ?? const []).map(ReminderOffset.fromMinutes).toSet();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = ref.watch(themeEngineProvider);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      constraints: const BoxConstraints(maxWidth: 500),
      decoration: BoxDecoration(
        color: palette.surface.withValues(alpha: 0.85),
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
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _isEditing ? 'Edit event' : 'New event',
                      style: TextStyle(color: palette.text, fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    if (_isEditing)
                      IconButton(
                        icon: Icon(Icons.delete_outline, color: Colors.redAccent.withValues(alpha: 0.8)),
                        onPressed: () async {
                          await ref.read(calendarRepositoryProvider).deleteEvent(
                            widget.existingEvent!.id,
                            calendarId: widget.existingEvent!.calendarId,
                          );
                          ref.invalidate(monthEventsProvider(DateTime(_start.year, _start.month, 1)));
                          if (context.mounted) Navigator.pop(context);
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _titleController,
                  autofocus: !_isEditing,
                  onChanged: (_) => setState(() {}),
                  style: TextStyle(color: palette.text),
                  decoration: InputDecoration(
                    labelText: 'Title',
                    labelStyle: TextStyle(color: palette.text.withValues(alpha: 0.6)),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: palette.text.withValues(alpha: 0.2))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: palette.primary, width: 2)),
                  ),
                  textCapitalization: TextCapitalization.sentences,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _locationController,
                  style: TextStyle(color: palette.text),
                  decoration: InputDecoration(
                    labelText: 'Location (optional)',
                    labelStyle: TextStyle(color: palette.text.withValues(alpha: 0.6)),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: palette.text.withValues(alpha: 0.2))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: palette.primary, width: 2)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _descriptionController,
                  style: TextStyle(color: palette.text),
                  decoration: InputDecoration(
                    labelText: 'Description (optional)',
                    labelStyle: TextStyle(color: palette.text.withValues(alpha: 0.6)),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: palette.text.withValues(alpha: 0.2))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: palette.primary, width: 2)),
                  ),
                  minLines: 1,
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: palette.text.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('All day', style: TextStyle(color: palette.text, fontWeight: FontWeight.w500)),
                        activeThumbColor: palette.primary,
                        value: _isAllDay,
                        onChanged: (value) => setState(() => _isAllDay = value),
                      ),
                      _DateTimeRow(
                        label: 'Starts',
                        value: _start,
                        showTime: !_isAllDay,
                        palette: palette,
                        onChanged: (value) => setState(() {
                          _start = value;
                          if (_end.isBefore(_start)) _end = _start.add(const Duration(hours: 1));
                        }),
                      ),
                      _DateTimeRow(
                        label: 'Ends',
                        value: _end,
                        showTime: !_isAllDay,
                        palette: palette,
                        onChanged: (value) => setState(() => _end = value),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: palette.text.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Color', style: TextStyle(color: palette.text, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final color in GoogleEventColor.options)
                            GestureDetector(
                              onTap: () => setState(() => _colorId = color.id),
                              child: CircleAvatar(
                                backgroundColor: Color(color.hex),
                                radius: 16,
                                child: _colorId == color.id ? const Icon(Icons.check, color: Colors.white, size: 16) : null,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: palette.text.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Remind me', style: TextStyle(color: palette.text, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final offset in ReminderOffset.presets)
                            FilterChip(
                              label: Text(offset.label, style: TextStyle(color: _selectedOffsets.contains(offset) ? palette.background : palette.text)),
                              selected: _selectedOffsets.contains(offset),
                              selectedColor: palette.primary,
                              backgroundColor: palette.surface,
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
                  ),
                ),
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
                            : Text(_isEditing ? 'Save' : 'Add event', style: const TextStyle(fontWeight: FontWeight.bold)),
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

  Future<void> _save() async {
    setState(() => _isSaving = true);
    final repo = ref.read(calendarRepositoryProvider);
    final description = _descriptionController.text.trim();
    final location = _locationController.text.trim();

    final event = CalendarEvent(
      id: widget.existingEvent?.id ?? '',
      calendarId: widget.existingEvent?.calendarId ?? 'primary',
      title: _titleController.text.trim(),
      description: description.isEmpty ? null : description,
      location: location.isEmpty ? null : location,
      start: _start,
      end: _end,
      isAllDay: _isAllDay,
      colorId: _colorId,
      reminderMinutes: _selectedOffsets.map((o) => o.beforeDue.inMinutes).toList(),
    );

    try {
      if (_isEditing) {
        await repo.updateEvent(event);
      } else {
        await repo.createEvent(event);
      }
      ref.invalidate(monthEventsProvider(DateTime(_start.year, _start.month, 1)));
      ref.invalidate(monthEventsProvider(DateTime(_end.year, _end.month, 1)));
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}

class _DateTimeRow extends StatelessWidget {
  const _DateTimeRow({
    required this.label,
    required this.value,
    required this.showTime,
    required this.palette,
    required this.onChanged,
  });

  final String label;
  final DateTime value;
  final bool showTime;
  final AppPalette palette;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    final dateLabel = '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
    final timeLabel = showTime ? ' ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}' : '';
    return Row(
      children: [
        SizedBox(width: 60, child: Text(label, style: TextStyle(color: palette.text.withValues(alpha: 0.8)))),
        Expanded(child: Text('$dateLabel$timeLabel', style: TextStyle(color: palette.text, fontWeight: FontWeight.bold))),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: palette.primary),
          onPressed: () async {
            final date = await showDatePicker(
              context: context,
              initialDate: value,
              firstDate: DateTime.now().subtract(const Duration(days: 365)),
              lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
            );
            if (date == null) return;

            if (!showTime) {
              onChanged(DateTime(date.year, date.month, date.day));
              return;
            }

            if (!context.mounted) return;
            final time = await showTimePicker(
              context: context,
              initialTime: TimeOfDay.fromDateTime(value),
            );
            if (time == null) return;

            onChanged(DateTime(date.year, date.month, date.day, time.hour, time.minute));
          },
          child: const Text('Change'),
        ),
      ],
    );
  }
}
