import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:app_links/app_links.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api.dart';
import '../../core/config.dart';
import '../../core/session.dart';

/// "Continue with Google" — runs the WEBSITE's own Google sign-in in a browser tab INSIDE the app
/// (an Android Custom Tab: Google refuses to sign in inside a plain embedded web view), so bans,
/// the admin block, login tracking and new-player emails apply exactly as on the site.
///
/// 1. A random verifier is created and kept in secure storage (it never leaves the phone); only its
///    SHA-256 `challenge` goes to /app-auth/google.
/// 2. After Google, the website redirects to `dazzlingwins://auth?code=…` through an Android intent
///    addressed to this app's package. The app receives it as a deep link — even if Android
///    restarted the app meanwhile, because the verifier is in secure storage.
/// 3. code + verifier are exchanged at /api/auth/app-exchange for the session.
class GoogleAuth {
  GoogleAuth._();

  static const _verifierKey = 'dw_google_verifier_v1';
  static const _maxAge = Duration(minutes: 10);
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true, resetOnError: true),
  );

  static final AppLinks _links = AppLinks();
  static StreamSubscription<Uri>? _sub;
  static final Set<String> _handled = {};

  /// Called with the outcome of a returning sign-in: null = signed in, otherwise an error message.
  static void Function(String? error)? onResult;

  static String _randomVerifier() {
    final r = Random.secure();
    return base64Url.encode(List<int>.generate(48, (_) => r.nextInt(256))).replaceAll('=', '');
  }

  static String _challenge(String verifier) =>
      base64Url.encode(sha256.convert(utf8.encode(verifier)).bytes).replaceAll('=', '');

  /// Start listening for the sign-in link (call once at startup, before runApp's first frame work).
  static void listen() {
    _sub ??= _links.uriLinkStream.listen(_handle, onError: (_) {});
  }

  /// Opens Google sign-in on top of the app. The result arrives later through [onResult].
  ///
  /// The tab belongs to this app's own window, not to the browser: when the website hands the
  /// one-time code back, Android returns to the app's main screen and closes the tab, so nothing
  /// is left open in the phone's browser. Only a phone without a Custom Tabs browser falls back
  /// to the normal browser.
  static Future<void> start() async {
    final verifier = _randomVerifier();
    await _storage.write(
      key: _verifierKey,
      value: jsonEncode({'v': verifier, 't': DateTime.now().millisecondsSinceEpoch}),
    );
    final url = AppConfig.uri('/app-auth/google', {'challenge': _challenge(verifier)});
    var ok = false;
    try {
      ok = await launchUrl(url, mode: LaunchMode.inAppBrowserView);
    } catch (_) {
      ok = false;
    }
    if (!ok) ok = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!ok) throw ApiException('Could not open Google sign-in.');
  }

  static Future<void> _handle(Uri uri) async {
    if (uri.scheme != 'dazzlingwins' || uri.host != 'auth') return;
    final code = uri.queryParameters['code'];
    if (code == null || code.isEmpty || !_handled.add(code)) return;
    try {
      await _exchange(code);
      onResult?.call(null);
    } on ApiException catch (e) {
      onResult?.call(e.message);
    } catch (_) {
      onResult?.call('Google sign-in failed. Please try again.');
    }
  }

  static Future<void> _exchange(String code) async {
    final raw = await _storage.read(key: _verifierKey);
    await _storage.delete(key: _verifierKey);
    if (raw == null) throw ApiException('This sign-in expired. Please tap Continue with Google again.');
    final saved = jsonDecode(raw) as Map<String, dynamic>;
    final age = DateTime.now().millisecondsSinceEpoch - ((saved['t'] as num?)?.toInt() ?? 0);
    if (age > _maxAge.inMilliseconds) throw ApiException('This sign-in expired. Please tap Continue with Google again.');

    final data = await ApiClient.instance.post(
      '/api/auth/app-exchange',
      {'code': code, 'verifier': saved['v']},
      auth: false,
    );
    final session = data['session'];
    if (session is! Map<String, dynamic>) throw ApiException('Google sign-in did not finish. Please try again.');
    await Session.instance.saveFromJson(session);
  }
}
