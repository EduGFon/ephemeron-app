import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/auth_screen.dart';
import '../../presentation/shell/app_shell.dart';
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

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    // Auth screen shown first, deliberately not gated by a redirect yet
    // (that needs a Listenable bridged from Riverpod's auth streams,
    // which is its own focused piece of work — see the router file's
    // top comment). For now "Continue" just navigates on regardless of
    // auth state, same as a skip button.
    initialLocation: '/auth',
    debugLogDiagnostics: false,
    routes: [
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
