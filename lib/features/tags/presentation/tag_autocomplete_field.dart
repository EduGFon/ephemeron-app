import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/database.dart';
import '../../../data/local/database_provider.dart';

/// Stream of all tags — consumed by the overlay (ConsumerWidget, so it has
/// its own ref and is never affected by the parent widget's lifecycle).
final allTagsProvider = StreamProvider<List<Tag>>((ref) {
  return ref.watch(appDatabaseProvider).select(ref.watch(appDatabaseProvider).tags).watch();
});

/// A TextField that intercepts `#` to show a floating tag-autocomplete overlay.
///
/// Fix for "ref unsafe" crash: the overlay is a [ConsumerWidget] with its OWN
/// Riverpod ref — it never borrows the parent's [WidgetRef], which becomes
/// invalid once the field widget starts unmounting.
class TagAutocompleteField extends StatefulWidget {
  const TagAutocompleteField({
    super.key,
    required this.controller,
    this.onTagSelected,
    this.decoration,
    this.style,
    this.textCapitalization = TextCapitalization.sentences,
    this.autofocus = false,
    this.onChanged,
  });

  final TextEditingController controller;
  final ValueChanged<Tag>? onTagSelected;
  final InputDecoration? decoration;
  final TextStyle? style;
  final TextCapitalization textCapitalization;
  final bool autofocus;
  final ValueChanged<String>? onChanged;

  @override
  State<TagAutocompleteField> createState() => _TagAutocompleteFieldState();
}

class _TagAutocompleteFieldState extends State<TagAutocompleteField> {
  final _focusNode = FocusNode();
  final _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    // Remove without setState — the widget is being torn down.
    _overlayEntry?.remove();
    _overlayEntry?.dispose();
    _overlayEntry = null;
    super.dispose();
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus) _hideOverlay();
  }

  void _onTextChanged() {
    if (!mounted) return;
    final text = widget.controller.text;
    final selection = widget.controller.selection;
    if (!selection.isValid) return;

    final cursor = selection.baseOffset.clamp(0, text.length);
    final before = text.substring(0, cursor);
    final hashIndex = before.lastIndexOf('#');

    if (hashIndex == -1) { _hideOverlay(); return; }

    final afterHash = before.substring(hashIndex + 1);
    // If there's a space after #, we're no longer in a tag token.
    if (afterHash.contains(' ') || afterHash.contains('\n')) { _hideOverlay(); return; }

    _showOverlayMenu(afterHash.toLowerCase());
    widget.onChanged?.call(text);
  }

  void _showOverlayMenu(String query) {
    // Rebuild the overlay entry each time the query changes so the
    // ConsumerWidget inside re-renders with the new filter string.
    _overlayEntry?.remove();
    _overlayEntry?.dispose();

    _overlayEntry = OverlayEntry(
      builder: (_) => _TagOverlayPortal(
        link: _layerLink,
        query: query,
        onTagSelected: (tag) {
          _insertTag(tag);
          _hideOverlay();
        },
        onDismiss: _hideOverlay,
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _insertTag(Tag tag) {
    final text = widget.controller.text;
    final cursor = widget.controller.selection.baseOffset.clamp(0, text.length);
    final before = text.substring(0, cursor);
    final after = text.substring(cursor);
    final hashIndex = before.lastIndexOf('#');
    if (hashIndex == -1) return;

    final newText = '${before.substring(0, hashIndex)}#${tag.name} $after';
    widget.controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: hashIndex + tag.name.length + 2),
    );
    widget.onTagSelected?.call(tag);
  }

  void _hideOverlay() {
    _overlayEntry?.remove();
    _overlayEntry?.dispose();
    _overlayEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: TextField(
        controller: widget.controller,
        focusNode: _focusNode,
        autofocus: widget.autofocus,
        style: widget.style,
        textCapitalization: widget.textCapitalization,
        decoration: widget.decoration,
        onChanged: widget.onChanged,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Overlay portal — a ConsumerWidget with its own Riverpod ref.
// This is the key fix: it NEVER borrows a ref from the parent widget.
// ─────────────────────────────────────────────────────────────────────────────

class _TagOverlayPortal extends ConsumerWidget {
  const _TagOverlayPortal({
    required this.link,
    required this.query,
    required this.onTagSelected,
    required this.onDismiss,
  });

  final LayerLink link;
  final String query;
  final ValueChanged<Tag> onTagSelected;
  final VoidCallback onDismiss;

  Color _parseColor(String hex) {
    try {
      final c = hex.replaceAll('#', '');
      return Color(int.parse('FF$c', radix: 16));
    } catch (_) {
      return const Color(0xFFD89B3C);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Safe: this ConsumerWidget has its own ref that lives until THIS
    // widget is removed from the overlay, not tied to the field's lifecycle.
    final tagsAsync = ref.watch(allTagsProvider);
    final tags = tagsAsync.value ?? const [];
    final filtered = query.isEmpty
        ? tags
        : tags.where((t) => t.name.toLowerCase().contains(query)).toList();

    if (filtered.isEmpty) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E1E2A) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final borderColor = isDark ? Colors.white12 : Colors.black12;

    return Positioned(
      child: CompositedTransformFollower(
        link: link,
        showWhenUnlinked: false,
        offset: const Offset(0, 38),
        child: Material(
          color: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 260, maxHeight: 220),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: filtered.length,
                separatorBuilder: (_, __) => Divider(height: 1, color: borderColor),
                itemBuilder: (ctx, i) {
                  final tag = filtered[i];
                  final color = _parseColor(tag.colorHex);
                  return InkWell(
                    onTap: () => onTagSelected(tag),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Row(
                        children: [
                          CircleAvatar(radius: 6, backgroundColor: color),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '#${tag.name}',
                              style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontSize: 14),
                            ),
                          ),
                          if (tag.defaultAlarmPreset != null)
                            Icon(Icons.notifications_outlined, size: 12, color: textColor.withValues(alpha: 0.4)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
