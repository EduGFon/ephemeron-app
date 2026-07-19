import 'google_auth_repository.dart';

class DesktopGoogleAuthRepository implements GoogleAuthRepository {
  @override
  GoogleAuthAccount? get currentAccount => null;

  @override
  Stream<GoogleAuthAccount?> get accountChanges => const Stream.empty();

  @override
  Future<void> initialize() async {}

  @override
  Future<void> signIn() async {}

  @override
  Future<void> signOut() async {}
  
  @override
  Future<String?> getAccessToken() async => null;

  void dispose() {}
}
