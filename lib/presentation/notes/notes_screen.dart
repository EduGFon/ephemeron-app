import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/theme/theme_engine_provider.dart';
import '../../core/theme/theme_palettes.dart';
import '../../data/local/database.dart';
import '../../features/notes/application/notes_providers.dart';
import '../../features/notes/data/notes_repository.dart';

class NotesScreen extends ConsumerWidget {
  const NotesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = ref.watch(themeEngineProvider);
    final currentFolderId = ref.watch(currentFolderIdProvider);
    final notesAsync = ref.watch(notesStreamProvider);
    final foldersAsync = ref.watch(foldersStreamProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.menu, color: palette.text),
          onPressed: () {
            // Hamburger menu functionality - standard open drawer if available
            Scaffold.of(context).openDrawer();
          },
        ),
        title: foldersAsync.when(
          data: (allFolders) => _buildBreadcrumbs(currentFolderId, allFolders, palette, ref),
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.create_new_folder_outlined, color: palette.text),
            tooltip: 'New Folder',
            onPressed: () => _showCreateFolderDialog(context, ref),
          ),
          IconButton(
            icon: Icon(Icons.search, color: palette.text),
            tooltip: 'Search',
            onPressed: () {
              // Search dialog/functionality placeholder
            },
          ),
          IconButton(
            icon: Icon(Icons.more_vert, color: palette.text),
            onPressed: () {
              // More actions
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              foldersAsync.when(
                data: (allFolders) {
                  // Filter folders whose parentFolderId is equal to currentFolderId
                  final visibleFolders = allFolders
                      .where((f) => f.parentFolderId == currentFolderId)
                      .toList();

                  // Get all notes to compute note counts inside folder picker
                  final allNotes = notesAsync.value ?? const [];

                  return _buildFoldersList(visibleFolders, allNotes, palette, ref);
                },
                loading: () => const SizedBox(height: 110, child: Center(child: CircularProgressIndicator())),
                error: (err, _) => Center(child: Text('Error loading folders: $err', style: TextStyle(color: palette.text))),
              ),
              const SizedBox(height: 12),
              notesAsync.when(
                data: (allNotes) {
                  // Filter notes belonging to currentFolderId
                  final visibleNotes = allNotes
                      .where((n) => n.folderId == currentFolderId)
                      .toList();

                  return _buildNotesSection(visibleNotes, palette, ref);
                },
                loading: () => const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator())),
                error: (err, _) => Center(child: Text('Error loading notes: $err', style: TextStyle(color: palette.text))),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: palette.primary,
        foregroundColor: palette.background,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        onPressed: () => _showNoteFormSheet(context, ref),
        child: const Icon(Icons.edit_outlined, size: 24),
      ),
    );
  }

  Widget _buildBreadcrumbs(
    String? currentId,
    List<NoteFolder> allFolders,
    AppPalette palette,
    WidgetRef ref,
  ) {
    final path = <Widget>[];

    path.add(
      GestureDetector(
        onTap: () {
          ref.read(currentFolderIdProvider.notifier).setFolder(null);
        },
        child: Text(
          'Folders',
          style: TextStyle(
            color: currentId == null ? palette.text : palette.text.withValues(alpha: 0.5),
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
      ),
    );

    if (currentId != null) {
      final list = <NoteFolder>[];
      String? targetId = currentId;
      while (targetId != null) {
        final folderList = allFolders.where((f) => f.id == targetId);
        if (folderList.isEmpty) break;
        final folder = folderList.first;
        list.insert(0, folder);
        targetId = folder.parentFolderId;
      }

      for (final folder in list) {
        path.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Icon(Icons.chevron_right, color: palette.text.withValues(alpha: 0.3), size: 16),
          ),
        );
        path.add(
          GestureDetector(
            onTap: () {
              ref.read(currentFolderIdProvider.notifier).setFolder(folder.id);
            },
            child: Text(
              folder.name,
              style: TextStyle(
                color: folder.id == currentId ? palette.text : palette.text.withValues(alpha: 0.5),
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
          ),
        );
      }
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: path,
      ),
    );
  }

  Widget _buildFoldersList(
    List<NoteFolder> folders,
    List<Note> notes,
    AppPalette palette,
    WidgetRef ref,
  ) {
    if (folders.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 110,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: folders.length,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemBuilder: (context, index) {
          final folder = folders[index];
          final noteCount = notes.where((n) => n.folderId == folder.id).length;

          return GestureDetector(
            onTap: () {
              ref.read(currentFolderIdProvider.notifier).setFolder(folder.id);
            },
            onLongPress: () {
              _showDeleteFolderDialog(context, ref, folder);
            },
            child: Container(
              width: 100,
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: palette.text.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: palette.text.withValues(alpha: 0.08)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: palette.primary.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.folder, color: palette.primary, size: 20),
                      ),
                      Text(
                        '$noteCount',
                        style: TextStyle(
                          color: palette.text.withValues(alpha: 0.5),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    folder.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.text,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildNotesSection(
    List<Note> notes,
    AppPalette palette,
    WidgetRef ref,
  ) {
    if (notes.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(48.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.notes, size: 48, color: palette.text.withValues(alpha: 0.1)),
              const SizedBox(height: 8),
              Text(
                'No notes yet',
                style: TextStyle(color: palette.text.withValues(alpha: 0.4), fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    final grouped = _groupNotesByDate(notes);
    final keys = grouped.keys.toList();

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: keys.length,
      itemBuilder: (context, idx) {
        final key = keys[idx];
        final groupNotes = grouped[key]!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 16, top: 20, bottom: 8),
              child: Text(
                key,
                style: TextStyle(
                  color: palette.text.withValues(alpha: 0.5),
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.95,
              ),
              itemCount: groupNotes.length,
              itemBuilder: (context, noteIdx) {
                final note = groupNotes[noteIdx];
                return GestureDetector(
                  onTap: () => _showNoteFormSheet(context, ref, existingNote: note),
                  onLongPress: () => _showDeleteNoteDialog(context, ref, note),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: palette.text.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: palette.text.withValues(alpha: 0.08)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            note.content,
                            style: TextStyle(
                              color: palette.text.withValues(alpha: 0.8),
                              fontSize: 13,
                              height: 1.4,
                            ),
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          note.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: palette.text,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _formatDate(note.createdAt),
                          style: TextStyle(
                            color: palette.text.withValues(alpha: 0.4),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
    ).animate().fadeIn();
  }

  Map<String, List<Note>> _groupNotesByDate(List<Note> notes) {
    final grouped = <String, List<Note>>{};
    final now = DateTime.now();

    for (final note in notes) {
      final dt = note.createdAt;
      String key;
      if (dt.year == now.year && dt.month == now.month) {
        key = 'This month';
      } else if (dt.year == now.year) {
        key = _getMonthName(dt.month);
      } else {
        key = '${dt.year}';
      }
      grouped.putIfAbsent(key, () => []).add(note);
    }
    return grouped;
  }

  String _getMonthName(int month) {
    return switch (month) {
      1 => 'Jan',
      2 => 'Feb',
      3 => 'Mar',
      4 => 'Apr',
      5 => 'May',
      6 => 'Jun',
      7 => 'Jul',
      8 => 'Aug',
      9 => 'Sep',
      10 => 'Oct',
      11 => 'Nov',
      _ => 'Dec',
    };
  }

  String _formatDate(DateTime dt) {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[dt.month - 1]} ${dt.day}';
  }

  void _showCreateFolderDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    final palette = ref.read(themeEngineProvider);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: palette.surface,
        title: Text('New Folder', style: TextStyle(color: palette.text)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: palette.text),
          decoration: InputDecoration(
            hintText: 'Folder name',
            hintStyle: TextStyle(color: palette.text.withValues(alpha: 0.5)),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: palette.primary),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Cancel', style: TextStyle(color: palette.text.withValues(alpha: 0.6))),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: palette.primary),
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                final parentId = ref.read(currentFolderIdProvider);
                await ref.read(notesRepositoryProvider).createFolder(
                  NoteFoldersCompanion.insert(
                    name: name,
                    parentFolderId: Value(parentId),
                  ),
                );
                if (context.mounted) Navigator.of(context).pop();
              }
            },
            child: Text('Create', style: TextStyle(color: palette.background)),
          ),
        ],
      ),
    );
  }

  void _showDeleteFolderDialog(BuildContext context, WidgetRef ref, NoteFolder folder) {
    final palette = ref.read(themeEngineProvider);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: palette.surface,
        title: Text('Delete folder?', style: TextStyle(color: palette.text)),
        content: Text(
          'This will permanently delete the folder "${folder.name}". Notes inside will be moved to the parent directory.',
          style: TextStyle(color: palette.text.withValues(alpha: 0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Cancel', style: TextStyle(color: palette.text.withValues(alpha: 0.6))),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await ref.read(notesRepositoryProvider).deleteFolder(folder.id);
              if (context.mounted) Navigator.of(context).pop();
            },
            child: const Text('Delete', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showDeleteNoteDialog(BuildContext context, WidgetRef ref, Note note) {
    final palette = ref.read(themeEngineProvider);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: palette.surface,
        title: Text('Delete note?', style: TextStyle(color: palette.text)),
        content: Text(
          'Are you sure you want to permanently delete this note?',
          style: TextStyle(color: palette.text.withValues(alpha: 0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Cancel', style: TextStyle(color: palette.text.withValues(alpha: 0.6))),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await ref.read(notesRepositoryProvider).deleteNote(note.id);
              if (context.mounted) Navigator.of(context).pop();
            },
            child: const Text('Delete', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showNoteFormSheet(BuildContext context, WidgetRef ref, {Note? existingNote}) {
    final titleController = TextEditingController(text: existingNote?.title);
    final contentController = TextEditingController(text: existingNote?.content);
    final palette = ref.read(themeEngineProvider);

    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black54,
      pageBuilder: (context, anim1, anim2) {
        return Center(
          child: Container(
            width: (MediaQuery.of(context).size.width * 0.9).clamp(300.0, 600.0),
            height: (MediaQuery.of(context).size.height * 0.8).clamp(400.0, 600.0),
            margin: const EdgeInsets.symmetric(vertical: 24),
            decoration: BoxDecoration(
              color: palette.surface.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: palette.text.withValues(alpha: 0.1)),
            ),
            child: Material(
              color: Colors.transparent,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      existingNote != null ? 'Edit Note' : 'New Note',
                      style: TextStyle(
                        fontFamily: 'Fraunces',
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: palette.text,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: titleController,
                      style: TextStyle(color: palette.text, fontWeight: FontWeight.bold, fontSize: 18),
                      decoration: InputDecoration(
                        hintText: 'Title',
                        hintStyle: TextStyle(color: palette.text.withValues(alpha: 0.5)),
                        border: InputBorder.none,
                      ),
                    ),
                    const Divider(),
                    Expanded(
                      child: TextField(
                        controller: contentController,
                        maxLines: null,
                        expands: true,
                        style: TextStyle(color: palette.text),
                        decoration: InputDecoration(
                          hintText: 'Type your note here...',
                          hintStyle: TextStyle(color: palette.text.withValues(alpha: 0.5)),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: Text('Cancel', style: TextStyle(color: palette.text.withValues(alpha: 0.6))),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: palette.primary),
                          onPressed: () async {
                            final title = titleController.text.trim();
                            final content = contentController.text.trim();
                            if (title.isEmpty && content.isEmpty) return;

                            final folderId = ref.read(currentFolderIdProvider);
                            final repo = ref.read(notesRepositoryProvider);

                            if (existingNote != null) {
                              await repo.updateNote(
                                NotesCompanion(
                                  id: Value(existingNote.id),
                                  title: Value(title.isEmpty ? '(Untitled)' : title),
                                  content: Value(content),
                                  folderId: Value(existingNote.folderId),
                                  updatedAt: Value(DateTime.now()),
                                ),
                              );
                            } else {
                              await repo.createNote(
                                NotesCompanion.insert(
                                  title: title.isEmpty ? '(Untitled)' : title,
                                  content: content,
                                  folderId: Value(folderId),
                                ),
                              );
                            }
                            if (context.mounted) Navigator.of(context).pop();
                          },
                          child: Text('Save', style: TextStyle(color: palette.background, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
