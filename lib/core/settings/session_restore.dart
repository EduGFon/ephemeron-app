import 'package:shared_preferences/shared_preferences.dart';

class SessionRestore {
  SessionRestore._();

  static Future<void> saveOpenMenu(String menu, {String? entityId, String? extra}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('session.openMenu', menu);
      await prefs.setString('session.openMenuEntityId', entityId ?? '');
      await prefs.setString('session.openMenuExtra', extra ?? '');
    } catch (_) {}
  }

  static Future<void> clearOpenMenu() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('session.openMenu', 'none');
      await prefs.setString('session.openMenuEntityId', '');
      await prefs.setString('session.openMenuExtra', '');
    } catch (_) {}
  }
}
