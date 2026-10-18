import 'package:dazzlingwins/features/games/game_rules.dart';
import 'package:dazzlingwins/features/levels/x_rule.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('X Rule levels and claims match the website', () {
    expect([0, 999, 1000, 2000, 3000, 4000, 5000, 9000].map((p) => xRuleLevel(p.toDouble())).toList(), [0, 0, 1, 2, 3, 4, 5, 5]);
    expect([0, 1, 2, 3, 4, 5].map(xRuleMaxMultiple).toList(), [5, 6, 7, 8, 9, 10]);
    final c = xRuleClaim(5, 0, 50);
    expect([c.min, c.max, c.cash, c.points], [15, 25, 25, 25]);
    expect(xRuleClaim(5, 5, 100).max, 50);
    expect(xRuleNextThreshold(5), isNull);
  });

  test('redeem hint uses X Rule when the player is on it', () {
    final hint = redeemHint({
      'xRule': {'rule': 'x', 'level': 1, 'progress': 1200, 'lastDeposit': 5, 'minClaim': 15, 'maxClaim': 30, 'maxMultiple': 6},
    }, 100);
    expect(hint, contains('X Rule Level 1'));
    expect(hint, contains('\$15.00'));
    expect(XRuleStatus.from({'rule': 'xp'}), isNull);
  });
}
