import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme/theme_engine_provider.dart';

/// Placeholder for the Notes section — real content arrives in its own
/// build step. Exists now purely so the shell has something to navigate
/// to and StatefulShellRoute has a branch to preserve state for.
class NotesScreen extends ConsumerWidget {
  const NotesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = ref.watch(themeEngineProvider);
    
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('Notes', style: TextStyle(color: palette.text, fontWeight: FontWeight.bold, fontSize: 24)),
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.notes_outlined, size: 64, color: palette.text.withValues(alpha: 0.1)),
            const SizedBox(height: 16),
            Text(
              'Notes',
              style: TextStyle(color: palette.text, fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Coming in a later build step',
              style: TextStyle(color: palette.text.withValues(alpha: 0.5), fontSize: 16),
            ),
          ],
        ).animate().fadeIn().slideY(begin: 0.1),
      ),
    );
  }
}
