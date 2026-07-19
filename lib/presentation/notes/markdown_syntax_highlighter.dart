import 'package:flutter/material.dart';

class MarkdownSyntaxHighlighter extends TextEditingController {
  MarkdownSyntaxHighlighter({super.text});

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final List<TextSpan> spans = [];
    final pattern = RegExp(
      r'(?<bold>\*\*.*?\*\*)|(?<italic>\b_.*?_\b|\*.*?\*)|(?<heading>#{1,6}\s.*)|(?<list>^\s*-\s\[[ x]\]\s.*|^\s*[-*]\s.*|^\s*\d+\.\s.*)|(?<link>\[.*?\]\(.*?\))',
      multiLine: true,
    );

    int lastMatchEnd = 0;
    for (final match in pattern.allMatches(text)) {
      if (match.start > lastMatchEnd) {
        spans.add(TextSpan(
          text: text.substring(lastMatchEnd, match.start),
          style: style,
        ));
      }

      TextStyle? matchStyle = style;
      
      if (match.namedGroup('bold') != null) {
        matchStyle = style?.copyWith(fontWeight: FontWeight.bold);
      } else if (match.namedGroup('italic') != null) {
        matchStyle = style?.copyWith(fontStyle: FontStyle.italic);
      } else if (match.namedGroup('heading') != null) {
        matchStyle = style?.copyWith(fontWeight: FontWeight.bold, fontSize: (style.fontSize ?? 14) * 1.3);
      } else if (match.namedGroup('list') != null) {
        matchStyle = style?.copyWith(color: Colors.blueAccent);
      } else if (match.namedGroup('link') != null) {
        matchStyle = style?.copyWith(color: Colors.blue, decoration: TextDecoration.underline);
      }

      spans.add(TextSpan(
        text: text.substring(match.start, match.end),
        style: matchStyle,
      ));

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
