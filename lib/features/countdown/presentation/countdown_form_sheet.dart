import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/theme_engine_provider.dart';
import '../../../data/local/database.dart';
import '../application/countdown_providers.dart';
import '../domain/countdown_type.dart';

Future<void> showCountdownFormSheet(
  BuildContext context, {
  required CountdownType type,
  Countdown? existingCountdown,
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
              child: CountdownFormSheet(type: type, existingCountdown: existingCountdown),
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

class CountdownFormSheet extends ConsumerStatefulWidget {
  const CountdownFormSheet({
    required this.type,
    this.existingCountdown,
    this.unifiedHeader,
    super.key,
  });

  final CountdownType type;
  final Countdown? existingCountdown;
  final Widget? unifiedHeader;

  @override
  ConsumerState<CountdownFormSheet> createState() => _CountdownFormSheetState();
}

class _CountdownFormSheetState extends ConsumerState<CountdownFormSheet> {
  late final _titleController = TextEditingController(
    text: widget.existingCountdown?.title,
  );
  late DateTime _targetDate =
      widget.existingCountdown?.targetDate ?? DateTime.now();
  late bool _showAge = widget.existingCountdown?.showAge ?? false;
  late bool _isYearly =
      widget.existingCountdown?.isYearly ?? widget.type.isYearlyByDefault;
  bool _isSaving = false;

  bool get _isEditing => widget.existingCountdown != null;

  @override
  void dispose() {
    _titleController.dispose();
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
                        controller: _titleController,
                        autofocus: !_isEditing,
                        onChanged: (_) => setState(() {}),
                        style: TextStyle(color: palette.text, fontSize: 22, fontWeight: FontWeight.bold),
                        decoration: InputDecoration(
                          hintText: 'Countdown Title',
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
                    Icon(Icons.hourglass_bottom, color: palette.primary),
                    if (_isEditing) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        icon: Icon(Icons.delete_outline, color: Colors.redAccent.withValues(alpha: 0.8)),
                        onPressed: () async {
                          await ref.read(countdownRepositoryProvider).deleteCountdown(widget.existingCountdown!.id);
                          if (context.mounted) Navigator.pop(context);
                        },
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 16),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: palette.text.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${_targetDate.year}-${_targetDate.month.toString().padLeft(2, '0')}-${_targetDate.day.toString().padLeft(2, '0')}',
                          style: TextStyle(color: palette.text, fontWeight: FontWeight.w500),
                        ),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(foregroundColor: palette.primary),
                        onPressed: _pickDate, 
                        child: const Text('Set date', style: TextStyle(fontWeight: FontWeight.bold))
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (widget.type.supportsAge || widget.type == CountdownType.custom)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: palette.text.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        if (widget.type.supportsAge)
                          Material(
                            color: Colors.transparent,
                            child: SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text('Show age', style: TextStyle(color: palette.text, fontWeight: FontWeight.w500)),
                              subtitle: Text(
                                _showAge
                                    ? 'The year above is used to calculate age'
                                    : 'Year is ignored — only month and day count',
                                style: TextStyle(color: palette.text.withValues(alpha: 0.6), fontSize: 12),
                              ),
                              activeThumbColor: palette.primary,
                              value: _showAge,
                              onChanged: (value) => setState(() => _showAge = value),
                            ),
                          ),
                        if (widget.type == CountdownType.custom)
                          Material(
                            color: Colors.transparent,
                            child: SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text('Repeats yearly', style: TextStyle(color: palette.text, fontWeight: FontWeight.w500)),
                              activeThumbColor: palette.primary,
                              value: _isYearly,
                              onChanged: (value) => setState(() => _isYearly = value),
                            ),
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                Text(
                  'Alerts: 3 days before and on the day',
                  style: TextStyle(color: palette.text.withValues(alpha: 0.5), fontSize: 12),
                  textAlign: TextAlign.center,
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
                            : Text(_isEditing ? 'Save' : 'Add', style: const TextStyle(fontWeight: FontWeight.bold)),
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

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _targetDate,
      firstDate: DateTime(1900),
      lastDate: DateTime.now().add(const Duration(days: 365 * 100)),
    );
    if (date != null) setState(() => _targetDate = date);
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    final repo = ref.read(countdownRepositoryProvider);
    try {
      if (_isEditing) {
        await repo.updateCountdown(
          widget.existingCountdown!.id,
          title: _titleController.text.trim(),
          targetDate: _targetDate,
          isYearly: _isYearly,
          showAge: _showAge,
        );
      } else {
        await repo.createCountdown(
          title: _titleController.text.trim(),
          type: widget.type,
          targetDate: _targetDate,
          isYearly: _isYearly,
          showAge: _showAge,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}
