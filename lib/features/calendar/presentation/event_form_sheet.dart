import 'dart:ui';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/shared_preferences_provider.dart';
import '../../../core/theme/theme_engine_provider.dart';
import '../../../core/theme/theme_palettes.dart';
import '../../../data/local/database.dart';
import '../../../data/local/database_provider.dart';
import '../../alarms/domain/alarm_preset.dart';
import '../../alarms/domain/reminder_offset.dart';
import '../../notes/data/notes_repository.dart';
import '../../tags/presentation/tag_autocomplete_field.dart';
import '../application/calendar_providers.dart';
import '../domain/calendar_event.dart';

/// Google Calendar description hard cap (bytes before base64 encoding overhead).
/// Anything beyond this is stored locally in a Note only.
const _kGoogleDescriptionLimit = 8000;

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
        child: FadeTransition(opacity: animation, child: child),
      );
    },
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Recurrence model
// ─────────────────────────────────────────────────────────────────────────────

enum RecurrenceType { none, daily, weekly, monthly, yearly }
enum RepeatDuration { forever, specificTimes, until }
enum MonthlyRepeatMode { dayOfMonth, dayOfWeek, selectDates }

class RecurrenceConfig {
  const RecurrenceConfig({
    this.type = RecurrenceType.none,
    this.interval = 1,
    this.monthlyMode = MonthlyRepeatMode.dayOfMonth,
    this.duration = RepeatDuration.forever,
    this.repeatTimes = 10,
    this.untilDate,
  });

  final RecurrenceType type;
  final int interval;
  final MonthlyRepeatMode monthlyMode;
  final RepeatDuration duration;
  final int repeatTimes;
  final DateTime? untilDate;

  String get label {
    if (type == RecurrenceType.none) return 'Don\'t repeat';
    switch (type) {
      case RecurrenceType.daily:
        return interval == 1 ? 'Every day' : 'Every $interval days';
      case RecurrenceType.weekly:
        return interval == 1 ? 'Every week' : 'Every $interval weeks';
      case RecurrenceType.monthly:
        return interval == 1 ? 'Every month' : 'Every $interval months';
      case RecurrenceType.yearly:
        return interval == 1 ? 'Every year' : 'Every $interval years';
      case RecurrenceType.none:
        return 'Don\'t repeat';
    }
  }

  RecurrenceConfig copyWith({
    RecurrenceType? type,
    int? interval,
    MonthlyRepeatMode? monthlyMode,
    RepeatDuration? duration,
    int? repeatTimes,
    DateTime? untilDate,
  }) {
    return RecurrenceConfig(
      type: type ?? this.type,
      interval: interval ?? this.interval,
      monthlyMode: monthlyMode ?? this.monthlyMode,
      duration: duration ?? this.duration,
      repeatTimes: repeatTimes ?? this.repeatTimes,
      untilDate: untilDate ?? this.untilDate,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Main form widget
// ─────────────────────────────────────────────────────────────────────────────

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
  // Notes controller — holds full text (description + overflow). Initialized below.
  late final _notesController = TextEditingController();
  late final _locationController = TextEditingController(text: widget.existingEvent?.location);
  late final _inviteeController = TextEditingController();

  late DateTime _start;
  late DateTime _end;
  late bool _isAllDay;
  String? _colorId;
  late Set<ReminderOffset> _selectedOffsets;
  AlarmPreset? _alarmPreset;
  bool _isSaving = false;
  bool _notesPreviewMode = false;
  RecurrenceConfig _recurrence = const RecurrenceConfig();

  // Attendees & conference
  final List<String> _attendees = [];
  bool _addVideoConference = false;
  bool _sendInvites = false;

  // Tags assigned to this event
  final List<Tag> _assignedTags = [];

  // RSVP (only visible when editing an existing event with attendees)
  late RsvpStatus _rsvpStatus;

  bool get _isEditing => widget.existingEvent != null;
  String? get _eventId => widget.existingEvent?.id;

  GoogleEventColor? get _selectedColor => _colorId == null
      ? null
      : GoogleEventColor.options.where((c) => c.id == _colorId).firstOrNull;

  @override
  void initState() {
    super.initState();
    final event = widget.existingEvent;
    final day = widget.initialDay ?? DateTime.now();
    _start = (event?.start ?? DateTime(day.year, day.month, day.day, 9)).toLocal();
    _end = (event?.end ?? _start.add(const Duration(hours: 1))).toLocal();
    _isAllDay = event?.isAllDay ?? false;
    _colorId = event?.colorId;
    _addVideoConference = event?.hasVideoConference ?? false;
    _rsvpStatus = event?.selfResponseStatus ?? RsvpStatus.needsAction;

    if (event != null) {
      _attendees.addAll(event.attendees);

      // Load merged notes: event.description is the Google-synced part;
      // the local Note (linked by eventId) may contain the full overflow text.
      // We'll load the full local note in initState via an async call.
      _notesController.text = event.description ?? '';
      _loadLinkedNote();

      final prefs = ref.read(sharedPreferencesProvider);
      final presetName = prefs.getString('event_alarm_preset_${event.id}');
      _alarmPreset = presetName != null
          ? AlarmPreset.values.byName(presetName)
          : (event.reminderMinutes.isNotEmpty ? AlarmPreset.light : AlarmPreset.light);
      _selectedOffsets = (event.reminderMinutes.isNotEmpty
              ? event.reminderMinutes.map(ReminderOffset.fromMinutes)
              : [ReminderOffset.atTime, ReminderOffset.thirtyMinBefore])
          .toSet();
    } else {
      _alarmPreset = AlarmPreset.light;
      _selectedOffsets = {ReminderOffset.atTime, ReminderOffset.thirtyMinBefore};
    }
  }

  Future<void> _loadLinkedNote() async {
    if (_eventId == null) return;
    final repo = ref.read(notesRepositoryProvider);
    final notes = await repo.watchNotesByEventId(_eventId!).first;
    if (notes.isNotEmpty && mounted) {
      // The local Note has the full content (Google description may be truncated)
      final note = notes.first;
      if (note.content.length > (_notesController.text.length)) {
        _notesController.text = note.content;
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    _locationController.dispose();
    _inviteeController.dispose();
    super.dispose();
  }

  void _onTagSelected(Tag tag) {
    if (_assignedTags.any((t) => t.id == tag.id)) return;
    setState(() {
      _assignedTags.add(tag);
      // Auto-apply tag defaults
      if (tag.defaultColorHex != null && _colorId == null) {
        // Try to match to Google color by hex
        final match = GoogleEventColor.options.where(
          (c) => '#${c.hex.toRadixString(16).substring(2).toUpperCase()}' == tag.defaultColorHex!.toUpperCase(),
        ).firstOrNull;
        if (match != null) _colorId = match.id;
      }
      if (tag.defaultAlarmPreset != null && _alarmPreset == null) {
        try {
          _alarmPreset = AlarmPreset.values.byName(tag.defaultAlarmPreset!);
        } catch (_) {}
      }
    });
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
          BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 40, offset: const Offset(0, 20)),
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

                // ── Title + Color + Delete ────────────────────────────────
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: TagAutocompleteField(
                        controller: _titleController,
                        autofocus: !_isEditing,
                        onChanged: (_) => setState(() {}),
                        onTagSelected: _onTagSelected,
                        style: TextStyle(color: palette.text, fontSize: 22, fontWeight: FontWeight.bold),
                        decoration: InputDecoration(
                          hintText: _isEditing ? 'Edit event' : 'New event',
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
                    _ColorPickerButton(
                      selectedColor: _selectedColor,
                      palette: palette,
                      onChanged: (id) => setState(() => _colorId = id),
                    ),
                    if (_isEditing) ...[
                      const SizedBox(width: 4),
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
                  ],
                ),
                const SizedBox(height: 10),

                // ── 1. Merged Notes field (description + local note) ──────
                _buildNotesField(palette),

                const SizedBox(height: 14),

                // ── Assigned tags chips ───────────────────────────────────
                if (_assignedTags.isNotEmpty) ...[
                  Wrap(
                    spacing: 6,
                    children: [
                      for (final tag in _assignedTags)
                        Chip(
                          label: Text('#${tag.name}', style: const TextStyle(fontSize: 12)),
                          backgroundColor: _parseColor(tag.colorHex).withValues(alpha: 0.2),
                          side: BorderSide.none,
                          deleteIcon: const Icon(Icons.close, size: 12),
                          onDeleted: () => setState(() => _assignedTags.removeWhere((t) => t.id == tag.id)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],

                // ── Date/Time ─────────────────────────────────────────────
                _buildListSectionCard(palette, children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                    child: Row(
                      children: [
                        Icon(Icons.access_time_outlined, size: 18, color: palette.text.withValues(alpha: 0.4)),
                        const SizedBox(width: 12),
                        Expanded(child: Text('All day', style: TextStyle(color: palette.text, fontWeight: FontWeight.w500))),
                        Switch(value: _isAllDay, activeThumbColor: palette.primary, onChanged: (v) => setState(() => _isAllDay = v)),
                      ],
                    ),
                  ),
                  const Divider(height: 1, thickness: 0.5),
                  _buildDateTimeRow(palette: palette, label: 'Starts', value: _start,
                    onDateChanged: (d) => setState(() {
                      _start = DateTime(d.year, d.month, d.day, _start.hour, _start.minute);
                      if (_end.isBefore(_start)) _end = _start.add(const Duration(hours: 1));
                    }),
                    onTimeChanged: (t) => setState(() {
                      _start = DateTime(_start.year, _start.month, _start.day, t.hour, t.minute);
                      if (_end.isBefore(_start)) _end = _start.add(const Duration(hours: 1));
                    }),
                  ),
                  const Divider(height: 1, thickness: 0.5),
                  _buildDateTimeRow(palette: palette, label: 'Ends', value: _end,
                    onDateChanged: (d) => setState(() => _end = DateTime(d.year, d.month, d.day, _end.hour, _end.minute)),
                    onTimeChanged: (t) => setState(() => _end = DateTime(_end.year, _end.month, _end.day, t.hour, t.minute)),
                  ),
                ]),

                const SizedBox(height: 8),

                // ── Location + Video + Invitees ───────────────────────────
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
                  const Divider(height: 1, thickness: 0.5),
                  // ── 3. Google Meet toggle ─────────────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                    child: Row(
                      children: [
                        Icon(Icons.videocam_outlined, size: 18, color: _addVideoConference ? palette.primary : palette.text.withValues(alpha: 0.4)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('Google Meet', style: TextStyle(color: palette.text, fontWeight: FontWeight.w500)),
                              if (_isEditing && widget.existingEvent!.videoConferenceLink != null)
                                Text(
                                  widget.existingEvent!.videoConferenceLink!,
                                  style: TextStyle(color: palette.primary, fontSize: 11),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                        Switch(
                          value: _addVideoConference,
                          activeThumbColor: palette.primary,
                          onChanged: (v) => setState(() => _addVideoConference = v),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, thickness: 0.5),
                  // ── 3. Invitees field ──────────────────────────────────
                  _buildInviteesSection(palette),
                ]),

                const SizedBox(height: 8),

                // ── Alarm + Color + Repeat ────────────────────────────────
                _buildListSectionCard(palette, children: [
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
                        onChanged: (value) => setState(() {
                          _alarmPreset = value;
                          if (value != null && _selectedOffsets.isEmpty) {
                            _selectedOffsets = {ReminderOffset.atTime, ReminderOffset.thirtyMinBefore};
                          }
                        }),
                      ),
                    ),
                  ),
                  if (_alarmPreset != null) ...[
                    Padding(
                      padding: const EdgeInsets.only(left: 40, right: 12, bottom: 10),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final offset in ReminderOffset.presets)
                            FilterChip(
                              label: Text(offset.label, style: TextStyle(fontSize: 12, color: _selectedOffsets.contains(offset) ? palette.background : palette.text)),
                              selected: _selectedOffsets.contains(offset),
                              selectedColor: palette.primary,
                              backgroundColor: palette.surface,
                              side: BorderSide(color: palette.text.withValues(alpha: 0.15)),
                              onSelected: (sel) => setState(() {
                                if (sel) _selectedOffsets.add(offset);
                                else _selectedOffsets.remove(offset);
                              }),
                            ),
                        ],
                      ),
                    ),
                  ],
                  const Divider(height: 1, thickness: 0.5),
                  InkWell(
                    borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(12), bottomRight: Radius.circular(12)),
                    onTap: () => _showRepeatDialog(context, palette),
                    child: _buildIconRow(
                      icon: Icons.repeat,
                      palette: palette,
                      child: Row(
                        children: [
                          Expanded(child: Text(_recurrence.label, style: TextStyle(color: _recurrence.type == RecurrenceType.none ? palette.text.withValues(alpha: 0.4) : palette.primary))),
                          Icon(Icons.chevron_right, size: 16, color: palette.text.withValues(alpha: 0.3)),
                        ],
                      ),
                    ),
                  ),
                ]),

                // ── 4+. RSVP (editing existing events only) ───────────────
                if (_isEditing) ...[
                  const SizedBox(height: 8),
                  _buildRsvpSection(palette),
                ],

                const SizedBox(height: 16),

                // ── Save/Cancel ───────────────────────────────────────────
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

  // ── 1. Merged Notes field ─────────────────────────────────────────────────

  Widget _buildNotesField(AppPalette palette) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 200),
      decoration: BoxDecoration(
        color: palette.text.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.text.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header bar
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 0),
            child: Row(
              children: [
                Icon(Icons.notes_outlined, size: 16, color: palette.text.withValues(alpha: 0.4)),
                const SizedBox(width: 6),
                Text('Notes', style: TextStyle(color: palette.text.withValues(alpha: 0.5), fontSize: 12)),
                // Show overflow indicator if text > Google limit
                if (_notesController.text.length > _kGoogleDescriptionLimit) ...[
                  const SizedBox(width: 6),
                  Tooltip(
                    message: 'Text over ${_kGoogleDescriptionLimit} chars is stored locally only (not synced to Google)',
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.cloud_off_outlined, size: 12, color: palette.text.withValues(alpha: 0.4)),
                        const SizedBox(width: 2),
                        Text('overflow local', style: TextStyle(color: palette.text.withValues(alpha: 0.35), fontSize: 10)),
                      ],
                    ),
                  ),
                ],
                const Spacer(),
                TextButton(
                  onPressed: () => setState(() => _notesPreviewMode = !_notesPreviewMode),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    _notesPreviewMode ? 'Edit' : 'Preview',
                    style: TextStyle(color: palette.primary, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          if (_notesPreviewMode)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: _notesController.text.trim().isEmpty
                  ? Text('No notes', style: TextStyle(color: palette.text.withValues(alpha: 0.3), fontStyle: FontStyle.italic, fontSize: 13))
                  : MarkdownBody(
                      data: _notesController.text,
                      styleSheet: MarkdownStyleSheet(
                        p: TextStyle(color: palette.text, fontSize: 13),
                        h1: TextStyle(color: palette.text, fontSize: 18, fontWeight: FontWeight.bold),
                        h2: TextStyle(color: palette.text, fontSize: 16, fontWeight: FontWeight.bold),
                        strong: TextStyle(color: palette.text, fontWeight: FontWeight.bold),
                        em: TextStyle(color: palette.text, fontStyle: FontStyle.italic),
                        code: TextStyle(color: palette.primary, fontFamily: 'monospace', fontSize: 12),
                      ),
                    ),
            )
          else
            Flexible(
              child: TextField(
                controller: _notesController,
                style: TextStyle(color: palette.text, fontSize: 13),
                maxLines: null,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Add notes (syncs to Google, supports **markdown**)...',
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

  // ── 3. Invitees ───────────────────────────────────────────────────────────

  Widget _buildInviteesSection(AppPalette palette) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.people_outline, size: 18, color: palette.text.withValues(alpha: 0.4)),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _inviteeController,
                  style: TextStyle(color: palette.text, fontSize: 13),
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    hintText: 'Add guests by email...',
                    hintStyle: TextStyle(color: palette.text.withValues(alpha: 0.4), fontSize: 13),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    suffixIcon: IconButton(
                      icon: Icon(Icons.add, size: 18, color: palette.primary),
                      onPressed: _addInvitee,
                    ),
                  ),
                  onSubmitted: (_) => _addInvitee(),
                ),
              ),
            ],
          ),
          if (_attendees.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final email in _attendees)
                  Chip(
                    avatar: CircleAvatar(
                      radius: 10,
                      backgroundColor: palette.primary.withValues(alpha: 0.2),
                      child: Text(email[0].toUpperCase(), style: TextStyle(fontSize: 10, color: palette.primary, fontWeight: FontWeight.bold)),
                    ),
                    label: Text(email, style: TextStyle(fontSize: 12, color: palette.text)),
                    backgroundColor: palette.text.withValues(alpha: 0.06),
                    side: BorderSide.none,
                    deleteIcon: Icon(Icons.close, size: 12, color: palette.text.withValues(alpha: 0.5)),
                    onDeleted: () => setState(() => _attendees.remove(email)),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            // Send invites toggle
            Row(
              children: [
                const SizedBox(width: 30),
                Icon(Icons.send_outlined, size: 14, color: _sendInvites ? palette.primary : palette.text.withValues(alpha: 0.4)),
                const SizedBox(width: 8),
                Expanded(child: Text('Send invitation emails', style: TextStyle(color: palette.text.withValues(alpha: 0.7), fontSize: 13))),
                Switch(
                  value: _sendInvites,
                  activeThumbColor: palette.primary,
                  onChanged: (v) => setState(() => _sendInvites = v),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  void _addInvitee() {
    final email = _inviteeController.text.trim();
    if (email.isEmpty) return;
    // Basic email validation
    if (!email.contains('@') || !email.contains('.')) return;
    if (_attendees.contains(email)) {
      _inviteeController.clear();
      return;
    }
    setState(() {
      _attendees.add(email);
      _inviteeController.clear();
    });
  }

  // ── RSVP ──────────────────────────────────────────────────────────────────

  Widget _buildRsvpSection(AppPalette palette) {
    final options = [
      (RsvpStatus.accepted, Icons.check_circle_outline, 'Yes'),
      (RsvpStatus.acceptedVirtually, Icons.videocam_outlined, 'Yes, virtually'),
      (RsvpStatus.tentative, Icons.help_outline, 'Maybe'),
      (RsvpStatus.declined, Icons.cancel_outlined, 'No'),
    ];

    return _buildListSectionCard(palette, children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.how_to_reg_outlined, size: 18, color: palette.text.withValues(alpha: 0.4)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Attending?', style: TextStyle(color: palette.text, fontWeight: FontWeight.w500, fontSize: 13)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final (status, icon, label) in options)
                        _RsvpChip(
                          label: label,
                          icon: icon,
                          selected: _rsvpStatus == status,
                          palette: palette,
                          onTap: () => setState(() => _rsvpStatus = status),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ]);
  }

  // ── Date/time row ─────────────────────────────────────────────────────────

  Widget _buildDateTimeRow({
    required AppPalette palette,
    required String label,
    required DateTime value,
    required ValueChanged<DateTime> onDateChanged,
    required ValueChanged<TimeOfDay> onTimeChanged,
  }) {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final weekday = days[(value.weekday - 1).clamp(0, 6)];
    final dateStr = '$weekday, ${months[value.month - 1]} ${value.day}';
    final timeStr = '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          SizedBox(width: 44, child: Text(label, style: TextStyle(color: palette.text.withValues(alpha: 0.5), fontSize: 12))),
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () async {
              final date = await showDatePicker(
                context: context,
                initialDate: value,
                firstDate: DateTime.now().subtract(const Duration(days: 365 * 2)),
                lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
              );
              if (date != null) onDateChanged(date);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Text(dateStr, style: TextStyle(color: palette.text, fontWeight: FontWeight.w600, fontSize: 13)),
            ),
          ),
          if (!_isAllDay) ...[
            const SizedBox(width: 6),
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () async {
                final time = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay.fromDateTime(value),
                );
                if (time != null) onTimeChanged(time);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: palette.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(timeStr, style: TextStyle(color: palette.primary, fontWeight: FontWeight.w600, fontSize: 13)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Repeat dialog ─────────────────────────────────────────────────────────

  Future<void> _showRepeatDialog(BuildContext context, AppPalette palette) async {
    final result = await showDialog<RecurrenceConfig>(
      context: context,
      builder: (ctx) => _RepeatDialog(initial: _recurrence, startDate: _start, palette: palette),
    );
    if (result != null) setState(() => _recurrence = result);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Widget _buildListSectionCard(AppPalette palette, {required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: palette.text.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.text.withValues(alpha: 0.08)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }

  Widget _buildIconRow({required IconData icon, required AppPalette palette, required Widget child, Color? iconColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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

  Color _parseColor(String hex) {
    try {
      final c = hex.replaceAll('#', '');
      return Color(int.parse('FF$c', radix: 16));
    } catch (_) {
      return const Color(0xFFD89B3C);
    }
  }

  // ── Save ──────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    setState(() => _isSaving = true);
    final repo = ref.read(calendarRepositoryProvider);
    final fullNotes = _notesController.text.trim();
    final location = _locationController.text.trim();

    // Truncate description to Google's limit; overflow goes to local note only
    final googleDescription = fullNotes.length > _kGoogleDescriptionLimit
        ? fullNotes.substring(0, _kGoogleDescriptionLimit)
        : (fullNotes.isEmpty ? null : fullNotes);

    final event = CalendarEvent(
      id: widget.existingEvent?.id ?? '',
      calendarId: widget.existingEvent?.calendarId ?? 'primary',
      title: _titleController.text.trim(),
      description: googleDescription,
      location: location.isEmpty ? null : location,
      start: _start,
      end: _end,
      isAllDay: _isAllDay,
      colorId: _colorId,
      reminderMinutes: _alarmPreset != null ? _selectedOffsets.map((o) => o.beforeDue.inMinutes).toList() : const [],
      attendees: _attendees,
      hasVideoConference: _addVideoConference,
    );

    try {
      String savedId;
      if (_isEditing) {
        final updated = await repo.updateEvent(event,
          preset: _alarmPreset,
          sendInvites: _sendInvites,
          addVideoConference: _addVideoConference,
        );
        savedId = updated.id;

        // RSVP if changed
        if (_rsvpStatus != widget.existingEvent!.selfResponseStatus) {
          await repo.respondToEvent(event, _rsvpStatus, sendInvites: _sendInvites);
        }
      } else {
        final created = await repo.createEvent(event,
          preset: _alarmPreset,
          sendInvites: _sendInvites,
          addVideoConference: _addVideoConference,
        );
        savedId = created.id;
      }

      // Save/update local note with FULL content (including overflow beyond Google limit)
      if (fullNotes.isNotEmpty && savedId.isNotEmpty) {
        final notesRepo = ref.read(notesRepositoryProvider);
        final existing = await notesRepo.watchNotesByEventId(savedId).first;
        if (existing.isEmpty) {
          await notesRepo.createNote(NotesCompanion.insert(
            title: _titleController.text.trim().isEmpty ? 'Event note' : _titleController.text.trim(),
            content: fullNotes,
            eventId: Value(savedId),
          ));
        } else {
          await notesRepo.updateNote(NotesCompanion(
            id: Value(existing.first.id),
            title: Value(_titleController.text.trim().isEmpty ? 'Event note' : _titleController.text.trim()),
            content: Value(fullNotes),
            eventId: Value(savedId),
            updatedAt: Value(DateTime.now()),
          ));
        }
      }

      // Assign tags to event in local DB
      for (final tag in _assignedTags) {
        await repo.assignTag(savedId, tag.id);
      }

      ref.invalidate(monthEventsProvider(DateTime(_start.year, _start.month, 1)));
      ref.invalidate(monthEventsProvider(DateTime(_end.year, _end.month, 1)));
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// RSVP chip
// ─────────────────────────────────────────────────────────────────────────────

class _RsvpChip extends StatelessWidget {
  const _RsvpChip({required this.label, required this.icon, required this.selected, required this.palette, required this.onTap});

  final String label;
  final IconData icon;
  final bool selected;
  final AppPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? palette.primary : palette.text.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? palette.primary : palette.text.withValues(alpha: 0.15)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: selected ? palette.background : palette.text.withValues(alpha: 0.6)),
            const SizedBox(width: 5),
            Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: selected ? palette.background : palette.text)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Color picker button
// ─────────────────────────────────────────────────────────────────────────────

class _ColorPickerButton extends StatelessWidget {
  const _ColorPickerButton({required this.selectedColor, required this.palette, required this.onChanged});

  final GoogleEventColor? selectedColor;
  final AppPalette palette;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final dotColor = selectedColor != null ? Color(selectedColor!.hex) : palette.primary;
    return PopupMenuButton<String?>(
      color: palette.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      offset: const Offset(0, 36),
      tooltip: 'Event color',
      itemBuilder: (ctx) => [
        PopupMenuItem<String?>(
          value: null,
          child: _ColorMenuItem(color: palette.primary, label: 'Calendar default', selected: selectedColor == null, palette: palette),
        ),
        for (final c in GoogleEventColor.options)
          PopupMenuItem<String?>(
            value: c.id,
            child: _ColorMenuItem(color: Color(c.hex), label: c.label, selected: selectedColor?.id == c.id, palette: palette),
          ),
      ],
      onSelected: onChanged,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: dotColor.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: dotColor.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(radius: 6, backgroundColor: dotColor),
            const SizedBox(width: 5),
            Text(selectedColor?.label ?? 'Color', style: TextStyle(color: dotColor, fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(width: 3),
            Icon(Icons.expand_more, color: dotColor, size: 14),
          ],
        ),
      ),
    );
  }
}

class _ColorMenuItem extends StatelessWidget {
  const _ColorMenuItem({required this.color, required this.label, required this.selected, required this.palette});

  final Color color;
  final String label;
  final bool selected;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(radius: 10, backgroundColor: color, child: selected ? const Icon(Icons.check, color: Colors.white, size: 12) : null),
        const SizedBox(width: 12),
        Text(label, style: TextStyle(color: palette.text, fontSize: 14)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Repeat dialog
// ─────────────────────────────────────────────────────────────────────────────

class _RepeatDialog extends StatefulWidget {
  const _RepeatDialog({required this.initial, required this.startDate, required this.palette});

  final RecurrenceConfig initial;
  final DateTime startDate;
  final AppPalette palette;

  @override
  State<_RepeatDialog> createState() => _RepeatDialogState();
}

class _RepeatDialogState extends State<_RepeatDialog> {
  late RecurrenceConfig _config;
  late final _timesController = TextEditingController(text: widget.initial.repeatTimes.toString());

  @override
  void initState() {
    super.initState();
    _config = widget.initial;
  }

  @override
  void dispose() {
    _timesController.dispose();
    super.dispose();
  }

  String _ordinal(int n) {
    if (n >= 11 && n <= 13) return '${n}th';
    switch (n % 10) {
      case 1: return '${n}st';
      case 2: return '${n}nd';
      case 3: return '${n}rd';
      default: return '${n}th';
    }
  }

  String _weekdayName(int wd) => ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'][wd - 1];
  String _nthWeekdayOfMonth(DateTime d) => '${_ordinal(((d.day - 1) ~/ 7) + 1)} ${_weekdayName(d.weekday)}';

  Widget _radioOption(RecurrenceType type, String label, {Widget? extra}) {
    final p = widget.palette;
    final selected = _config.type == type;
    return Column(
      children: [
        InkWell(
          onTap: () => setState(() => _config = _config.copyWith(type: type)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: selected ? p.primary : p.text.withValues(alpha: 0.4), size: 20),
                const SizedBox(width: 14),
                Text(label, style: TextStyle(color: p.text, fontSize: 15)),
              ],
            ),
          ),
        ),
        if (selected && extra != null)
          Padding(padding: const EdgeInsets.only(left: 50, right: 16, bottom: 12), child: extra),
        Divider(height: 1, thickness: 0.5, indent: 50, color: p.text.withValues(alpha: 0.1)),
      ],
    );
  }

  Widget _durationRadio(RepeatDuration dur, String label, {Widget? extra}) {
    final p = widget.palette;
    final selected = _config.duration == dur;
    return InkWell(
      onTap: () => setState(() => _config = _config.copyWith(duration: dur)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: selected ? p.primary : p.text.withValues(alpha: 0.4), size: 20),
                const SizedBox(width: 14),
                Text(label, style: TextStyle(color: p.text, fontSize: 15)),
              ],
            ),
            if (selected && extra != null) ...[
              const SizedBox(height: 10),
              Padding(padding: const EdgeInsets.only(left: 34), child: extra),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final d = widget.startDate;

    Widget? monthExtra;
    if (_config.type == RecurrenceType.monthly) {
      monthExtra = Wrap(spacing: 8, children: [
        _monthModeChip('On the ${_ordinal(d.day)}', MonthlyRepeatMode.dayOfMonth),
        _monthModeChip('On the ${_nthWeekdayOfMonth(d)}', MonthlyRepeatMode.dayOfWeek),
        _monthModeChip('Select dates', MonthlyRepeatMode.selectDates),
      ]);
    }

    return Dialog(
      backgroundColor: p.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 680),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
              child: Row(
                children: [
                  IconButton(icon: Icon(Icons.arrow_back, color: p.text), onPressed: () => Navigator.pop(context)),
                  const SizedBox(width: 4),
                  Text('Repeat', style: TextStyle(color: p.text, fontSize: 20, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            if (_config.type != RecurrenceType.none)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Text(_buildSummary(d), style: TextStyle(color: p.text.withValues(alpha: 0.6), fontSize: 13)),
              ),
            const SizedBox(height: 4),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(color: p.text.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(14)),
                      child: Column(
                        children: [
                          _radioOption(RecurrenceType.none, 'Don\'t repeat'),
                          _radioOption(RecurrenceType.daily, 'Every ${_config.type == RecurrenceType.daily ? _config.interval : 1} day'),
                          _radioOption(RecurrenceType.weekly, 'Every ${_config.type == RecurrenceType.weekly ? _config.interval : 1} week'),
                          _radioOption(RecurrenceType.monthly, 'Every ${_config.type == RecurrenceType.monthly ? _config.interval : 1} month', extra: monthExtra),
                          _radioOption(RecurrenceType.yearly, 'Every ${_config.type == RecurrenceType.yearly ? _config.interval : 1} year'),
                        ],
                      ),
                    ),
                    if (_config.type != RecurrenceType.none) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                        child: Text('Duration', style: TextStyle(color: p.text.withValues(alpha: 0.5), fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(color: p.text.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(14)),
                        child: Column(
                          children: [
                            _durationRadio(RepeatDuration.forever, 'Forever'),
                            Divider(height: 1, thickness: 0.5, indent: 50, color: p.text.withValues(alpha: 0.1)),
                            _durationRadio(
                              RepeatDuration.specificTimes,
                              'Specific number of times',
                              extra: _config.duration == RepeatDuration.specificTimes
                                  ? SizedBox(
                                      width: 100,
                                      child: TextField(
                                        controller: _timesController,
                                        keyboardType: TextInputType.number,
                                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                        style: TextStyle(color: p.text),
                                        decoration: InputDecoration(
                                          hintText: '10',
                                          suffix: Text(' times', style: TextStyle(color: p.text.withValues(alpha: 0.5))),
                                          isDense: true,
                                          border: UnderlineInputBorder(borderSide: BorderSide(color: p.primary)),
                                        ),
                                        onChanged: (v) {
                                          final n = int.tryParse(v);
                                          if (n != null && n > 0) _config = _config.copyWith(repeatTimes: n);
                                        },
                                      ),
                                    )
                                  : null,
                            ),
                            Divider(height: 1, thickness: 0.5, indent: 50, color: p.text.withValues(alpha: 0.1)),
                            _durationRadio(
                              RepeatDuration.until,
                              'Until',
                              extra: _config.duration == RepeatDuration.until
                                  ? InkWell(
                                      onTap: () async {
                                        final date = await showDatePicker(
                                          context: context,
                                          initialDate: _config.untilDate ?? DateTime.now().add(const Duration(days: 30)),
                                          firstDate: DateTime.now(),
                                          lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
                                        );
                                        if (date != null) setState(() => _config = _config.copyWith(untilDate: date));
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                        decoration: BoxDecoration(color: p.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                                        child: Text(
                                          _config.untilDate != null
                                              ? '${_config.untilDate!.year}-${_config.untilDate!.month.toString().padLeft(2,'0')}-${_config.untilDate!.day.toString().padLeft(2,'0')}'
                                              : 'Pick a date',
                                          style: TextStyle(color: p.primary, fontWeight: FontWeight.w600, fontSize: 13),
                                        ),
                                      ),
                                    )
                                  : null,
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: p.primary,
                  foregroundColor: p.background,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () => Navigator.pop(context, _config),
                child: const Text('Done', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _monthModeChip(String label, MonthlyRepeatMode mode) {
    final p = widget.palette;
    final selected = _config.monthlyMode == mode;
    return ActionChip(
      label: Text(label, style: TextStyle(fontSize: 12, color: selected ? p.background : p.text, fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
      backgroundColor: selected ? p.primary : p.text.withValues(alpha: 0.08),
      side: BorderSide.none,
      onPressed: () => setState(() => _config = _config.copyWith(monthlyMode: mode)),
    );
  }

  String _buildSummary(DateTime d) {
    switch (_config.type) {
      case RecurrenceType.daily: return 'This event will repeat every ${_config.interval} day${_config.interval == 1 ? '' : 's'}.';
      case RecurrenceType.weekly: return 'This event will repeat every ${_config.interval} week${_config.interval == 1 ? '' : 's'}.';
      case RecurrenceType.monthly:
        if (_config.monthlyMode == MonthlyRepeatMode.dayOfMonth) return 'This event will repeat on the ${_ordinal(d.day)} of every month.';
        if (_config.monthlyMode == MonthlyRepeatMode.dayOfWeek) return 'This event will repeat on the ${_nthWeekdayOfMonth(d)} of every month.';
        return 'This event will repeat on selected dates every month.';
      case RecurrenceType.yearly: return 'This event will repeat every year.';
      case RecurrenceType.none: return '';
    }
  }
}
