import 'package:dazzlingwins/core/notification_inbox.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _n(String id, String at) => {'id': id, 'title': 'Offer $id', 'body': 'Tap to see your new offer.', 'at': at};

void main() {
  final inbox = NotificationInbox.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    inbox.reset();
    await inbox.loadMarks();
    inbox.setFetched([
      _n('a', '2026-10-01T10:00:00.000Z'),
      _n('c', '2026-10-03T10:00:00.000Z'),
      _n('b', '2026-10-02T10:00:00.000Z'),
    ]);
  });

  group('notification inbox', () {
    test('lists newest first and everything starts unread', () {
      expect(inbox.items.map((n) => n.id), ['c', 'b', 'a']);
      expect(inbox.unreadCount, 3);
    });

    test('read one, then read all', () async {
      await inbox.markRead(inbox.items.first);
      expect(inbox.unreadCount, 2);
      await inbox.markAllRead();
      expect(inbox.unreadCount, 0);
      expect(inbox.items.length, 3);
    });

    test('delete removes one notification and it stays deleted after a refresh', () async {
      final target = inbox.items.firstWhere((n) => n.id == 'b');
      await inbox.delete(target);
      expect(inbox.items.map((n) => n.id), ['c', 'a']);
      expect(inbox.unreadCount, 2);

      inbox.setFetched([_n('a', '2026-10-01T10:00:00.000Z'), _n('b', '2026-10-02T10:00:00.000Z'), _n('c', '2026-10-03T10:00:00.000Z')]);
      expect(inbox.items.map((n) => n.id), ['c', 'a']);
    });

    test('clear all empties the inbox but a new campaign still arrives', () async {
      await inbox.clearAll();
      expect(inbox.items, isEmpty);
      expect(inbox.unreadCount, 0);

      inbox.setFetched([_n('c', '2026-10-03T10:00:00.000Z'), _n('d', '2026-10-04T10:00:00.000Z')]);
      expect(inbox.items.map((n) => n.id), ['d']);
      expect(inbox.unreadCount, 1);
    });

    test('read and deleted marks survive an app restart', () async {
      await inbox.markRead(inbox.items.firstWhere((n) => n.id == 'c'));
      await inbox.delete(inbox.items.firstWhere((n) => n.id == 'a'));

      inbox.reset();
      await inbox.loadMarks();
      inbox.setFetched([_n('a', '2026-10-01T10:00:00.000Z'), _n('b', '2026-10-02T10:00:00.000Z'), _n('c', '2026-10-03T10:00:00.000Z')]);
      expect(inbox.items.map((n) => n.id), ['c', 'b']);
      expect(inbox.unreadCount, 1);
    });

    test('ignores duplicates and rows without an id', () {
      inbox.setFetched([_n('a', '2026-10-01T10:00:00.000Z'), _n('a', '2026-10-01T10:00:00.000Z'), _n('', '2026-10-02T10:00:00.000Z')]);
      expect(inbox.items.length, 1);
    });
  });
}
