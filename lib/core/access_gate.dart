import 'package:flutter/foundation.dart';

import 'api.dart';
import 'session.dart';

/// The two player access rules the website enforces (lib/access-gate-server.ts), as the app sees
/// them:
///
///  * VPN / proxy: the website answers 403 `vpnBlocked`. The app signs the player out and shows
///    "Your IP is not supported – You are blocked" (see ApiClient and main.dart).
///  * A second account on the same internet connection: 403 `signupKycRequired` until its KYC is
///    approved. The app shows the "Complete your sign up" screen that leads to KYC (HomeShell).
///
/// This class only remembers the second state and asks /api/auth/access for it. The server decides
/// everything; the app never unlocks anything on its own.
class AppAccess extends ChangeNotifier {
  AppAccess._();
  static final AppAccess instance = AppAccess._();

  bool _signupKycRequired = false;
  String _kycStatus = 'none';
  String _message = '';
  bool _checking = false;

  bool get signupKycRequired => _signupKycRequired;

  /// 'none' | 'pending' | 'approved' | 'rejected'
  String get kycStatus => _kycStatus;
  String get message => _message;

  /// A gated action was refused by the server: show the KYC screen straight away.
  void markSignupKyc(String message) {
    if (_signupKycRequired && _message == message) return;
    _signupKycRequired = true;
    if (message.isNotEmpty) _message = message;
    notifyListeners();
  }

  /// Asks the website for the current state. Never throws. A VPN answer (403 vpnBlocked) is
  /// handled by ApiClient, which signs the player out.
  Future<void> check() async {
    if (_checking || !Session.instance.isSignedIn) return;
    _checking = true;
    try {
      final d = await ApiClient.instance.get('/api/auth/access');
      final required = d['signupKycRequired'] == true;
      final status = strOf(d['kycStatus'], 'none');
      final message = strOf(d['message']);
      if (required != _signupKycRequired || status != _kycStatus || (required && message != _message)) {
        _signupKycRequired = required;
        _kycStatus = status;
        if (message.isNotEmpty) _message = message;
        notifyListeners();
      }
    } catch (_) {
      // Offline or signed out: keep the last known state; the server still enforces the rules.
    } finally {
      _checking = false;
    }
  }

  void reset() {
    _signupKycRequired = false;
    _kycStatus = 'none';
    _message = '';
    notifyListeners();
  }
}

/// Wording the website uses (kept here so the app reads the same when a message is missing).
const String kVpnBlockedMessage =
    'Your IP is not supported. You are blocked because a VPN or proxy is turned on. Turn off your VPN, then sign in again.';
const String kSignupKycMessage =
    'An account was already created on this internet connection. Submit your KYC to complete your sign up.';
