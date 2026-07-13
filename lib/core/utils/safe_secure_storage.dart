import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A wrapper around FlutterSecureStorage that falls back to SharedPreferences
/// if secure storage throws an exception (e.g. KeyringLocked on Linux).
class SafeSecureStorage {
  const SafeSecureStorage();

  static const _storage = FlutterSecureStorage();

  Future<void> write({required String key, required String value}) async {
    try {
      await _storage.write(key: key, value: value);
    } catch (_) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('fallback_secure_$key', value);
    }
  }

  Future<String?> read({required String key}) async {
    try {
      final val = await _storage.read(key: key);
      if (val != null) return val;
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('fallback_secure_$key');
  }

  Future<void> delete({required String key}) async {
    try {
      await _storage.delete(key: key);
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('fallback_secure_$key');
  }
}
