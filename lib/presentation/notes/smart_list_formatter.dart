import 'package:flutter/services.dart';

class SmartListFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // If text was removed, or if this is not a simple single character insertion (like Enter), just return newValue.
    if (newValue.text.length <= oldValue.text.length) {
      return _renumberLists(newValue, oldValue);
    }

    // Check if the newly added character(s) includes a newline
    final int insertionStart = oldValue.selection.baseOffset;
    final int insertionEnd = newValue.selection.baseOffset;
    
    if (insertionStart >= 0 && insertionEnd > insertionStart) {
      final insertedText = newValue.text.substring(insertionStart, insertionEnd);
      if (insertedText == '\n') {
        return _handleNewline(oldValue, newValue, insertionStart);
      }
    }

    return _renumberLists(newValue, oldValue);
  }

  TextEditingValue _handleNewline(TextEditingValue oldValue, TextEditingValue newValue, int insertionStart) {
    // Find the previous line
    final textBeforeInsertion = oldValue.text.substring(0, insertionStart);
    final previousNewlineIndex = textBeforeInsertion.lastIndexOf('\n');
    final previousLine = textBeforeInsertion.substring(previousNewlineIndex + 1);

    // Regex to match list prefixes:
    // Checkboxes: "- [ ] ", "- [x] "
    // Bullets: "- ", "* "
    // Numbers: "1. "
    // Arrows: "-> ", "=> "
    final RegExp prefixRegex = RegExp(r'^(\s*)(-\s\[\s\]\s|-\s\[x\]\s|-\s|\*\s|\d+\.\s|->\s|=>\s)(.*)$');
    final match = prefixRegex.firstMatch(previousLine);

    if (match != null) {
      final indent = match.group(1) ?? '';
      String prefix = match.group(2) ?? '';
      final content = match.group(3) ?? '';

      // If the previous line was just an empty list item, hitting enter again should remove it (stop the list).
      if (content.trim().isEmpty) {
        final beforeEmptyItem = textBeforeInsertion.substring(0, previousNewlineIndex + 1);
        final afterEmptyItem = newValue.text.substring(insertionStart + 1);
        final newText = beforeEmptyItem + afterEmptyItem;
        return TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(offset: beforeEmptyItem.length),
        );
      }

      // Handle numbers auto-increment
      final numberMatch = RegExp(r'^(\d+)\.\s$').firstMatch(prefix);
      if (numberMatch != null) {
        final currentNum = int.parse(numberMatch.group(1)!);
        prefix = '${currentNum + 1}. ';
      } else if (prefix == '- [x] ') {
        prefix = '- [ ] '; // Checkboxes should default to unchecked on a new line
      }

      final insertString = '\n$indent$prefix';
      
      final textBefore = oldValue.text.substring(0, insertionStart);
      final textAfter = oldValue.text.substring(insertionStart);
      
      var finalString = textBefore + insertString + textAfter;
      var newSelectionOffset = textBefore.length + insertString.length;

      final resultValue = TextEditingValue(
        text: finalString,
        selection: TextSelection.collapsed(offset: newSelectionOffset),
      );
      
      return _renumberLists(resultValue, newValue);
    }

    return newValue;
  }

  TextEditingValue _renumberLists(TextEditingValue current, TextEditingValue old) {
    // Only renumber if the text has changed substantially (e.g. items added or removed)
    // To avoid excessive computation on every single keystroke, we can do a quick check
    // if there's a numbered list in the text.
    if (!current.text.contains(RegExp(r'^\s*\d+\.\s', multiLine: true))) {
      return current;
    }

    final lines = current.text.split('\n');
    bool inList = false;
    int listCounter = 1;
    bool changed = false;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final numberMatch = RegExp(r'^(\s*)(\d+)\.\s(.*)$').firstMatch(line);
      
      if (numberMatch != null) {
        if (!inList) {
          inList = true;
          listCounter = int.parse(numberMatch.group(2)!);
        } else {
          listCounter++;
          final expectedPrefix = '${numberMatch.group(1)}$listCounter. ${numberMatch.group(3)}';
          if (line != expectedPrefix) {
            lines[i] = expectedPrefix;
            changed = true;
          }
        }
      } else {
        // Stop sequential numbering if we hit a non-numbered line (unless it's just indented content?)
        // For simplicity, any non-numbered line resets the list detection.
        if (line.trim().isNotEmpty) {
          inList = false;
        }
      }
    }

    if (changed) {
      final newText = lines.join('\n');
      
      // We must adjust the selection offset based on the length difference
      int offsetDiff = newText.length - current.text.length;
      int newOffset = current.selection.baseOffset + offsetDiff;
      if (newOffset < 0) newOffset = 0;
      if (newOffset > newText.length) newOffset = newText.length;

      return TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: newOffset),
      );
    }

    return current;
  }
}
