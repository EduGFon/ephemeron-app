import 'dart:async' show unawaited;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/theme_engine_provider.dart';
import '../../../core/config/app_config.dart';
import '../backend/backend_auth_provider.dart';
import '../backend/backend_auth_repository.dart';
import '../google/google_auth_provider.dart';
import '../google/google_auth_repository.dart';
import 'google_sign_in_button.dart';
import '../../../core/utils/safe_secure_storage.dart';
import '../../sync/application/sync_service.dart';

class AuthScreen extends ConsumerWidget {
  const AuthScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Connect your accounts')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Ephemeron needs two independent connections. Neither one '
              'can see the other\'s data.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            const _GoogleCalendarCard(),
            const SizedBox(height: 16),
            const _BackendAccountCard(),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () async {
                final prefs = await SharedPreferences.getInstance();
                final lastScreen = prefs.getString('settings.lastScreen') ?? '/calendar';
                if (context.mounted) {
                  context.go(lastScreen);
                }
              },
              child: const Text('Continue'),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                'You can connect either one later from Settings.',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GoogleCalendarCard extends ConsumerWidget {
  const _GoogleCalendarCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountAsync = ref.watch(googleAccountProvider);
    final palette = ref.watch(themeEngineProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.calendar_month_outlined),
                const SizedBox(width: 8),
                Text('Google Calendar', style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Your events stay in your own Google account — this app '
              'never sends calendar data through a server.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            accountAsync.when(
              data: (account) => account == null
                  ? buildGoogleSignInButton(
                      onPressed: () => _signIn(context, ref),
                      palette: palette,
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: Text(
                            account.email,
                            style: Theme.of(context).textTheme.bodyLarge,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        TextButton(
                          onPressed: () =>
                              ref.read(googleAuthRepositoryProvider).signOut(),
                          child: const Text('Disconnect'),
                        ),
                      ],
                    ),
              loading: () => const LinearProgressIndicator(),
              error: (error, _) => Text(
                'Could not check Google sign-in status.',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _signIn(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(googleAuthRepositoryProvider).signIn();
      // Pre-authorize both scopes we know we'll need (Calendar + Tasks)
      // in this one round, rather than letting each feature request its
      // own scope lazily later and prompt the user a second time.
      // Best-effort: a failure/decline here shouldn't undo the sign-in
      // that already succeeded above — Calendar/Tasks features will
      // simply re-prompt individually if this didn't go through.
      try {
        await ref.read(googleAuthRepositoryProvider).getAccessToken(const [
          AppConfig.googleCalendarScope,
          AppConfig.googleTasksScope,
        ]);
      } on Exception {
        // Swallowed on purpose — see comment above.
      }
      // Trigger sync immediately after successful sign-in
      unawaited(ref.read(syncServiceProvider.notifier).sync());
    } on GoogleAuthCancelledException {
      // User backed out — not an error, nothing to show.
    } on GoogleAuthException catch (e) {
      if (context.mounted) {
        if (e.message.contains('Client ID is not configured')) {
          unawaited(_showCredentialsDialog(context));
        } else {
          _showError(context, e.message);
        }
      }
    }
  }

  Future<void> _showCredentialsDialog(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    const storage = SafeSecureStorage();
    final customSecret = await storage.read(key: 'google.desktop.customClientSecret') ?? '';
    final idController = TextEditingController(text: prefs.getString('google.desktop.customClientId') ?? '');
    final secretController = TextEditingController(text: customSecret);

    if (!context.mounted) return;

    unawaited(showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Google OAuth Credentials'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enter your own Google OAuth Client ID and Secret for Desktop (type "Desktop application" in Google Cloud Console).',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: idController,
              decoration: const InputDecoration(
                labelText: 'Client ID',
                hintText: 'xxxx.apps.googleusercontent.com',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: secretController,
              decoration: const InputDecoration(
                labelText: 'Client Secret',
                hintText: 'Required by Google Cloud Console',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final id = idController.text.trim();
              final secret = secretController.text.trim();
              if (id.isNotEmpty && secret.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Client Secret is required when Client ID is provided.')),
                );
                return;
              }
              final prefs = await SharedPreferences.getInstance();
              if (id.isEmpty) {
                await prefs.remove('google.desktop.customClientId');
                await storage.delete(key: 'google.desktop.customClientSecret');
              } else {
                await prefs.setString('google.desktop.customClientId', id);
                await storage.write(key: 'google.desktop.customClientSecret', value: secret);
              }
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ));
  }

  void _showError(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _BackendAccountCard extends ConsumerStatefulWidget {
  const _BackendAccountCard();

  @override
  ConsumerState<_BackendAccountCard> createState() => _BackendAccountCardState();
}

class _BackendAccountCardState extends ConsumerState<_BackendAccountCard> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isRegisterMode = false;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sessionAsync = ref.watch(backendSessionProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.checklist_outlined),
                const SizedBox(width: 8),
                Text('Tasks & Habits account', style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Separate from Google — this is your own Ephemeron account, '
              'used only for tasks and habits.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            sessionAsync.when(
              data: (session) =>
                  session == null ? _buildForm(context) : _buildLoggedIn(context, session),
              loading: () => const LinearProgressIndicator(),
              error: (error, _) => Text(
                'Could not restore session.',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoggedIn(BuildContext context, BackendSession session) {
    return Row(
      children: [
        Expanded(
          child: Text(
            session.email,
            style: Theme.of(context).textTheme.bodyLarge,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        TextButton(
          onPressed: () => ref.read(backendAuthRepositoryProvider).logout(),
          child: const Text('Log out'),
        ),
      ],
    );
  }

  Widget _buildForm(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'Email'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _passwordController,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Password'),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 8),
          Text(
            _errorMessage!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_isRegisterMode ? 'Create account' : 'Log in'),
        ),
        TextButton(
          onPressed: _isSubmitting
              ? null
              : () => setState(() => _isRegisterMode = !_isRegisterMode),
          child: Text(
            _isRegisterMode
                ? 'Already have an account? Log in'
                : "Don't have an account? Create one",
          ),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || !email.contains('@')) {
      setState(() => _errorMessage = 'Enter a valid email address.');
      return;
    }
    if (password.length < 8) {
      setState(() => _errorMessage = 'Password must be at least 8 characters.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final repo = ref.read(backendAuthRepositoryProvider);
      if (_isRegisterMode) {
        await repo.register(email: email, password: password);
      } else {
        await repo.login(email: email, password: password);
      }
    } on BackendAuthException catch (e) {
      setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}
