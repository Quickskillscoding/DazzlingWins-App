import 'package:dazzlingwins/features/spin/spin_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 10, 10, 12);
  int ms(Duration ago) => now.subtract(ago).millisecondsSinceEpoch;

  final history = <String, dynamic>{
    'bets': [
      {'id': 'bet-buy-1', 'game': 'Juwa', 'label': 'Add score', 'at': ms(const Duration(hours: 1)), 'amount': -10, 'status': 'Other'},
      {'id': 'bet-spin-a', 'game': 'Spin Wheel', 'label': 'Spin reward', 'at': ms(const Duration(hours: 2)), 'amount': 4, 'status': 'Won'},
      {'id': 'bet-spin-buy-b', 'game': 'Spin Wheel', 'label': 'Extra spin purchase', 'at': ms(const Duration(days: 3)), 'amount': -1, 'status': 'Other'},
      {'id': 'bet-spin-c', 'game': 'Spin Wheel', 'label': 'No win', 'at': ms(const Duration(days: 20)), 'amount': 0, 'status': 'Push'},
      {'id': 'bet-spin-d', 'game': 'Spin Wheel', 'label': 'Spin reward', 'at': ms(const Duration(days: 200)), 'amount': 2, 'status': 'Won'},
    ],
  };

  group('spin history', () {
    test('keeps only Spin Wheel rows, newest first', () {
      final all = spinHistoryFrom(history);
      expect(all.map((e) => e.id), ['bet-spin-a', 'bet-spin-buy-b', 'bet-spin-c', 'bet-spin-d']);
      expect(all[0].purchase, isFalse);
      expect(all[0].amount, 4);
      expect(all[1].purchase, isTrue);
    });

    test('look-back tabs match the website', () {
      final all = spinHistoryFrom(history);
      expect(kSpinHistoryWindows.map((w) => w.label), ['24 hours', '7 days', '30 days', '12 months']);
      final counts = [for (final w in kSpinHistoryWindows) filterSpinHistory(all, w.window, now: now).length];
      expect(counts, [1, 2, 3, 4]);
    });

    test('an empty or broken answer gives an empty list', () {
      expect(spinHistoryFrom(const {}), isEmpty);
      expect(spinHistoryFrom(const {'bets': 'x'}), isEmpty);
    });
  });

  test('spin rules use the website numbers', () {
    expect(kFreeSpinCycleDays, 5);
    expect(kFreeSpinUnlockDeposit, 5);
    expect(kPaidExtraSpinPrice, 1);
    expect(kSpinBonusTtlHours, 72);
    final text = kSpinRules.map((r) => r.text).join(' ');
    expect(text, contains('One free spin every 24 hours for 5 days.'));
    expect(text, contains('within 72 hours'));
    expect(text, contains('KYC'));
  });
}
