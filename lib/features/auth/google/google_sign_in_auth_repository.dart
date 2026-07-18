import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/config/app_config.dart';
import '../../../core/utils/dev_logger.dart';
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
  static bool _gsiInitialized = false;
  bool _initialized = false;

  @override
  Stream<GoogleAuthAccount?> get accountChanges => _accountController.stream;

  @override
  GoogleAuthAccount? get currentAccount => _currentAccount;

  @override
  Future<void> initialize() async {
    if (_initialized) return;

    if (!_gsiInitialized) {
      DevLogger.log('Initializing GoogleSignIn (kIsWeb: $kIsWeb)');
      try {
        await _instance.initialize(
          clientId: kIsWeb ? AppConfig.googleWebClientId : null,
          serverClientId: kIsWeb ? null : AppConfig.googleWebClientId,
        );
        DevLogger.log('GoogleSignIn initialized successfully.');
        _gsiInitialized = true;
      } catch (e, stack) {
        DevLogger.logError('GoogleSignIn initialization failed', e, stack);
        rethrow;
      }
    } else {
      DevLogger.log('GoogleSignIn already initialized globally.');
    }

    _eventSubscription = _instance.authenticationEvents.listen(
      (event) {
        DevLogger.log('GoogleSignIn Auth Event: $event');
        _handleAuthEvent(event);
      },
      onError: (Object error, StackTrace stack) {
        // Stream errors come from failed authenticate() calls, not from
        // explicit sign-out events — don't treat them as sign-out.
        DevLogger.logError('GoogleSignIn event stream error', error, stack);
      },
    );

    _initialized = true;

    // Awaited so that initialize() only resolves AFTER we know whether a
    // previous session exists. This lets the splash-screen redirect see the
    // correct account state immediately rather than racing with the event.
    // Any failure here is non-fatal — the user just lands on /auth.
    try {
      await _instance.attemptLightweightAuthentication();
    } catch (_) {
      // Lightweight auth failed or timed out — no session to restore.
    }
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
    DevLogger.log('Starting Google Sign-In authenticate flow...');
    try {
      await _instance.authenticate();
      DevLogger.log('Google Sign-In authenticate flow call completed.');
    } on GoogleSignInException catch (e, stack) {
      DevLogger.logError('Google Sign-In failed (GoogleSignInException)', e, stack);
      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw const GoogleAuthCancelledException();
      }
      throw GoogleAuthException(e.description ?? e.code.name);
    } catch (e, stack) {
      DevLogger.logError('Google Sign-In failed (generic error)', e, stack);
      throw GoogleAuthException(e.toString());
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
      DevLogger.logError('getAccessToken failed: No account signed in');
      throw const GoogleAuthException('No Google account signed in yet.');
    }

    DevLogger.log('Requesting access token for scopes: $scopes');
    try {
      final existing = await signedInAccount.authorizationClient
          .authorizationForScopes(scopes);
      if (existing != null) {
        DevLogger.log('Found existing authorized access token.');
        return existing.accessToken;
      }

      DevLogger.log('Consent screen required. Triggering authorizeScopes...');
      final authorized =
          await signedInAccount.authorizationClient.authorizeScopes(scopes);
      DevLogger.log('authorizeScopes succeeded.');
      return authorized.accessToken;
    } on GoogleSignInException catch (e, stack) {
      DevLogger.logError('getAccessToken failed (GoogleSignInException)', e, stack);
      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw const GoogleAuthCancelledException();
      }
      throw GoogleAuthException(e.description ?? e.code.name);
    } catch (e, stack) {
      DevLogger.logError('getAccessToken failed (generic error)', e, stack);
      throw GoogleAuthException(e.toString());
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
