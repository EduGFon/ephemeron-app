import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/config/app_config.dart';
import '../../../core/utils/safe_secure_storage.dart';
import 'google_auth_repository.dart';

class DesktopGoogleAuthRepository extends GoogleAuthRepository {
  DesktopGoogleAuthRepository();

  final _accountController = StreamController<GoogleAuthAccount?>.broadcast();
  final _storage = const SafeSecureStorage();
  
  GoogleAuthAccount? _currentAccount;
  String? _accessToken;
  DateTime? _tokenExpiry;
  bool _initialized = false;

  @override
  Stream<GoogleAuthAccount?> get accountChanges => _accountController.stream;

  @override
  GoogleAuthAccount? get currentAccount => _currentAccount;

  @override
  Future<void> initialize() async {
    if (_initialized) return;

    final prefs = await SharedPreferences.getInstance();
    final accountId = prefs.getString('google.desktop.accountId');
    final accountEmail = prefs.getString('google.desktop.accountEmail');
    final accountName = prefs.getString('google.desktop.accountName');
    final accountPhoto = prefs.getString('google.desktop.accountPhoto');
    
    _accessToken = await _storage.read(key: 'google.desktop.accessToken');
    final expiryStr = await _storage.read(key: 'google.desktop.tokenExpiry');
    if (expiryStr != null) {
      _tokenExpiry = DateTime.tryParse(expiryStr);
    }

    if (accountId != null && accountEmail != null) {
      _currentAccount = GoogleAuthAccount(
        id: accountId,
        email: accountEmail,
        displayName: accountName,
        photoUrl: accountPhoto,
      );
      _accountController.add(_currentAccount);
    }

    _initialized = true;

    // Try silent refresh if we have a refresh token
    unawaited(_trySilentRefresh());
  }

  Future<void> _trySilentRefresh() async {
    try {
      final refreshToken = await _storage.read(key: 'google.desktop.refreshToken');
      if (refreshToken != null) {
        await _refreshAccessToken(refreshToken);
      }
    } catch (_) {
      // Ignore background errors
    }
  }

  Future<String> _getClientId() async {
    if (!AppConfig.googleDesktopClientId.startsWith('REPLACE_ME')) {
      return AppConfig.googleDesktopClientId;
    }
    final prefs = await SharedPreferences.getInstance();
    final customId = prefs.getString('google.desktop.customClientId');
    if (customId != null && customId.isNotEmpty) {
      return customId;
    }
    throw const GoogleAuthException(
      'Google Client ID is not configured. Please set it in Settings -> Google Account.',
    );
  }

  Future<String> _getClientSecret() async {
    if (!AppConfig.googleDesktopClientSecret.startsWith('REPLACE_ME')) {
      return AppConfig.googleDesktopClientSecret;
    }
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('google.desktop.customClientSecret') ?? '';
  }

  @override
  Future<void> signIn() async {
    _ensureInitialized();

    final clientId = await _getClientId();
    final clientSecret = await _getClientSecret();

    // 1. Bind local loopback HTTP server
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final port = server.port;
    final redirectUri = 'http://localhost:$port';

    // 2. State & PKCE (Google doesn't strictly require PKCE on loopback but it is best practice)
    final state = DateTime.now().millisecondsSinceEpoch.toString();

    // 3. Construct Authorization URL
    final scopes = [
      'openid',
      'email',
      'profile',
      AppConfig.googleCalendarScope,
      AppConfig.googleTasksScope,
    ].join(' ');

    final authUrl = 'https://accounts.google.com/o/oauth2/v2/auth'
        '?client_id=$clientId'
        '&redirect_uri=${Uri.encodeComponent(redirectUri)}'
        '&response_type=code'
        '&scope=${Uri.encodeComponent(scopes)}'
        '&state=$state'
        '&prompt=consent'
        '&access_type=offline';

    // 4. Launch browser
    await _launchBrowser(authUrl);

    // 5. Listen for redirect
    String? authCode;
    try {
      await for (final request in server.timeout(const Duration(minutes: 5))) {
        final queryParams = request.uri.queryParameters;
        if (queryParams['state'] == state) {
          authCode = queryParams['code'];
          
          request.response.headers.contentType = ContentType.html;
          request.response.write('''
            <!DOCTYPE html>
            <html>
            <head>
              <title>Authentication Successful</title>
              <style>
                body {
                  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
                  background-color: #121212;
                  color: #ffffff;
                  display: flex;
                  flex-direction: column;
                  align-items: center;
                  justify-content: center;
                  height: 100vh;
                  margin: 0;
                }
                .card {
                  background-color: #1e1e1e;
                  padding: 2rem;
                  border-radius: 16px;
                  box-shadow: 0 4px 20px rgba(0,0,0,0.5);
                  text-align: center;
                }
                h1 { color: #8ab4f8; margin-top: 0; }
                p { color: #aaa; }
              </style>
            </head>
            <body>
              <div class="card">
                <h1>Authentication Complete</h1>
                <p>Ephemeron has been authorized successfully.</p>
                <p>You can close this tab and return to the app.</p>
              </div>
            </body>
            </html>
          ''');
          await request.response.close();
          break;
        } else {
          request.response.statusCode = HttpStatus.badRequest;
          request.response.write('Invalid state parameter.');
          await request.response.close();
        }
      }
    } catch (e) {
      throw GoogleAuthException('Authentication timed out or failed: $e');
    } finally {
      await server.close(force: true);
    }

    if (authCode == null) {
      throw const GoogleAuthException('Failed to obtain authorization code.');
    }

    // 6. Exchange Code for Tokens
    final response = await http.post(
      Uri.parse('https://oauth2.googleapis.com/token'),
      body: {
        'client_id': clientId,
        if (clientSecret.isNotEmpty) 'client_secret': clientSecret,
        'code': authCode,
        'grant_type': 'authorization_code',
        'redirect_uri': redirectUri,
      },
    );

    if (response.statusCode != HttpStatus.ok) {
      throw GoogleAuthException('Failed to exchange authorization code: ${response.body}');
    }

    final tokenData = jsonDecode(response.body) as Map<String, dynamic>;
    final accessToken = tokenData['access_token'] as String;
    final refreshToken = tokenData['refresh_token'] as String?;
    final expiresIn = tokenData['expires_in'] as int? ?? 3600;

    _accessToken = accessToken;
    _tokenExpiry = DateTime.now().add(Duration(seconds: expiresIn));

    // 7. Get User Info
    final userInfoResponse = await http.get(
      Uri.parse('https://www.googleapis.com/oauth2/v3/userinfo'),
      headers: {'Authorization': 'Bearer $accessToken'},
    );

    if (userInfoResponse.statusCode != HttpStatus.ok) {
      throw GoogleAuthException('Failed to fetch user info: ${userInfoResponse.body}');
    }

    final userData = jsonDecode(userInfoResponse.body) as Map<String, dynamic>;
    final id = userData['sub'] as String;
    final email = userData['email'] as String;
    final name = userData['name'] as String?;
    final picture = userData['picture'] as String?;

    // 8. Persist details
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('google.desktop.accountId', id);
    await prefs.setString('google.desktop.accountEmail', email);
    if (name != null) await prefs.setString('google.desktop.accountName', name);
    if (picture != null) await prefs.setString('google.desktop.accountPhoto', picture);

    await _storage.write(key: 'google.desktop.accessToken', value: accessToken);
    await _storage.write(key: 'google.desktop.tokenExpiry', value: _tokenExpiry!.toIso8601String());
    if (refreshToken != null) {
      await _storage.write(key: 'google.desktop.refreshToken', value: refreshToken);
    }

    _currentAccount = GoogleAuthAccount(
      id: id,
      email: email,
      displayName: name,
      photoUrl: picture,
    );
    _accountController.add(_currentAccount);
  }

  @override
  Future<void> signOut() async {
    _ensureInitialized();
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('google.desktop.accountId');
    await prefs.remove('google.desktop.accountEmail');
    await prefs.remove('google.desktop.accountName');
    await prefs.remove('google.desktop.accountPhoto');

    await _storage.delete(key: 'google.desktop.accessToken');
    await _storage.delete(key: 'google.desktop.refreshToken');
    await _storage.delete(key: 'google.desktop.tokenExpiry');

    _accessToken = null;
    _tokenExpiry = null;
    _currentAccount = null;
    _accountController.add(null);
  }

  @override
  Future<String> getAccessToken(List<String> scopes) async {
    _ensureInitialized();

    final currentExpiry = _tokenExpiry;
    final accessToken = _accessToken;

    if (accessToken != null && currentExpiry != null && currentExpiry.isAfter(DateTime.now().add(const Duration(minutes: 5)))) {
      return accessToken;
    }

    // Refresh token needed
    final refreshToken = await _storage.read(key: 'google.desktop.refreshToken');
    if (refreshToken == null) {
      throw const GoogleAuthException('No refresh token available. Please sign in again.');
    }

    return _refreshAccessToken(refreshToken);
  }

  Future<String> _refreshAccessToken(String refreshToken) async {
    final clientId = await _getClientId();
    final clientSecret = await _getClientSecret();

    final response = await http.post(
      Uri.parse('https://oauth2.googleapis.com/token'),
      body: {
        'client_id': clientId,
        if (clientSecret.isNotEmpty) 'client_secret': clientSecret,
        'refresh_token': refreshToken,
        'grant_type': 'refresh_token',
      },
    );

    if (response.statusCode != HttpStatus.ok) {
      // If refresh token is revoked/invalid, sign out automatically
      await signOut();
      throw GoogleAuthException('Session expired or refresh failed: ${response.body}');
    }

    final tokenData = jsonDecode(response.body) as Map<String, dynamic>;
    final newAccessToken = tokenData['access_token'] as String;
    final expiresIn = tokenData['expires_in'] as int? ?? 3600;
    // Note: Google doesn't always return a new refresh token on refresh
    final newRefreshToken = tokenData['refresh_token'] as String?;

    _accessToken = newAccessToken;
    _tokenExpiry = DateTime.now().add(Duration(seconds: expiresIn));

    await _storage.write(key: 'google.desktop.accessToken', value: newAccessToken);
    await _storage.write(key: 'google.desktop.tokenExpiry', value: _tokenExpiry!.toIso8601String());
    if (newRefreshToken != null) {
      await _storage.write(key: 'google.desktop.refreshToken', value: newRefreshToken);
    }

    return newAccessToken;
  }

  Future<void> _launchBrowser(String url) async {
    if (Platform.isLinux) {
      await Process.run('xdg-open', [url]);
    } else if (Platform.isMacOS) {
      await Process.run('open', [url]);
    } else if (Platform.isWindows) {
      await Process.run('cmd', ['/c', 'start', '', url]);
    } else {
      throw const GoogleAuthException('Unsupported platform for desktop authentication.');
    }
  }

  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError('DesktopGoogleAuthRepository must be initialized first.');
    }
  }

  void dispose() {
    _accountController.close();
  }
}
