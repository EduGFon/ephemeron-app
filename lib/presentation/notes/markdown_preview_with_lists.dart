import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

class MarkdownPreviewWithLists extends StatefulWidget {
  const MarkdownPreviewWithLists({
    required this.data,
    required this.onChanged,
    required this.styleSheet,
    super.key,
  });

  final String data;
  final ValueChanged<String> onChanged;
  final MarkdownStyleSheet styleSheet;

  @override
  State<MarkdownPreviewWithLists> createState() => _MarkdownPreviewWithListsState();
}

class _MarkdownPreviewWithListsState extends State<MarkdownPreviewWithLists> {
  @override
  Widget build(BuildContext context) {
    final blocks = _parseBlocks(widget.data);

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: blocks.length,
      itemBuilder: (context, index) {
        final block = blocks[index];
        if (block is _TextBlock) {
          return MarkdownBody(
            data: block.text.replaceAll(RegExp(r'(?<!\n)\n(?!\n)'), '  \n'),
            styleSheet: widget.styleSheet,
          );
        } else if (block is _ListBlock) {
          return ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: block.items.length,
            onReorderItem: (oldIndex, newIndex) {
              final item = block.items.removeAt(oldIndex);
              block.items.insert(newIndex, item);
              
              _rebuildTextAndNotify(blocks);
            },
            itemBuilder: (context, i) {
              final item = block.items[i];
              return Row(
                key: ValueKey('${block.startIndex}_$i'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 4.0, right: 8.0, left: 8.0),
                    child: Icon(Icons.drag_indicator, size: 16, color: Colors.grey),
                  ),
                  Expanded(
                    child: MarkdownBody(
                      data: item.trim(),
                      styleSheet: widget.styleSheet,
                    ),
                  ),
                ],
              );
            },
          );
        }
        return const SizedBox.shrink();
      },
    );
  }

  void _rebuildTextAndNotify(List<_Block> blocks) {
    final buffer = StringBuffer();
    for (final block in blocks) {
      if (block is _TextBlock) {
        buffer.write(block.text);
      } else if (block is _ListBlock) {
        for (var i = 0; i < block.items.length; i++) {
          final item = block.items[i];
          if (block.isNumbered) {
            final content = item.replaceFirst(RegExp(r'^\d+\.\s'), '');
            buffer.write('${i + 1}. $content');
          } else {
            buffer.write(item);
          }
        }
      }
    }
    widget.onChanged(buffer.toString());
  }

  List<_Block> _parseBlocks(String text) {
    final lines = text.split(RegExp(r'(?<=\n)')); // Keep newlines
    final blocks = <_Block>[];
    
    final listRegex = RegExp(r'^(\s*)(-\s\[\s\]\s|-\s\[x\]\s|-\s|\*\s|\d+\.\s|->\s|=>\s)(.*)$');

    _TextBlock? currentText;
    _ListBlock? currentList;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final match = listRegex.firstMatch(line);

      if (match != null) {
        if (currentText != null) {
          blocks.add(currentText);
          currentText = null;
        }
        currentList ??= _ListBlock(startIndex: i, isNumbered: line.trimLeft().contains(RegExp(r'^\d+\.')));
        currentList.items.add(line);
      } else {
        // If it's an indented line following a list item, it might be part of it.
        // For simplicity, any non-matching line breaks the list unless it's just whitespace.
        if (currentList != null && line.trim().isEmpty) {
          currentList.items.last += line; // append empty line to last item
        } else {
          if (currentList != null) {
            blocks.add(currentList);
            currentList = null;
          }
          currentText ??= _TextBlock();
          currentText.text += line;
        }
      }
    }

    if (currentText != null) blocks.add(currentText);
    if (currentList != null) blocks.add(currentList);

    return blocks;
  }
}

abstract class _Block {}

class _TextBlock extends _Block {
  String text = '';
}

class _ListBlock extends _Block {
  _ListBlock({required this.startIndex, required this.isNumbered});
  final int startIndex;
  final bool isNumbered;
  final List<String> items = [];
}
