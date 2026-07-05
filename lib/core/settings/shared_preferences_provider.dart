import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

late final SharedPreferences sharedPrefs;

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  return sharedPrefs;
});
