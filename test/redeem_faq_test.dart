import 'package:dazzlingwins/core/app_state.dart';
import 'package:dazzlingwins/features/help/faq_data.dart';
import 'package:dazzlingwins/features/help/faq_screen.dart';
import 'package:dazzlingwins/features/wallet/redeem_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('redeem', () {
    test('lists only approved game accounts, by title, with the score on file', () {
      final games = redeemGamesFrom({
        'accounts': [
          {'game_slug': 'juwa', 'game_title': 'Juwa', 'status': 'ready', 'current_score': 40, 'bonus_score': 2.5},
          {'game_slug': 'orion-star', 'game_title': 'Orion Star', 'status': 'pending', 'current_score': 9},
          {'game_slug': 'fire-kirin', 'game_title': 'Fire Kirin', 'status': 'ready'},
          {'game_slug': '', 'game_title': 'Broken', 'status': 'ready'},
        ],
      });
      expect(games.map((g) => g.title), ['Fire Kirin', 'Juwa']);
      expect(games.last.score, 42.5);
      expect(games.first.score, 0);
      expect(redeemGamesFrom(const {}), isEmpty);
    });

    test('rules name the starter levels and their cash caps from the level table', () {
      final rules = redeemRules(XpLevel.defaults).join(' ');
      expect(rules, contains('Bronze and Silver'));
      expect(rules, contains(r'$100 at Bronze'));
      expect(rules, contains(r'$150 at Silver'));
      expect(rules, contains('80%'));
      expect(rules, contains('10%'));
    });
  });

  group('faq', () {
    test('has every category and question of the website FAQ', () {
      expect(kFaq.map((c) => c.id), ['general', 'deposits', 'withdrawals', 'bonuses', 'account', 'trust', 'support']);
      expect(kFaq.fold<int>(0, (n, c) => n + c.items.length), 31);
      final ids = [for (final c in kFaq) ...c.items.map((i) => i.id)];
      expect(ids.toSet().length, ids.length);
      for (final c in kFaq) {
        for (final i in c.items) {
          expect(i.question.trim(), isNotEmpty);
          expect(i.answer.trim(), isNotEmpty);
        }
      }
    });

    test('search looks in questions and answers', () {
      expect(searchFaq(''), same(kFaq));
      final hits = searchFaq('minimum');
      expect(hits, isNotEmpty);
      expect(hits.expand((c) => c.items).map((i) => i.id), containsAll(['dep-1', 'wd-2']));
      expect(searchFaq('zzzz-not-there'), isEmpty);
    });
  });
}
