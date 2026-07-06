import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/local/database.dart';
import '../data/notes_repository.dart';

class CurrentFolderNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  void setFolder(String? id) => state = id;
}

final currentFolderIdProvider = NotifierProvider<CurrentFolderNotifier, String?>(
  () => CurrentFolderNotifier(),
);

final notesStreamProvider = StreamProvider<List<Note>>((ref) {
  return ref.watch(notesRepositoryProvider).watchAllNotes();
});

final foldersStreamProvider = StreamProvider<List<NoteFolder>>((ref) {
  return ref.watch(notesRepositoryProvider).watchAllFolders();
});
