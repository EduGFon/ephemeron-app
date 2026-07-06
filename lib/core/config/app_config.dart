/// Central place for the values that differ per environment/deployment.
/// Nothing here is a secret in the traditional sense (OAuth client IDs are
/// public identifiers, not credentials) — but keeping them in one file
/// means Step 4 (Calendar) and any future desktop auth implementation
/// don't need to hunt for magic strings scattered across the codebase.
abstract final class AppConfig {
  /// Web OAuth client ID (type "Web application" in Google Cloud Console).
  /// Required by google_sign_in on Web; NOT used on Android, where the
  /// SDK resolves the client via the package name + SHA-1 fingerprint
  /// registered against your Android-type OAuth client instead.
  /// TODO: replace with your real Web client ID before running on Web.
  static const String googleWebClientId =
      'REPLACE_ME.apps.googleusercontent.com';

  /// Desktop OAuth client ID (type "Desktop application" in Google Cloud Console).
  /// Required for Linux/macOS/Windows custom loopback OAuth2 flow.
  static const String googleDesktopClientId =
      'REPLACE_ME.apps.googleusercontent.com';

  /// Desktop OAuth client secret (Google recommends PKCE, but desktop type clients
  /// still require client secret parameter in the token endpoint, even if empty/public).
  static const String googleDesktopClientSecret = 'REPLACE_ME';

  /// Calendar scope requested during authorization (kept separate from
  /// sign-in/identity, per google_sign_in v7's split between
  /// authentication and authorization).
  static const String googleCalendarScope =
      'https://www.googleapis.com/auth/calendar';

  /// Tasks scope — used for the best-effort Google Tasks mirror (Step 3).
  /// Requested together with the Calendar scope in one authorization
  /// round wherever possible, rather than prompting the user twice.
  static const String googleTasksScope =
      'https://www.googleapis.com/auth/tasks';

  /// Base URL for your own backend (tasks/habits storage + its own
  /// auth). No backend exists yet as of Step 1 — this points at a local
  /// placeholder on purpose, so failed requests fail loudly and obviously
  /// rather than silently hitting something real.
  /// TODO: replace once the backend is deployed.
  static const String backendBaseUrl = 'http://localhost:8787';
}
