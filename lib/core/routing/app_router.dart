import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/auth/google/google_auth_provider.dart';
import '../../features/auth/presentation/auth_screen.dart';
import '../../presentation/shell/app_shell.dart';
import '../../presentation/splash/splash_screen.dart';
import '../../features/calendar/presentation/calendar_screen.dart';
import '../../features/tasks/presentation/tasks_screen.dart';
import '../../features/matrix/presentation/matrix_screen.dart';
import '../../features/habits/presentation/habits_screen.dart';
import '../../features/countdown/presentation/countdown_screen.dart';
import '../../features/focus/presentation/focus_screen.dart';
import '../../presentation/notes/notes_screen.dart';
import 'root_navigator_key.dart';

/// Branch order here is load-bearing: it must match NavSection's
/// branchIndex values exactly (calendar=0 ... notes=6). All 7 branches
/// are always defined, regardless of which ones are currently pinned to
/// the visible bottom bar — that's a presentation-layer decision made in
/// AppShell, not a routing one. Keeping routing static like this avoids
/// the real complexity of reconfiguring go_router itself at runtime.
/// Navigator key lives in root_navigator_key.dart — shared with
/// alarm_scheduler.dart, see that file's usage for why.

/// ChangeNotifier bridging both the auth init future and the account
/// stream to GoRouter's refreshListenable, so redirects fire whenever
/// either init completes or the user signs in/out.
class _AuthNotifier extends ChangeNotifier {
  _AuthNotifier(Ref ref) {
    ref.listen(googleAuthInitProvider, (_, __) => notifyListeners());
    ref.listen(googleAccountProvider, (_, __) => notifyListeners());
  }
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final authNotifier = _AuthNotifier(ref);

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    // Start on /splash — it shows a spinner and waits for auth init.
    // The redirect below takes over as soon as init resolves, so the
    // user never sees /auth if they were already signed in.
    initialLocation: '/splash',
    debugLogDiagnostics: false,
    refreshListenable: authNotifier,
    redirect: (context, state) async {
      final location = state.matchedLocation;
      final initAsync = ref.read(googleAuthInitProvider);

      // While google_sign_in is still initializing, stay on /splash.
      if (initAsync.isLoading) {
        return location == '/splash' ? null : '/splash';
      }

      final accountAsync = ref.read(googleAccountProvider);
      final isSignedIn = !accountAsync.isLoading &&
          accountAsync.whenData((a) => a).value != null;

      if (location == '/splash' || location == '/auth') {
        if (isSignedIn) {
          // Session restored — jump straight to last-used screen.
          final prefs = await SharedPreferences.getInstance();
          return prefs.getString('settings.lastScreen') ?? '/calendar';
        }
        // Not signed in yet: /splash → /auth; /auth stays on /auth.
        return location == '/splash' ? '/auth' : null;
      }

      // Signed out while on a main screen → back to /auth.
      if (!isSignedIn && location != '/auth') return '/auth';

      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/auth',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const AuthScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return AppShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/calendar',
                builder: (context, state) => const CalendarScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/tasks',
                builder: (context, state) => const TasksScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/matrix',
                builder: (context, state) => const MatrixScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/habits',
                builder: (context, state) => const HabitsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/countdown',
                builder: (context, state) => const CountdownScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/focus',
                builder: (context, state) => const FocusScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/notes',
                builder: (context, state) => const NotesScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
