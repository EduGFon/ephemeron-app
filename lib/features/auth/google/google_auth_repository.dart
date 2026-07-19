import '../../../core/config/app_config.dart';

/// Minimal identity info from a signed-in Google account. Deliberately
/// small — this app never sends this (or anything else Google-related) to
/// our own backend, so it doesn't need to carry anything beyond what the
/// UI displays.
class GoogleAuthAccount {
  const GoogleAuthAccount({
    required this.id,
    required this.email,
    this.displayName,
    this.photoUrl,
  });

  final String id;
  final String email;
  final String? displayName;
  final String? photoUrl;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GoogleAuthAccount &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          email == other.email &&
          displayName == other.displayName &&
          photoUrl == other.photoUrl;

  @override
  int get hashCode => Object.hash(id, email, displayName, photoUrl);
}

/// Thrown when the user cancels a sign-in or authorization prompt — a
/// normal, expected outcome, not an error condition the UI should show a
/// scary message for.
class GoogleAuthCancelledException implements Exception {
  const GoogleAuthCancelledException();
}

/// Thrown for genuine failures (network, misconfiguration, etc).
class GoogleAuthException implements Exception {
  const GoogleAuthException(this.message);
  final String message;

  @override
  String toString() => 'GoogleAuthException: $message';
}

/// Contract for Google identity + Calendar-scope authorization. Split
/// into two concerns on purpose, matching Google's own current model:
/// "who is signed in" (authentication) is separate from "what have they
/// granted access to" (authorization) — a Calendar-scope grant can be
/// revoked or expire independently of the underlying sign-in.
///
/// Current implementation ([GoogleSignInAuthRepository]) covers Android +
/// Web only, matching MVP priority. A desktop implementation (Windows/
/// Linux, via a loopback-redirect OAuth flow) can be added later as an
/// alternate implementation of this same interface — nothing above this
/// layer needs to change when that happens.
abstract class GoogleAuthRepository {
  /// Must be called once before any other method, typically at app
  /// startup. Also attempts to silently restore a previous session.
  Future<void> initialize();

  /// Emits the current account, or null when signed out. This is the
  /// single source of truth for "is a Google account connected" —
  /// prefer watching this over relying on the return value of [signIn].
  Stream<GoogleAuthAccount?> get accountChanges;

  GoogleAuthAccount? get currentAccount;

  /// Starts an interactive sign-in. Must be called from a user gesture
  /// (e.g. a button's onPressed) — some platforms require this.
  /// Throws [GoogleAuthCancelledException] if the user backs out.
  Future<void> signIn();

  Future<void> signOut();

  /// Returns a valid access token authorized for every scope in
  /// [scopes], requesting the user's consent interactively if any of
  /// them haven't been granted yet. Introduced in Step 3 (Tasks needs
  /// its own scope alongside Calendar's) — request scopes together in
  /// one call wherever a feature needs more than one, rather than
  /// prompting the user twice.
  ///
  /// Must be called from a user gesture the first time (or after
  /// expiry) — silent renewal is attempted first internally, but falls
  /// back to an interactive prompt when that's not possible.
  /// Throws [GoogleAuthCancelledException] or [GoogleAuthException].
  Future<String> getAccessToken(
    List<String> scopes, {
    bool promptIfNecessary = false,
  });

  /// Convenience wrapper for the common single-scope Calendar case —
  /// kept from Step 1 so existing call sites don't need to change.
  Future<String> getCalendarAccessToken({bool promptIfNecessary = false}) =>
      getAccessToken(
        const [AppConfig.googleCalendarScope],
        promptIfNecessary: promptIfNecessary,
      );
}
