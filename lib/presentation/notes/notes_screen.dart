import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../core/theme/theme_engine_provider.dart';
import '../../core/theme/theme_palettes.dart';
import '../../data/local/database.dart';
import '../../features/notes/application/notes_providers.dart';
import '../../features/notes/data/notes_repository.dart';
import 'note_form_sheet.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Notes screen
// ─────────────────────────────────────────────────────────────────────────────

class NotesScreen extends ConsumerStatefulWidget {
  const NotesScreen({super.key});

  @override
  ConsumerState<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends ConsumerState<NotesScreen> {
  /// ID of the folder currently highlighted as a DragTarget.
  String? _dragHoverId;
  bool _isSearching = false;
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final palette = ref.watch(themeEngineProvider);
    final currentFolderId = ref.watch(currentFolderIdProvider);
    final notesAsync = ref.watch(notesStreamProvider);
    final foldersAsync = ref.watch(foldersStreamProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: _isSearching
            ? IconButton(
                icon: Icon(Icons.arrow_back, color: palette.text),
                onPressed: () => setState(() {
                  _isSearching = false;
                  _searchQuery = '';
                }),
              )
            : null,
        title: _isSearching
            ? TextField(
                autofocus: true,
                style: TextStyle(color: palette.text, fontSize: 16),
                decoration: InputDecoration(
                  hintText: 'Search title, content, #tag...',
                  hintStyle: TextStyle(color: palette.text.withValues(alpha: 0.4)),
                  border: InputBorder.none,
                ),
                onChanged: (val) => setState(() => _searchQuery = val),
              )
            : foldersAsync.when(
                data: (allFolders) => _buildBreadcrumbs(currentFolderId, allFolders, palette, ref),
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
        actions: _isSearching
            ? [
                if (_searchQuery.isNotEmpty)
                  IconButton(
                    icon: Icon(Icons.clear, color: palette.text),
                    onPressed: () => setState(() => _searchQuery = ''),
                  ),
              ]
            : [
                IconButton(
                  icon: Icon(Icons.create_new_folder_outlined, color: palette.text),
                  tooltip: 'New Folder',
                  onPressed: () => _showCreateFolderDialog(context, ref),
                ),
                IconButton(
                  icon: Icon(Icons.search, color: palette.text),
                  tooltip: 'Search',
                  onPressed: () => setState(() => _isSearching = true),
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
              // Folders row (with DragTarget support)
              foldersAsync.when(
                data: (allFolders) {
                  final visibleFolders = allFolders
                      .where((f) => f.parentFolderId == currentFolderId)
                      .toList();
                  final allNotes = notesAsync.value ?? const [];
                  return _buildFoldersList(visibleFolders, allNotes, palette, ref);
                },
                loading: () => const SizedBox(height: 110, child: Center(child: CircularProgressIndicator())),
                error: (err, _) => Center(child: Text('Error loading folders: $err', style: TextStyle(color: palette.text))),
              ),
              const SizedBox(height: 12),
              // Notes grid (Draggable cards)
              notesAsync.when(
                data: (allNotes) {
                  final q = _searchQuery.trim().toLowerCase();
                  final visibleNotes = allNotes.where((n) {
                    if (q.isEmpty) {
                      return n.folderId == currentFolderId;
                    }
                    final matchesText = n.title.toLowerCase().contains(q) ||
                        n.content.toLowerCase().contains(q);
                    bool matchesFolder = false;
                    if (foldersAsync.value != null) {
                      final matchingFolders = foldersAsync.value!
                          .where((f) => f.name.toLowerCase().contains(q))
                          .map((f) => f.id)
                          .toSet();
                      if (n.folderId != null && matchingFolders.contains(n.folderId)) {
                        matchesFolder = true;
                      }
                    }
                    final isInsideFolder = currentFolderId == null || n.folderId == currentFolderId;
                    return (matchesText || matchesFolder) && isInsideFolder;
                  }).toList();
                  return _buildNotesSection(visibleNotes, palette, ref);
                },
                loading: () => const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator())),
                error: (err, _) => Center(child: Text('Error loading notes: $err', style: TextStyle(color: palette.text))),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Breadcrumbs
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildBreadcrumbs(
    String? currentId,
    List<NoteFolder> allFolders,
    AppPalette palette,
    WidgetRef ref,
  ) {
    final path = <Widget>[];
    
    // Notes root folder breadcrumb target
    path.add(
      DragTarget<Note>(
        onWillAcceptWithDetails: (details) => details.data.folderId != null,
        onAcceptWithDetails: (details) async {
          final note = details.data;
          await ref.read(notesRepositoryProvider).moveNoteToFolder(note.id, null);
        },
        builder: (context, candidateData, rejectedData) {
          final isHovered = candidateData.isNotEmpty;
          return GestureDetector(
            onTap: () => ref.read(currentFolderIdProvider.notifier).setFolder(null),
            child: Text(
              'Notes',
              style: TextStyle(
                color: isHovered
                    ? palette.primary
                    : (currentId == null ? palette.text : palette.text.withValues(alpha: 0.5)),
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
          );
        },
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
        path.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Icon(Icons.chevron_right, color: palette.text.withValues(alpha: 0.3), size: 16),
        ));
        
        path.add(
          DragTarget<Note>(
            onWillAcceptWithDetails: (details) => details.data.folderId != folder.id,
            onAcceptWithDetails: (details) async {
              final note = details.data;
              await ref.read(notesRepositoryProvider).moveNoteToFolder(note.id, folder.id);
            },
            builder: (context, candidateData, rejectedData) {
              final isHovered = candidateData.isNotEmpty;
              return GestureDetector(
                onTap: () => ref.read(currentFolderIdProvider.notifier).setFolder(folder.id),
                child: Text(
                  folder.name,
                  style: TextStyle(
                    color: isHovered
                        ? palette.primary
                        : (folder.id == currentId ? palette.text : palette.text.withValues(alpha: 0.5)),
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
              );
            },
          ),
        );
      }
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: path),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Folders list — each folder is a DragTarget<Note>
  // ─────────────────────────────────────────────────────────────────────────

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
          final isHovered = _dragHoverId == folder.id;

          return DragTarget<Note>(
            onWillAcceptWithDetails: (details) {
              setState(() => _dragHoverId = folder.id);
              return details.data.folderId != folder.id;
            },
            onLeave: (_) => setState(() => _dragHoverId = null),
            onAcceptWithDetails: (details) async {
              setState(() => _dragHoverId = null);
              await ref
                  .read(notesRepositoryProvider)
                  .moveNoteToFolder(details.data.id, folder.id);
            },
            builder: (context, candidateData, rejectedData) {
              return AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 100,
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  color: isHovered
                      ? palette.primary.withValues(alpha: 0.15)
                      : palette.text.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isHovered ? palette.primary : palette.text.withValues(alpha: 0.08),
                    width: isHovered ? 2 : 1,
                  ),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => ref.read(currentFolderIdProvider.notifier).setFolder(folder.id),
                  onLongPress: () => _showDeleteFolderDialog(context, ref, folder),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: (isHovered ? palette.primary : palette.primary).withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                isHovered ? Icons.folder_open : Icons.folder,
                                color: palette.primary,
                                size: 20,
                              ),
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
                            color: isHovered ? palette.primary : palette.text,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Notes grid — each card is Draggable<Note>
  // ─────────────────────────────────────────────────────────────────────────

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
              Text('No notes yet', style: TextStyle(color: palette.text.withValues(alpha: 0.4), fontSize: 14)),
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
                style: TextStyle(color: palette.text.withValues(alpha: 0.5), fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 220,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.9,
              ),
              itemCount: groupNotes.length,
              itemBuilder: (context, noteIdx) {
                final note = groupNotes[noteIdx];
                return _DraggableNoteCard(
                  note: note,
                  palette: palette,
                  onTap: () => _showNoteFormSheet(context, ref, existingNote: note),
                  onLongPress: () => _showDeleteNoteDialog(context, ref, note),
                );
              },
            ),
          ],
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────────────

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

  String _getMonthName(int month) => switch (month) {
    1 => 'Jan', 2 => 'Feb', 3 => 'Mar', 4 => 'Apr',
    5 => 'May', 6 => 'Jun', 7 => 'Jul', 8 => 'Aug',
    9 => 'Sep', 10 => 'Oct', 11 => 'Nov', _ => 'Dec',
  };


  // ─────────────────────────────────────────────────────────────────────────
  // Dialogs
  // ─────────────────────────────────────────────────────────────────────────

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
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: palette.primary)),
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
                  NoteFoldersCompanion.insert(name: name, parentFolderId: Value(parentId)),
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
          'This will permanently delete "${folder.name}". Notes inside will be moved to the parent directory.',
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
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (context, anim1, anim2) {
        return Center(
          child: SingleChildScrollView(
            child: Material(
              color: Colors.transparent,
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom,
                ),
                child: NoteFormSheet(existingNote: existingNote),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, anim1, anim2, child) {
        return ScaleTransition(
          scale: CurvedAnimation(parent: anim1, curve: Curves.easeOutBack),
          child: FadeTransition(opacity: anim1, child: child),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 2. Draggable note card with event shortcut chip
// ─────────────────────────────────────────────────────────────────────────────

class _DraggableNoteCard extends StatelessWidget {
  const _DraggableNoteCard({
    required this.note,
    required this.palette,
    required this.onTap,
    required this.onLongPress,
  });

  final Note note;
  final AppPalette palette;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final card = _NoteCardContent(note: note, palette: palette);

    return Draggable<Note>(
      data: note,
      // Shown while dragging (ghost copy, slightly transparent)
      feedback: Material(
        color: Colors.transparent,
        child: Opacity(
          opacity: 0.85,
          child: SizedBox(
            width: 160,
            height: 170,
            child: card,
          ),
        ),
      ),
      // The original card dims when dragged
      childWhenDragging: Opacity(
        opacity: 0.3,
        child: card,
      ),
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: card,
      ),
    );
  }
}

class _NoteCardContent extends StatelessWidget {
  const _NoteCardContent({required this.note, required this.palette});

  final Note note;
  final AppPalette palette;

  String _formatDate(DateTime dt) {
    final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[dt.month - 1]} ${dt.day}';
  }

  @override
  Widget build(BuildContext context) {
    final hasEventLink = note.eventId != null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.text.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: hasEventLink
              ? palette.primary.withValues(alpha: 0.3)
              : palette.text.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: IgnorePointer(
              child: ClipRect(
                child: MarkdownBody(
                  data: note.content,
                  softLineBreak: true,
                  styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                    p: TextStyle(color: palette.text.withValues(alpha: 0.8), fontSize: 11, height: 1.4),
                    h1: TextStyle(color: palette.text, fontSize: 14, fontWeight: FontWeight.bold),
                    h2: TextStyle(color: palette.text, fontSize: 12, fontWeight: FontWeight.bold),
                    h3: TextStyle(color: palette.text, fontSize: 11, fontWeight: FontWeight.bold),
                    code: TextStyle(color: palette.primary, fontSize: 10),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            note.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: palette.text, fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  _formatDate(note.createdAt),
                  style: TextStyle(color: palette.text.withValues(alpha: 0.4), fontSize: 11),
                ),
              ),
              // ── 2. Event shortcut chip ────────────────────────────
              if (hasEventLink)
                Tooltip(
                  message: 'Linked to calendar event',
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: palette.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.event_outlined, size: 10, color: palette.primary),
                        const SizedBox(width: 3),
                        Text('Event', style: TextStyle(color: palette.primary, fontSize: 10, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}


