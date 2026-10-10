import 'package:dazzlingwins/core/format.dart';
import 'package:dazzlingwins/features/auth/auth_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('money formatting (same as the website)', () {
    test('two decimals with thousands separators', () {
      expect(money(0), r'$0.00');
      expect(money(1234.5), r'$1,234.50');
      expect(money(-10), r'-$10.00');
      expect(money(5, sign: true), r'+$5.00');
    });

    test('status labels', () {
      expect(statusLabel('approved'), 'Approved');
      expect(statusLabel('ready'), 'Approved');
      expect(statusLabel('rejected'), 'Rejected');
      expect(statusLabel('pending'), 'Pending');
    });

    test('compact integers', () {
      expect(compactInt(15000), '15,000');
      expect(compactInt(999), '999');
    });
  });

  group('sign-up password rules', () {
    test('needs 8+ chars with upper, lower, number and special', () {
      expect(PasswordStrength.of('').score, 0);
      expect(PasswordStrength.of('password').meetsRules, isFalse);
      expect(PasswordStrength.of('Password1').meetsRules, isFalse);
      expect(PasswordStrength.of('Pass1!').meetsRules, isFalse);
      expect(PasswordStrength.of('Password1!').meetsRules, isTrue);
    });

    test('labels weak to strong', () {
      expect(PasswordStrength.of('abc').label, 'Weak');
      expect(PasswordStrength.of('abcdefgh1').label, 'Fair');
      expect(PasswordStrength.of('Abcdefgh1').label, 'Good');
      expect(PasswordStrength.of('Abcdefgh1!').label, 'Strong');
    });
  });
}
