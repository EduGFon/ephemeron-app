import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the backend refresh token in platform-native secure storage
/// (Keystore on Android, Keychain on iOS/macOS, DPAPI on Windows,
/// libsecret on Linux, IndexedDB-with-encryption on Web) rather than
/// SharedPreferences/Drift — a long-lived bearer credential shouldn't
/// sit in plaintext-accessible storage.
///
/// The short-lived access token is kept in memory only (not persisted):
/// it's cheap to re-derive from the refresh token on cold start, and
/// keeping it out of storage entirely shrinks what a filesystem-level
/// compromise could expose.
class SecureTokenStorage {
  const SecureTokenStorage._();

  static const _storage = FlutterSecureStorage();

  static const _refreshTokenKey = 'backend.refreshToken';
  static const _userIdKey = 'backend.userId';
  static const _emailKey = 'backend.email';

  static Future<void> saveSession({
    required String refreshToken,
    required String userId,
    required String email,
  }) async {
    await Future.wait([
      _storage.write(key: _refreshTokenKey, value: refreshToken),
      _storage.write(key: _userIdKey, value: userId),
      _storage.write(key: _emailKey, value: email),
    ]);
  }

  static Future<({String refreshToken, String userId, String email})?>
  readSession() async {
    final values = await Future.wait([
      _storage.read(key: _refreshTokenKey),
      _storage.read(key: _userIdKey),
      _storage.read(key: _emailKey),
    ]);
    final refreshToken = values[0];
    final userId = values[1];
    final email = values[2];
    if (refreshToken == null || userId == null || email == null) return null;
    return (refreshToken: refreshToken, userId: userId, email: email);
  }

  static Future<void> clear() async {
    await Future.wait([
      _storage.delete(key: _refreshTokenKey),
      _storage.delete(key: _userIdKey),
      _storage.delete(key: _emailKey),
    ]);
  }
}
