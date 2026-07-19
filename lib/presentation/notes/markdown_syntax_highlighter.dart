import 'package:flutter/material.dart';

class MarkdownSyntaxHighlighter extends TextEditingController {
  MarkdownSyntaxHighlighter({super.text});

  bool toggleCheckboxAtCursor() {
    final offset = selection.baseOffset;
    if (offset < 0) return false;

    final textBefore = text.substring(0, offset);
    final textAfter = text.substring(offset);
    final lineStart = textBefore.lastIndexOf('\n') + 1;
    final lineEndIndex = textAfter.indexOf('\n');
    final lineEnd = lineEndIndex == -1 ? text.length : offset + lineEndIndex;

    if (lineStart >= lineEnd) return false;

    final line = text.substring(lineStart, lineEnd);
    final match = RegExp(r'^(\s*-\s\[)([ x])(\]\s)').firstMatch(line);
    
    if (match != null) {
      final checkboxStart = lineStart + match.start;
      final checkboxEnd = lineStart + match.end;

      if (offset >= checkboxStart && offset <= checkboxEnd) {
        final isChecked = match.group(2) == 'x';
        final newChar = isChecked ? ' ' : 'x';
        final replaceStart = lineStart + match.start + match.group(1)!.length;
        
        final newText = text.replaceRange(replaceStart, replaceStart + 1, newChar);
        
        value = TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(offset: offset),
        );
        return true;
      }
    }
    return false;
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final List<TextSpan> spans = [];
    final pattern = RegExp(
      r'(?<bold>\*\*(?<boldContent>.*?)\*\*)|(?<italic>_(?<italicContent>.*?)_|\*(?<italicContent2>.*?)\*)|(?<heading>(?<headingSyntax>#{1,6}\s)(?<headingContent>.*))|(?<checkbox>^\s*-\s\[[ x]\]\s)|(?<list>^\s*[-*]\s.*|^\s*\d+\.\s.*)|(?<link>\[(?<linkContent>.*?)\]\((?<linkUrl>.*?)\))',
      multiLine: true,
    );

    int activeLineStart = -1;
    int activeLineEnd = -1;
    if (selection.isValid && selection.isCollapsed) {
      final offset = selection.baseOffset;
      activeLineStart = text.lastIndexOf('\n', offset - 1 == -1 ? 0 : offset - 1) + 1;
      final end = text.indexOf('\n', offset);
      activeLineEnd = end == -1 ? text.length : end;
    } else if (selection.isValid && !selection.isCollapsed) {
      activeLineStart = text.lastIndexOf('\n', selection.start - 1 == -1 ? 0 : selection.start - 1) + 1;
      final end = text.indexOf('\n', selection.end);
      activeLineEnd = end == -1 ? text.length : end;
    }

    int lastMatchEnd = 0;
    for (final match in pattern.allMatches(text)) {
      if (match.start > lastMatchEnd) {
        spans.add(TextSpan(
          text: text.substring(lastMatchEnd, match.start),
          style: style,
        ));
      }

      final touchesActiveLine = (match.start <= activeLineEnd && match.end >= activeLineStart);
      final hideSyntax = !touchesActiveLine;
      final hiddenStyle = style?.copyWith(color: Colors.transparent, fontSize: 0.0);

      if (match.namedGroup('bold') != null) {
        final content = match.namedGroup('boldContent')!;
        final syntaxStyle = hideSyntax ? hiddenStyle : style?.copyWith(color: Colors.grey);
        final contentStyle = style?.copyWith(fontWeight: FontWeight.bold);

        spans.add(TextSpan(text: '**', style: syntaxStyle));
        spans.add(TextSpan(text: content, style: contentStyle));
        spans.add(TextSpan(text: '**', style: syntaxStyle));
      } else if (match.namedGroup('italic') != null) {
        final content = match.namedGroup('italicContent') ?? match.namedGroup('italicContent2')!;
        final syntaxChar = match.namedGroup('italicContent') != null ? '_' : '*';
        final syntaxStyle = hideSyntax ? hiddenStyle : style?.copyWith(color: Colors.grey);
        final contentStyle = style?.copyWith(fontStyle: FontStyle.italic);

        spans.add(TextSpan(text: syntaxChar, style: syntaxStyle));
        spans.add(TextSpan(text: content, style: contentStyle));
        spans.add(TextSpan(text: syntaxChar, style: syntaxStyle));
      } else if (match.namedGroup('heading') != null) {
        final syntax = match.namedGroup('headingSyntax')!;
        final content = match.namedGroup('headingContent')!;
        final syntaxStyle = hideSyntax ? hiddenStyle : style?.copyWith(color: Colors.grey, fontSize: (style.fontSize ?? 14) * 1.3);
        final contentStyle = style?.copyWith(fontWeight: FontWeight.bold, fontSize: (style.fontSize ?? 14) * 1.3);

        spans.add(TextSpan(text: syntax, style: syntaxStyle));
        spans.add(TextSpan(text: content, style: contentStyle));
      } else if (match.namedGroup('checkbox') != null) {
        final matchText = text.substring(match.start, match.end);
        final isChecked = matchText.contains('[x]');
        spans.add(TextSpan(
          text: matchText,
          style: style?.copyWith(
            color: isChecked ? Colors.grey : Colors.blueAccent,
            fontWeight: FontWeight.bold,
          ),
        ));
      } else if (match.namedGroup('list') != null) {
        spans.add(TextSpan(
          text: text.substring(match.start, match.end),
          style: style?.copyWith(color: Colors.blueAccent),
        ));
      } else if (match.namedGroup('link') != null) {
        final linkContent = match.namedGroup('linkContent')!;
        final linkUrl = match.namedGroup('linkUrl')!;
        final syntaxStyle = hideSyntax ? hiddenStyle : style?.copyWith(color: Colors.grey);
        final contentStyle = style?.copyWith(color: Colors.blue, decoration: TextDecoration.underline);

        spans.add(TextSpan(text: '[', style: syntaxStyle));
        spans.add(TextSpan(text: linkContent, style: contentStyle));
        spans.add(TextSpan(text: ']($linkUrl)', style: syntaxStyle));
      }

      lastMatchEnd = match.end;
    }

    if (lastMatchEnd < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastMatchEnd),
        style: style,
      ));
    }

    return TextSpan(style: style, children: spans);
  }
}
