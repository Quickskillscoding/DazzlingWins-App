import 'package:dazzlingwins/features/wallet/deposit_limits.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('deposit limits (set by admins on the website)', () {
    test('read from the payment method; empty or bad = no limit', () {
      final l = DepositLimits.of({'min_deposit': '10.00', 'max_deposit': 500});
      expect(l.min, 10);
      expect(l.max, 500);
      expect(l.any, isTrue);
      expect(DepositLimits.of({}).any, isFalse);
      expect(DepositLimits.of({'min_deposit': 0, 'max_deposit': 'x'}).any, isFalse);
      expect(DepositLimits.of({'min_deposit': null, 'max_deposit': 250}).text, 'Max \$250');
    });

    test('wording matches the website', () {
      expect(const DepositLimits(min: 10, max: 500).text, 'Min \$10 · Max \$500');
      expect(const DepositLimits(min: 7.5).text, 'Min \$7.50');
      expect(const DepositLimits().text, '');
    });

    test('amounts outside the limits are refused before anything is sent', () {
      const l = DepositLimits(min: 10, max: 500);
      expect(l.errorFor(10, 'CashApp'), isNull);
      expect(l.errorFor(500, 'CashApp'), isNull);
      expect(l.errorFor(9.99, 'CashApp'), 'The minimum deposit with CashApp is \$10.');
      expect(l.errorFor(500.5, 'CashApp'), 'The maximum deposit with CashApp is \$500.');
      expect(const DepositLimits().errorFor(1, 'Chime'), isNull);
    });
  });
}
