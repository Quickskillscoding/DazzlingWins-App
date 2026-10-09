import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Login tokens, kept ONLY in the Android Keystore-backed secure storage (never plain prefs,
/// never logged). The access token lasts ~1 h; ApiClient refreshes it with the refresh token.
class Session extends ChangeNotifier {
  Session._();
  static final Session instance = Session._();

  static const _key = 'dw_session_v1';
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true, resetOnError: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );

  String? _accessToken;
  String? _refreshToken;
  int _expiresAt = 0; // unix seconds
  String? _userId;
  String? _email;

  String? get accessToken => _accessToken;
  String? get refreshToken => _refreshToken;
  String? get userId => _userId;
  String? get email => _email;
  bool get isSignedIn => _accessToken != null && _refreshToken != null;

  /// Refresh a minute early so a request never goes out with a token about to expire.
  bool get needsRefresh => _expiresAt > 0 && DateTime.now().millisecondsSinceEpoch ~/ 1000 >= _expiresAt - 60;

  Future<void> load() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null) return;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      _accessToken = data['accessToken'] as String?;
      _refreshToken = data['refreshToken'] as String?;
      _expiresAt = (data['expiresAt'] as num?)?.toInt() ?? 0;
      _userId = data['userId'] as String?;
      _email = data['email'] as String?;
    } catch (_) {
      await clear(notify: false);
    }
  }

  /// Accepts both the website login shape (snake_case Supabase session) and /api/auth/token/refresh.
  Future<void> saveFromJson(Map<String, dynamic> session, {Map<String, dynamic>? user}) async {
    final access = (session['access_token'] ?? session['accessToken']) as String?;
    final refresh = (session['refresh_token'] ?? session['refreshToken']) as String?;
    if (access == null || refresh == null) throw StateError('No session in the response.');
    _accessToken = access;
    _refreshToken = refresh;
    _expiresAt = ((session['expires_at'] ?? session['expiresAt']) as num?)?.toInt() ?? 0;
    final u = user ?? (session['user'] as Map<String, dynamic>?);
    if (u != null) {
      _userId = u['id'] as String? ?? _userId;
      _email = u['email'] as String? ?? _email;
    }
    await _storage.write(
      key: _key,
      value: jsonEncode({
        'accessToken': _accessToken,
        'refreshToken': _refreshToken,
        'expiresAt': _expiresAt,
        'userId': _userId,
        'email': _email,
      }),
    );
    notifyListeners();
  }

  Future<void> clear({bool notify = true}) async {
    _accessToken = null;
    _refreshToken = null;
    _expiresAt = 0;
    _userId = null;
    _email = null;
    try {
      await _storage.delete(key: _key);
    } catch (_) {}
    if (notify) notifyListeners();
  }
}
