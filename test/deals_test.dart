import 'package:dazzlingwins/features/deals/deals_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('dazzling deals', () {
    test('defaults match the website', () {
      const d = DealsSettings.defaults;
      expect(d.weeklyDepositTarget, 1000);
      expect(d.weeklyCashback, 100);
      expect(d.loyaltyBase, 50);
      expect(d.loyaltyStep, 25);
      expect(d.weeklyTitle, 'Exclusive Weekly Reward');
      expect(d.loyaltyTitle, 'Loyalty Bonus');
    });

    test('settings come from the server, bad or missing values fall back', () {
      final s = DealsSettings.fromJson({
        'weeklyEnabled': false,
        'weeklyDepositTarget': 500,
        'weeklyCashback': 40,
        'weeklyTitle': '  Big Week  ',
        'weeklyCta': '',
        'loyaltyBase': 10,
        'loyaltyStep': 5,
        'loyaltyTitle': 7,
      });
      expect(s.weeklyEnabled, isFalse);
      expect(s.weeklyDepositTarget, 500);
      expect(s.weeklyCashback, 40);
      expect(s.weeklyTitle, 'Big Week');
      expect(s.weeklyCta, 'Deposit Now');
      expect(s.loyaltyEnabled, isTrue);
      expect(s.loyaltyReward(1), 10);
      expect(s.loyaltyReward(4), 25);
      expect(s.loyaltyReward(0), 0);
      expect(DealsSettings.fromJson(const {}).signature, DealsSettings.defaults.signature);
      expect(s.signature, isNot(DealsSettings.defaults.signature));
    });

    test('loyalty reward: base at Level 1, then one step per level', () {
      const d = DealsSettings.defaults;
      expect([for (var l = 1; l <= 4; l++) d.loyaltyReward(l)], [50, 75, 100, 125]);
    });

    test('player status', () {
      final st = DealsStatus.fromJson({
        'weekStart': '2026-10-05T00:00:00.000Z',
        'weekEnd': '2026-10-12T00:00:00.000Z',
        'weekDeposits': 250.5,
        'weeklyClaimed': false,
        'xp': 1200,
        'level': 1,
        'loyaltyClaimableLevel': 1,
        'loyaltyClaimedToday': false,
        'lock': null,
      })!;
      expect(st.weekDeposits, 250.5);
      expect(st.level, 1);
      expect(st.loyaltyClaimableLevel, 1);
      expect(st.lock, isNull);
      expect(st.weekEnd, isNotNull);
      expect(DealsStatus.fromJson(null), isNull);
      expect(DealsStatus.fromJson({'loyaltyClaimableLevel': null, 'lock': 'weekly'})!.loyaltyClaimableLevel, isNull);
      expect(DealsStatus.fromJson({'lock': 'weekly'})!.lock, 'weekly');
      expect(DealsStatus.fromJson({'lock': 'other'})!.lock, isNull);
    });

    test('weekly progress', () {
      expect(weeklyRemaining(250.5, 1000), 749.5);
      expect(weeklyRemaining(1200, 1000), 0);
      expect(weeklyProgress(250, 1000), 0.25);
      expect(weeklyProgress(5000, 1000), 1);
      expect(weeklyProgress(10, 0), 1);
    });

    test('money, time left and lock messages', () {
      expect(dealMoney(1000), r'$1,000');
      expect(dealMoney(100), r'$100');
      expect(dealMoney(749.5), r'$749.50');
      expect(dealMoney(0), r'$0');
      final now = DateTime.utc(2026, 10, 10, 12);
      expect(weekTimeLeft(DateTime.utc(2026, 10, 12), now: now), '1d 12h left this week');
      expect(weekTimeLeft(DateTime.utc(2026, 10, 10, 17), now: now), '5h left this week');
      expect(weekTimeLeft(null), '');
      expect(dealLockMessage('weekly'), contains('next Monday'));
      expect(dealLockMessage('loyalty'), contains('tomorrow'));
      expect(dealLockMessage(null), isNull);
    });

    test('an admin change or new progress changes the signature (so the screen updates)', () {
      final a = DealsData.fromJson({'ready': true, 'settings': <String, dynamic>{}, 'status': {'weekDeposits': 10}});
      final b = DealsData.fromJson({'ready': true, 'settings': {'weeklyCashback': 150}, 'status': {'weekDeposits': 10}});
      final c = DealsData.fromJson({'ready': true, 'settings': <String, dynamic>{}, 'status': {'weekDeposits': 20}});
      expect(a.signature, isNot(b.signature));
      expect(a.signature, isNot(c.signature));
      expect(a.signature, DealsData.fromJson({'ready': true, 'settings': <String, dynamic>{}, 'status': {'weekDeposits': 10}}).signature);
    });
  });
}
