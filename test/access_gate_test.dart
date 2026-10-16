import 'package:dazzlingwins/core/access_gate.dart';
import 'package:dazzlingwins/core/api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('access rules (VPN block, KYC for a second account on the same IP)', () {
    test('the website answers are recognised', () {
      final vpn = ApiException(kVpnBlockedMessage, status: 403, data: {'vpnBlocked': true});
      expect(vpn.vpnBlocked, isTrue);
      expect(vpn.signupKycRequired, isFalse);
      final kyc = ApiException(kSignupKycMessage, status: 403, data: {'signupKycRequired': true});
      expect(kyc.signupKycRequired, isTrue);
      expect(kyc.vpnBlocked, isFalse);
      expect(ApiException('x', status: 403).vpnBlocked, isFalse);
    });

    test('a refused action opens the KYC screen, signing out closes it', () {
      final access = AppAccess.instance;
      access.reset();
      expect(access.signupKycRequired, isFalse);
      var notified = 0;
      void listener() => notified++;
      access.addListener(listener);
      access.markSignupKyc(kSignupKycMessage);
      expect(access.signupKycRequired, isTrue);
      expect(access.message, kSignupKycMessage);
      access.markSignupKyc(kSignupKycMessage); // same state: no extra rebuild
      expect(notified, 1);
      access.reset();
      expect(access.signupKycRequired, isFalse);
      access.removeListener(listener);
    });

    test('wording matches the website', () {
      expect(kVpnBlockedMessage, contains('Your IP is not supported'));
      expect(kVpnBlockedMessage, contains('You are blocked'));
      expect(kSignupKycMessage, contains('Submit your KYC to complete your sign up'));
    });
  });
}
