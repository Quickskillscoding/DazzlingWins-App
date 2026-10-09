import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

import '../../core/api.dart';
import '../../core/config.dart';
import '../../core/session.dart';

/// "Continue with Google" — runs the WEBSITE's own Google sign-in in a secure in-app browser tab,
/// so bans, the admin block, login tracking and new-player emails apply exactly as on the site.
///
/// Security (PKCE-style): a random [verifier] never leaves the app; only its SHA-256 `challenge`
/// is sent. The website hands back a short-lived encrypted code through an Android intent
/// addressed to this app's package; the code is worthless without the verifier.
class GoogleAuth {
  GoogleAuth._();

  static const callbackScheme = 'dazzlingwins';

  static String _randomVerifier() {
    final r = Random.secure();
    final bytes = List<int>.generate(48, (_) => r.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  static String _challenge(String verifier) =>
      base64Url.encode(sha256.convert(utf8.encode(verifier)).bytes).replaceAll('=', '');

  /// Returns true when signed in, false when the player closed the browser tab.
  static Future<bool> signIn() async {
    final verifier = _randomVerifier();
    final url = AppConfig.uri('/app-auth/google', {'challenge': _challenge(verifier)}).toString();

    final String result;
    try {
      result = await FlutterWebAuth2.authenticate(url: url, callbackUrlScheme: callbackScheme);
    } on PlatformException catch (e) {
      if (e.code == 'CANCELED') return false;
      throw ApiException('Could not open Google sign-in. Please try again.');
    }

    final code = Uri.tryParse(result)?.queryParameters['code'];
    if (code == null || code.isEmpty) {
      throw ApiException('Google sign-in did not finish. Please try again.');
    }
    final data = await ApiClient.instance.post('/api/auth/app-exchange', {'code': code, 'verifier': verifier}, auth: false);
    final session = data['session'];
    if (session is! Map<String, dynamic>) {
      throw ApiException('Google sign-in did not finish. Please try again.');
    }
    await Session.instance.saveFromJson(session);
    return true;
  }
}
