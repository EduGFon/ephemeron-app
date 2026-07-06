import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/local/database.dart';
import '../../../data/local/database_provider.dart';

final notesRepositoryProvider = Provider<NotesRepository>((ref) {
  return NotesRepository(ref.watch(appDatabaseProvider));
});

class NotesRepository {
  final AppDatabase _db;
  NotesRepository(this._db);

  Stream<List<Note>> watchAllNotes() {
    return _db.select(_db.notes).watch();
  }

  Stream<List<Note>> watchNotesByEventId(String eventId) {
    return (_db.select(_db.notes)..where((n) => n.eventId.equals(eventId))).watch();
  }

  Stream<List<NoteFolder>> watchAllFolders() {
    return _db.select(_db.noteFolders).watch();
  }

  Future<void> createNote(NotesCompanion companion) async {
    await _db.into(_db.notes).insert(companion);
  }

  Future<void> updateNote(NotesCompanion companion) async {
    await _db.update(_db.notes).replace(companion);
  }

  Future<void> deleteNote(String id) async {
    await (_db.delete(_db.notes)..where((n) => n.id.equals(id))).go();
  }

  Future<void> createFolder(NoteFoldersCompanion companion) async {
    await _db.into(_db.noteFolders).insert(companion);
  }

  Future<void> deleteFolder(String id) async {
    await (_db.delete(_db.noteFolders)..where((f) => f.id.equals(id))).go();
    await (_db.update(_db.notes)..where((n) => n.folderId.equals(id)))
        .write(const NotesCompanion(folderId: Value(null)));
  }

  /// Move [noteId] into [targetFolderId] (null = root).
  Future<void> moveNoteToFolder(String noteId, String? targetFolderId) async {
    await (_db.update(_db.notes)..where((n) => n.id.equals(noteId)))
        .write(NotesCompanion(folderId: Value(targetFolderId), updatedAt: Value(DateTime.now())));
  }
}
