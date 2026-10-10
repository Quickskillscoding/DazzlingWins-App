import 'package:dazzlingwins/features/games/game_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('manual game account login', () {
    test('username: 3 to 24 letters, numbers, dots, - or _', () {
      for (final ok in ['abc', 'your.name-123', 'A_b.c-9', 'x' * 24]) {
        expect(isValidGameUsername(ok), isTrue, reason: ok);
      }
      for (final bad in ['', 'ab', 'x' * 25, 'has space', 'émile', 'name@site', 'a/b']) {
        expect(isValidGameUsername(bad), isFalse, reason: bad);
      }
    });

    test('password: anything non-empty up to 64 characters', () {
      expect(isValidGamePassword('a'), isTrue);
      expect(isValidGamePassword('p@ss word!'), isTrue);
      expect(isValidGamePassword('x' * 64), isTrue);
      expect(isValidGamePassword(''), isFalse);
      expect(isValidGamePassword('   '), isFalse);
      expect(isValidGamePassword('x' * 65), isFalse);
    });
  });

  group('wallet choice', () {
    test('each wallet has its own note, worded like the website', () {
      expect(walletNote('current').title, 'Current Wallet score:');
      expect(walletNote('current').text, contains('according to your XP level'));
      expect(walletNote('bonus').title, 'Bonus Wallet score:');
      expect(walletNote('bonus').text, contains('10% of your winnings'));
      expect(walletName('bonus'), 'Bonus Wallet');
      expect(walletName('current'), 'Current Wallet');
      expect(walletName(''), 'Current Wallet');
    });

    test('score cannot be bought with more than the wallet holds', () {
      expect(balanceProblem(wallet: 'current', amount: 10, currentWallet: 10, bonusWallet: 0), isNull);
      expect(balanceProblem(wallet: 'current', amount: 10.01, currentWallet: 10, bonusWallet: 50), contains('Deposit first'));
      expect(balanceProblem(wallet: 'bonus', amount: 3, currentWallet: 0, bonusWallet: 3), isNull);
      expect(balanceProblem(wallet: 'bonus', amount: 4, currentWallet: 100, bonusWallet: 3), contains('Bonus Wallet'));
    });
  });

  group('redeem and transfer wording', () {
    test('starter levels: 80% up to the level cap', () {
      expect(
        redeemHint({'starter': true}, 100),
        'No redeem limit. At your level you receive 80% of a redeem up to 100, or 100 for anything above that. The rest goes to your XP.',
      );
      expect(redeemHint({'starter': true}, 150), contains('up to 150, or 150 for anything above'));
    });

    test('higher levels: daily cap and what is left today', () {
      expect(
        redeemHint({'starter': false, 'dailyCap': 300, 'dailyRemaining': 120.4}, 100),
        'Level cap 300 / day · 120 left today. Max 100 per request. Extra score converts to XP.',
      );
      expect(transferHint({'dailyCap': 300, 'dailyRemaining': 300}), 'Level cap 300 / day · 300 left today. Max 100 per request. Extra score converts to XP.');
      expect(transferHint(const {}), contains('Level cap 0 / day'));
    });
  });

  test('request outcomes', () {
    expect(requestOutcome('pending'), 'pending');
    expect(requestOutcome('ready'), 'done');
    expect(requestOutcome('approved'), 'done');
    expect(requestOutcome('rejected'), 'rejected');
    expect(requestOutcome(null), 'pending');
  });

  test('wait screens have their lines', () {
    expect(kCreateLines, contains('Locking in username & password…'));
    for (final lines in [kCreateLines, kBuyLines, kRedeemLines, kTransferLines]) {
      expect(lines, isNotEmpty);
    }
  });
}
