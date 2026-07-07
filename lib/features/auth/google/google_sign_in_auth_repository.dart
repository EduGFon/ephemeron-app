import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/config/app_config.dart';
import 'google_auth_repository.dart';

/// Implements [GoogleAuthRepository] on top of google_sign_in ^7.x.
///
/// Worth knowing if you've used this package before v7: the API changed
/// significantly (singleton instance, explicit initialize(), separate
/// authenticate()/authorizationClient calls instead of one signIn()
/// method). This class is written against the current API — see
/// https://pub.dev/packages/google_sign_in for the canonical reference if
/// something here looks unfamiliar.
// `extends`, not `implements` — GoogleAuthRepository provides a concrete
// default body for getCalendarAccessToken(); `implements` would treat it
// as a pure interface and require re-implementing that method here too.
// Found during real-device testing (surfaced as a missing-implementation
// compile error).
class GoogleSignInAuthRepository extends GoogleAuthRepository {
  GoogleSignInAuthRepository() : _instance = GoogleSignIn.instance;

  final GoogleSignIn _instance;
  final _accountController = StreamController<GoogleAuthAccount?>.broadcast();
  StreamSubscription<GoogleSignInAuthenticationEvent>? _eventSubscription;
  // v7 removed GoogleSignIn.currentUser — the SDK no longer tracks "who's
  // signed in" for you, so this class does, from the authentication
  // events stream. _signedInAccount is the raw SDK object (needed for
  // .authorizationClient); _currentAccount is our stripped-down app model.
  GoogleSignInAccount? _signedInAccount;
  GoogleAuthAccount? _currentAccount;
  bool _initialized = false;

  @override
  Stream<GoogleAuthAccount?> get accountChanges => _accountController.stream;

  @override
  GoogleAuthAccount? get currentAccount => _currentAccount;

  @override
  Future<void> initialize() async {
    if (_initialized) return;

    await _instance.initialize(
      // Only Web needs an explicit client ID here — Android resolves the
      // OAuth client via the package name + SHA-1 fingerprint registered
      // in Cloud Console instead.
      clientId: kIsWeb ? AppConfig.googleWebClientId : null,
      serverClientId: kIsWeb ? null : AppConfig.googleWebClientId,
    );

    _eventSubscription = _instance.authenticationEvents.listen(
      _handleAuthEvent,
      onError: (Object error) {
        // Surfaced as a signed-out state; the sign-in button remains the
        // recovery path rather than crashing app startup over this.
        _currentAccount = null;
        _accountController.add(null);
      },
    );

    _initialized = true;

    // Fire-and-forget: if a previous session exists, it'll arrive via
    // the event stream above shortly. Not awaited on purpose — startup
    // shouldn't block on this.
    unawaited(_instance.attemptLightweightAuthentication());
  }

  void _handleAuthEvent(GoogleSignInAuthenticationEvent event) {
    switch (event) {
      case GoogleSignInAuthenticationEventSignIn():
        _signedInAccount = event.user;
        _currentAccount = _toAppAccount(event.user);
        _accountController.add(_currentAccount);
      default:
        _signedInAccount = null;
        _currentAccount = null;
        _accountController.add(null);
    }
  }

  GoogleAuthAccount _toAppAccount(GoogleSignInAccount account) {
    return GoogleAuthAccount(
      id: account.id,
      email: account.email,
      displayName: account.displayName,
      photoUrl: account.photoUrl,
    );
  }

  @override
  Future<void> signIn() async {
    _ensureInitialized();
    try {
      await _instance.authenticate();
      // Resulting state arrives via the event stream (_handleAuthEvent),
      // kept as the single source of truth rather than also setting
      // state from this method's return value.
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw const GoogleAuthCancelledException();
      }
      throw GoogleAuthException(e.description ?? e.code.name);
    }
  }

  @override
  Future<void> signOut() async {
    _ensureInitialized();
    await _instance.signOut();
    _signedInAccount = null;
    _currentAccount = null;
    _accountController.add(null);
  }

  @override
  Future<String> getAccessToken(List<String> scopes) async {
    _ensureInitialized();
    final signedInAccount = _signedInAccount;
    if (signedInAccount == null) {
      throw const GoogleAuthException('No Google account signed in yet.');
    }

    try {
      // Try silently first — succeeds if the user already granted these
      // scopes in a previous session and they haven't expired.
      final existing = await signedInAccount.authorizationClient
          .authorizationForScopes(scopes);
      if (existing != null) return existing.accessToken;

      // Falls back to an interactive consent screen. Must be reachable
      // from a user gesture on platforms that enforce it.
      final authorized =
          await signedInAccount.authorizationClient.authorizeScopes(scopes);
      return authorized.accessToken;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw const GoogleAuthCancelledException();
      }
      throw GoogleAuthException(e.description ?? e.code.name);
    }
  }

  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError(
        'GoogleSignInAuthRepository.initialize() must be called and '
        'awaited before use.',
      );
    }
  }

  void dispose() {
    _eventSubscription?.cancel();
    _accountController.close();
  }
}
