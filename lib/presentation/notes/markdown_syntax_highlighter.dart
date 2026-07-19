import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

class MarkdownSyntaxHighlighter extends TextEditingController {
  MarkdownSyntaxHighlighter({super.text});

  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();

    final List<TextSpan> spans = [];
    final pattern = RegExp(
      r'(?<bold>\*\*.*?\*\*)|(?<italic>\b_.*?_\b|\*.*?\*)|(?<heading>#{1,6}\s.*)|(?<checkbox>^\s*-\s\[[ x]\]\s)|(?<list>^\s*[-*]\s.*|^\s*\d+\.\s.*)|(?<link>\[.*?\]\(.*?\))',
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
      TapGestureRecognizer? recognizer;
      
      if (match.namedGroup('bold') != null) {
        matchStyle = style?.copyWith(fontWeight: FontWeight.bold);
      } else if (match.namedGroup('italic') != null) {
        matchStyle = style?.copyWith(fontStyle: FontStyle.italic);
      } else if (match.namedGroup('heading') != null) {
        matchStyle = style?.copyWith(fontWeight: FontWeight.bold, fontSize: (style.fontSize ?? 14) * 1.3);
      } else if (match.namedGroup('checkbox') != null) {
        final matchText = text.substring(match.start, match.end);
        final isChecked = matchText.contains('[x]');
        
        recognizer = TapGestureRecognizer()
          ..onTap = () {
            final start = match.start;
            final end = match.end;
            final currentText = text;
            final newText = isChecked
                ? matchText.replaceFirst('[x]', '[ ]')
                : matchText.replaceFirst('[ ]', '[x]');
            
            final oldSelection = selection;
            value = TextEditingValue(
              text: currentText.replaceRange(start, end, newText),
              selection: oldSelection,
            );
          };
        _recognizers.add(recognizer);
        
        matchStyle = style?.copyWith(
          color: isChecked ? Colors.grey : Colors.blueAccent,
        );
      } else if (match.namedGroup('list') != null) {
        matchStyle = style?.copyWith(color: Colors.blueAccent);
      } else if (match.namedGroup('link') != null) {
        matchStyle = style?.copyWith(color: Colors.blue, decoration: TextDecoration.underline);
      }

      spans.add(TextSpan(
        text: text.substring(match.start, match.end),
        style: matchStyle,
        recognizer: recognizer,
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

