import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'google_auth_repository.dart';
import 'google_sign_in_auth_repository.dart';
import 'desktop_google_auth_repository_stub.dart' if (dart.library.io) 'desktop_google_auth_repository.dart';

final googleAuthRepositoryProvider = Provider<GoogleAuthRepository>((ref) {
  final GoogleAuthRepository repo;
  if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.linux || defaultTargetPlatform == TargetPlatform.windows || defaultTargetPlatform == TargetPlatform.macOS)) {
    repo = DesktopGoogleAuthRepository();
  } else {
    repo = GoogleSignInAuthRepository();
  }
  ref.onDispose(() {
    if (repo is GoogleSignInAuthRepository) {
      repo.dispose();
    } else if (repo is DesktopGoogleAuthRepository) {
      repo.dispose();
    }
  });
  return repo;
});

/// Runs [GoogleAuthRepository.initialize] exactly once. Other providers
/// depend on this future rather than calling initialize() themselves, so
/// initialization never races even if several widgets watch Google auth
/// state at once during startup.
final googleAuthInitProvider = FutureProvider<void>((ref) async {
  final repo = ref.watch(googleAuthRepositoryProvider);
  await repo.initialize();
});

/// Reactive current-account stream. Yields the already-known value first
/// (in case sign-in resolved before this provider had a listener), then
/// forwards subsequent changes.
final googleAccountProvider = StreamProvider<GoogleAuthAccount?>((ref) async* {
  await ref.watch(googleAuthInitProvider.future);
  final repo = ref.watch(googleAuthRepositoryProvider);
  yield repo.currentAccount;
  yield* repo.accountChanges;
});
