import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/database.dart';
import '../../../data/local/database_provider.dart';

// Provider for all tags (used by autocomplete)
final allTagsProvider = StreamProvider<List<Tag>>((ref) {
  return ref.watch(appDatabaseProvider).select(ref.watch(appDatabaseProvider).tags).watch();
});

/// A text field that intercepts `#` to show a tag autocomplete overlay.
/// When the user types `#`, a floating menu appears with filtered tags.
/// Selecting a tag fires [onTagSelected] and inserts `#tagname` at the cursor.
class TagAutocompleteField extends ConsumerStatefulWidget {
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
  ConsumerState<TagAutocompleteField> createState() => _TagAutocompleteFieldState();
}

class _TagAutocompleteFieldState extends ConsumerState<TagAutocompleteField> {
  final _focusNode = FocusNode();
  final _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  String _tagQuery = '';
  bool _showOverlay = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus) _hideOverlay();
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    _focusNode.dispose();
    _hideOverlay();
    super.dispose();
  }

  void _onTextChanged() {
    final text = widget.controller.text;
    final selection = widget.controller.selection;
    if (!selection.isValid) return;

    final cursor = selection.baseOffset.clamp(0, text.length);
    final before = text.substring(0, cursor);

    // Look for # that isn't preceded by a word character
    final hashIndex = before.lastIndexOf('#');
    if (hashIndex == -1) {
      _hideOverlay();
      return;
    }

    // Check that nothing between # and cursor has a space (i.e. we're still in a tag token)
    final afterHash = before.substring(hashIndex + 1);
    if (afterHash.contains(' ') || afterHash.contains('\n')) {
      _hideOverlay();
      return;
    }

    setState(() {
      _tagQuery = afterHash.toLowerCase();
      _showOverlay = true;
    });
    _showOverlayMenu();
    widget.onChanged?.call(text);
  }

  void _showOverlayMenu() {
    _hideOverlay(removeEntry: false);
    final overlay = Overlay.of(context);
    _overlayEntry = OverlayEntry(builder: (_) => _TagOverlay(
      link: _layerLink,
      query: _tagQuery,
      ref: ref,
      onTagSelected: (tag) {
        _insertTag(tag);
        _hideOverlay();
      },
    ));
    overlay.insert(_overlayEntry!);
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

  void _hideOverlay({bool removeEntry = true}) {
    if (removeEntry) {
      _overlayEntry?.remove();
      _overlayEntry = null;
    }
    if (mounted) setState(() => _showOverlay = false);
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
        onChanged: (v) {
          // onTextChanged listener handles the tag logic
          widget.onChanged?.call(v);
        },
      ),
    );
  }
}

class _TagOverlay extends StatelessWidget {
  const _TagOverlay({
    required this.link,
    required this.query,
    required this.ref,
    required this.onTagSelected,
  });

  final LayerLink link;
  final String query;
  final WidgetRef ref;
  final ValueChanged<Tag> onTagSelected;

  @override
  Widget build(BuildContext context) {
    final tagsAsync = ref.watch(allTagsProvider);
    final tags = tagsAsync.value ?? const [];
    final filtered = query.isEmpty
        ? tags
        : tags.where((t) => t.name.toLowerCase().contains(query)).toList();

    if (filtered.isEmpty) return const SizedBox.shrink();

    // Get theme colors from context if available
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E1E2A) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final borderColor = isDark ? Colors.white12 : Colors.black12;

    return Positioned(
      child: CompositedTransformFollower(
        link: link,
        showWhenUnlinked: false,
        offset: const Offset(0, 36),
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
                            child: Text('#${tag.name}', style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontSize: 14)),
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

  Color _parseColor(String hex) {
    try {
      final c = hex.replaceAll('#', '');
      return Color(int.parse('FF$c', radix: 16));
    } catch (_) {
      return const Color(0xFFD89B3C);
    }
  }
}
