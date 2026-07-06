import 'dart:ui';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/shared_preferences_provider.dart';
import '../../../core/theme/theme_engine_provider.dart';
import '../../../core/theme/theme_palettes.dart';
import '../../alarms/domain/alarm_preset.dart';
import '../../alarms/domain/reminder_offset.dart';

import '../../notes/data/notes_repository.dart';
import '../../../data/local/database.dart';
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
  late final _noteController = TextEditingController();

  late DateTime _start;
  late DateTime _end;
  late bool _isAllDay;
  String? _colorId;
  late Set<ReminderOffset> _selectedOffsets;
  AlarmPreset? _alarmPreset;
  bool _isSaving = false;
  bool _descriptionPreviewMode = false;

  bool get _isEditing => widget.existingEvent != null;
  String? get _eventId => widget.existingEvent?.id;

  @override
  void initState() {
    super.initState();
    final event = widget.existingEvent;
    final day = widget.initialDay ?? DateTime.now();
    _start = (event?.start ?? DateTime(day.year, day.month, day.day, 9)).toLocal();
    _end = (event?.end ?? _start.add(const Duration(hours: 1))).toLocal();
    _isAllDay = event?.isAllDay ?? false;
    _colorId = event?.colorId;
    _selectedOffsets = (event?.reminderMinutes ?? const []).map(ReminderOffset.fromMinutes).toSet();
    if (event != null) {
      final prefs = ref.read(sharedPreferencesProvider);
      final presetName = prefs.getString('event_alarm_preset_${event.id}');
      _alarmPreset = presetName != null ? AlarmPreset.values.byName(presetName) : (event.reminderMinutes.isNotEmpty ? AlarmPreset.light : null);
    } else {
      _alarmPreset = null;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = ref.watch(themeEngineProvider);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      constraints: const BoxConstraints(maxWidth: 560),
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

                // Header row
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

                // Title field
                TextField(
                  controller: _titleController,
                  autofocus: !_isEditing,
                  onChanged: (_) => setState(() {}),
                  style: TextStyle(color: palette.text, fontSize: 20, fontWeight: FontWeight.w600),
                  decoration: InputDecoration(
                    hintText: 'Title',
                    hintStyle: TextStyle(color: palette.text.withValues(alpha: 0.3), fontSize: 20, fontWeight: FontWeight.w600),
                    border: InputBorder.none,
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: palette.text.withValues(alpha: 0.15)),
                    ),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: palette.primary, width: 2),
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  textCapitalization: TextCapitalization.sentences,
                ),
                const SizedBox(height: 8),

                // Markdown Description field
                _buildDescriptionField(palette),

                const SizedBox(height: 16),

                // Date/Time Section (like the screenshot rows)
                _buildListSectionCard(palette, children: [
                  _buildIconRow(
                    icon: Icons.access_time_outlined,
                    palette: palette,
                    child: Row(
                      children: [
                        Material(
                          color: Colors.transparent,
                          child: SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text('All day', style: TextStyle(color: palette.text, fontWeight: FontWeight.w500)),
                            activeThumbColor: palette.primary,
                            value: _isAllDay,
                            onChanged: (value) => setState(() => _isAllDay = value),
                          ),
                        ),
                      ],
                    ),
                    isSwitch: true,
                  ),
                  const Divider(height: 1, thickness: 0.5),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        const SizedBox(width: 40),
                        Expanded(
                          child: _DatePickerButton(
                            value: _start,
                            showTime: !_isAllDay,
                            palette: palette,
                            onChanged: (v) => setState(() {
                              _start = v;
                              if (_end.isBefore(_start)) _end = _start.add(const Duration(hours: 1));
                            }),
                          ),
                        ),
                        Icon(Icons.arrow_forward, color: palette.text.withValues(alpha: 0.4), size: 16),
                        Expanded(
                          child: _DatePickerButton(
                            value: _end,
                            showTime: !_isAllDay,
                            palette: palette,
                            onChanged: (v) => setState(() => _end = v),
                            alignRight: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                ]),

                const SizedBox(height: 8),

                // Location
                _buildListSectionCard(palette, children: [
                  _buildIconRow(
                    icon: Icons.location_on_outlined,
                    palette: palette,
                    child: TextField(
                      controller: _locationController,
                      style: TextStyle(color: palette.text),
                      decoration: InputDecoration(
                        hintText: 'Location',
                        hintStyle: TextStyle(color: palette.text.withValues(alpha: 0.4)),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                ]),

                const SizedBox(height: 8),

                // Color, Alarm, Repeat
                _buildListSectionCard(palette, children: [
                  _buildIconRow(
                    icon: Icons.circle,
                    iconColor: _colorId != null
                        ? Color(GoogleEventColor.options.firstWhere((c) => c.id == _colorId, orElse: () => GoogleEventColor.options.first).hex)
                        : palette.primary,
                    palette: palette,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final color in GoogleEventColor.options)
                          GestureDetector(
                            onTap: () => setState(() => _colorId = color.id),
                            child: CircleAvatar(
                              backgroundColor: Color(color.hex),
                              radius: 14,
                              child: _colorId == color.id ? const Icon(Icons.check, color: Colors.white, size: 14) : null,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, thickness: 0.5),
                  _buildIconRow(
                    icon: Icons.notifications_outlined,
                    palette: palette,
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<AlarmPreset?>(
                        dropdownColor: palette.surface,
                        style: TextStyle(color: palette.text),
                        value: _alarmPreset,
                        isExpanded: true,
                        hint: Text('Don\'t notify', style: TextStyle(color: palette.text.withValues(alpha: 0.5))),
                        items: const [
                          DropdownMenuItem(value: null, child: Text('Don\'t notify')),
                          DropdownMenuItem(value: AlarmPreset.light, child: Text('Light — notification')),
                          DropdownMenuItem(value: AlarmPreset.medium, child: Text('Medium — full screen')),
                          DropdownMenuItem(value: AlarmPreset.strong, child: Text('Strong — long sound')),
                          DropdownMenuItem(value: AlarmPreset.constant, child: Text('Constant alert')),
                        ],
                        onChanged: (value) => setState(() => _alarmPreset = value),
                      ),
                    ),
                  ),
                  if (_alarmPreset != null) ...[
                    Padding(
                      padding: const EdgeInsets.only(left: 40, bottom: 8),
                      child: Wrap(
                        spacing: 8,
                        children: [
                          for (final offset in ReminderOffset.presets)
                            FilterChip(
                              label: Text(offset.label, style: TextStyle(fontSize: 12, color: _selectedOffsets.contains(offset) ? palette.background : palette.text)),
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
                    ),
                  ],
                  const Divider(height: 1, thickness: 0.5),
                  _buildIconRow(
                    icon: Icons.repeat,
                    palette: palette,
                    child: Text('Don\'t repeat', style: TextStyle(color: palette.text.withValues(alpha: 0.4))),
                  ),
                ]),

                const SizedBox(height: 8),

                // Notes section — linked to event
                _buildNotesSection(palette),

                const SizedBox(height: 16),

                // Save/Cancel buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: palette.text,
                          side: BorderSide(color: palette.text.withValues(alpha: 0.2)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
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
                          padding: const EdgeInsets.symmetric(vertical: 14),
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

  Widget _buildDescriptionField(AppPalette palette) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 180),
      decoration: BoxDecoration(
        color: palette.text.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.text.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Toggle bar
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 0),
            child: Row(
              children: [
                Icon(Icons.subject, size: 16, color: palette.text.withValues(alpha: 0.4)),
                const SizedBox(width: 6),
                Text('Description', style: TextStyle(color: palette.text.withValues(alpha: 0.5), fontSize: 12)),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(() => _descriptionPreviewMode = !_descriptionPreviewMode),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    _descriptionPreviewMode ? 'Edit' : 'Preview',
                    style: TextStyle(color: palette.primary, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          if (_descriptionPreviewMode)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: _descriptionController.text.trim().isEmpty
                  ? Text('No description', style: TextStyle(color: palette.text.withValues(alpha: 0.3), fontStyle: FontStyle.italic, fontSize: 13))
                  : MarkdownBody(
                      data: _descriptionController.text,
                      styleSheet: MarkdownStyleSheet(
                        p: TextStyle(color: palette.text, fontSize: 13),
                        h1: TextStyle(color: palette.text, fontSize: 18, fontWeight: FontWeight.bold),
                        h2: TextStyle(color: palette.text, fontSize: 16, fontWeight: FontWeight.bold),
                        h3: TextStyle(color: palette.text, fontSize: 14, fontWeight: FontWeight.w600),
                        strong: TextStyle(color: palette.text, fontWeight: FontWeight.bold),
                        em: TextStyle(color: palette.text, fontStyle: FontStyle.italic),
                        code: TextStyle(color: palette.primary, fontFamily: 'monospace', fontSize: 12),
                        blockquotePadding: const EdgeInsets.only(left: 12),
                        blockquoteDecoration: BoxDecoration(
                          border: Border(left: BorderSide(color: palette.primary, width: 3)),
                        ),
                      ),
                    ),
            )
          else
            Flexible(
              child: TextField(
                controller: _descriptionController,
                style: TextStyle(color: palette.text, fontSize: 13),
                maxLines: null,
                decoration: InputDecoration(
                  hintText: 'Add description (supports **markdown**)...',
                  hintStyle: TextStyle(color: palette.text.withValues(alpha: 0.3), fontSize: 13),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildNotesSection(AppPalette palette) {
    if (!_isEditing) {
      // When creating a new event, show a simple note field that saves after event creation
      return _buildListSectionCard(palette, children: [
        _buildIconRow(
          icon: Icons.notes_outlined,
          palette: palette,
          child: TextField(
            controller: _noteController,
            style: TextStyle(color: palette.text, fontSize: 13),
            maxLines: 3,
            minLines: 1,
            decoration: InputDecoration(
              hintText: 'Notes (linked to this event)',
              hintStyle: TextStyle(color: palette.text.withValues(alpha: 0.4), fontSize: 13),
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
      ]);
    }

    // When editing, show live note stream
    final notesAsync = ref.watch(
      StreamProvider<List<Note>>((ref) => ref.watch(notesRepositoryProvider).watchNotesByEventId(_eventId!)),
    );

    return _buildListSectionCard(palette, children: [
      _buildIconRow(
        icon: Icons.notes_outlined,
        palette: palette,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            notesAsync.when(
              data: (notes) {
                if (notes.isEmpty) return const SizedBox.shrink();
                return Column(
                  children: [
                    for (final note in notes)
                      _NoteItemTile(
                        note: note,
                        palette: palette,
                        onDelete: () => ref.read(notesRepositoryProvider).deleteNote(note.id),
                      ),
                    const Divider(height: 8, thickness: 0.5),
                  ],
                );
              },
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),
            TextField(
              controller: _noteController,
              style: TextStyle(color: palette.text, fontSize: 13),
              maxLines: 3,
              minLines: 1,
              decoration: InputDecoration(
                hintText: 'Add a linked note...',
                hintStyle: TextStyle(color: palette.text.withValues(alpha: 0.4), fontSize: 13),
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                suffixIcon: IconButton(
                  icon: Icon(Icons.send_outlined, size: 18, color: palette.primary),
                  onPressed: _saveNote,
                ),
              ),
            ),
          ],
        ),
      ),
    ]);
  }

  Widget _buildListSectionCard(AppPalette palette, {required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: palette.text.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.text.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  Widget _buildIconRow({
    required IconData icon,
    required AppPalette palette,
    required Widget child,
    Color? iconColor,
    bool isSwitch = false,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: isSwitch ? 0 : 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: iconColor ?? palette.text.withValues(alpha: 0.4)),
          const SizedBox(width: 12),
          Expanded(child: child),
        ],
      ),
    );
  }

  Future<void> _saveNote() async {
    final content = _noteController.text.trim();
    if (content.isEmpty || _eventId == null) return;
    await ref.read(notesRepositoryProvider).createNote(
      NotesCompanion.insert(
        title: 'Note',
        content: content,
        eventId: Value(_eventId),
      ),
    );
    _noteController.clear();
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
      reminderMinutes: _alarmPreset != null ? _selectedOffsets.map((o) => o.beforeDue.inMinutes).toList() : const [],
    );

    try {
      String savedId;
      if (_isEditing) {
        final updated = await repo.updateEvent(event, preset: _alarmPreset);
        savedId = updated.id;
      } else {
        final created = await repo.createEvent(event, preset: _alarmPreset);
        savedId = created.id;
      }

      // If user typed a note while creating, save it linked to this event
      final noteText = _noteController.text.trim();
      if (noteText.isNotEmpty && savedId.isNotEmpty) {
        await ref.read(notesRepositoryProvider).createNote(
          NotesCompanion.insert(
            title: 'Note',
            content: noteText,
            eventId: Value(savedId),
          ),
        );
      }

      ref.invalidate(monthEventsProvider(DateTime(_start.year, _start.month, 1)));
      ref.invalidate(monthEventsProvider(DateTime(_end.year, _end.month, 1)));
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}

class _NoteItemTile extends StatelessWidget {
  const _NoteItemTile({required this.note, required this.palette, required this.onDelete});

  final Note note;
  final AppPalette palette;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.sticky_note_2_outlined, size: 14, color: palette.text.withValues(alpha: 0.4)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(note.content, style: TextStyle(color: palette.text.withValues(alpha: 0.85), fontSize: 13)),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onDelete,
            child: Icon(Icons.close, size: 14, color: palette.text.withValues(alpha: 0.3)),
          ),
        ],
      ),
    );
  }
}

class _DatePickerButton extends StatelessWidget {
  const _DatePickerButton({
    required this.value,
    required this.showTime,
    required this.palette,
    required this.onChanged,
    this.alignRight = false,
  });

  final DateTime value;
  final bool showTime;
  final AppPalette palette;
  final ValueChanged<DateTime> onChanged;
  final bool alignRight;

  @override
  Widget build(BuildContext context) {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final weekday = days[(value.weekday - 1).clamp(0, 6)];
    final dateStr = '$weekday, ${months[value.month - 1]} ${value.day}';
    final timeStr = '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

    return GestureDetector(
      onTap: () async {
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
      child: Column(
        crossAxisAlignment: alignRight ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(dateStr, style: TextStyle(color: palette.text, fontWeight: FontWeight.w500, fontSize: 13)),
          if (showTime)
            Text(timeStr, style: TextStyle(color: palette.text.withValues(alpha: 0.7), fontSize: 13)),
        ],
      ),
    );
  }
}
