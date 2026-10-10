import 'package:dazzlingwins/features/games/my_games_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('my games', () {
    final answer = <String, dynamic>{
      'accounts': [
        {'id': '1', 'game_slug': 'juwa', 'game_title': 'Juwa', 'username': 'dwju_ali', 'password': 'Ju#4821', 'status': 'pending'},
        {'id': '2', 'game_slug': 'orion-star', 'game_title': 'Orion Star', 'username': 'dwos_ali', 'password': 'Os#1177', 'status': 'ready'},
        {'id': '3', 'game_slug': 'fire-kirin', 'game_title': 'Fire Kirin', 'username': 'dwfk_ali', 'password': 'Fk#9090', 'status': 'ready'},
        {'id': '4', 'game_slug': '', 'game_title': 'Broken', 'status': 'ready'},
      ],
    };

    test('approved accounts first, then pending, by title; broken rows dropped', () {
      final list = myGameAccountsFrom(answer);
      expect(list.map((a) => a.title), ['Fire Kirin', 'Orion Star', 'Juwa']);
      expect(list.map((a) => a.approved), [true, true, false]);
    });

    test('login text is ready to paste', () {
      final orion = myGameAccountsFrom(answer).firstWhere((a) => a.slug == 'orion-star');
      expect(orion.username, 'dwos_ali');
      expect(orion.password, 'Os#1177');
      expect(orion.loginText, 'Username: dwos_ali\nPassword: Os#1177');
    });

    test('a new password changes the signature (so the screen updates)', () {
      final a = MyGameAccount.fromJson({'id': '2', 'game_slug': 'orion-star', 'game_title': 'Orion Star', 'username': 'u', 'password': 'p1', 'status': 'ready'});
      final b = MyGameAccount.fromJson({'id': '2', 'game_slug': 'orion-star', 'game_title': 'Orion Star', 'username': 'u', 'password': 'p2', 'status': 'ready'});
      expect(a.signature, isNot(b.signature));
    });

    test('an empty or broken answer gives an empty list', () {
      expect(myGameAccountsFrom(const {}), isEmpty);
      expect(myGameAccountsFrom(const {'accounts': 'x'}), isEmpty);
    });
  });
}
