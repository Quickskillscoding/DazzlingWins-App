import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'session.dart';

/// One promo notification in the player's inbox.
class InboxItem {
  const InboxItem({required this.id, required this.title, required this.body, required this.at});

  factory InboxItem.fromJson(Map<String, dynamic> json) => InboxItem(
        id: strOf(json['id']),
        title: strOf(json['title'], 'New offer for you'),
        body: strOf(json['body']),
        at: strOf(json['at']),
      );

  final String id;
  final String title;
  final String body;

  /// ISO time the campaign was delivered to this player.
  final String at;

  /// Stable identity of this delivery (a campaign can be delivered more than once).
  String get key => '$id|$at';
}

/// The bell's notification inbox: the player's recent promo campaigns, plus which of them were
/// read or deleted on this device. Read / deleted marks are kept per player in local storage,
/// so they survive restarts and never leak between accounts on the same phone.
class NotificationInbox extends ChangeNotifier {
  NotificationInbox._();
  static final NotificationInbox instance = NotificationInbox._();

  /// How far back the inbox looks.
  static const window = Duration(days: 30);

  /// Most marks remembered per player (oldest are forgotten first).
  static const _maxMarks = 300;

  List<InboxItem> _all = const [];
  final Set<String> _read = <String>{};
  final Set<String> _dismissed = <String>{};
  String? _owner;

  bool _loading = false;
  bool _fetched = false;
  String? _error;

  /// Notifications still in the inbox, newest first.
  List<InboxItem> get items => _all.where((n) => !_dismissed.contains(n.key)).toList(growable: false);
  int get unreadCount => _all.where((n) => !_dismissed.contains(n.key) && !_read.contains(n.key)).length;
  bool isRead(InboxItem item) => _read.contains(item.key);

  bool get loading => _loading;

  /// True once the server answered at least once for the current player.
  bool get fetched => _fetched;
  String? get error => _error;

  String get _ownerId => Session.instance.userId ?? 'guest';
  String _readKey(String owner) => 'dw_inbox_read_$owner';
  String _dismissedKey(String owner) => 'dw_inbox_dismissed_$owner';

  /// Load the read / deleted marks of the signed-in player (again after an account switch).
  Future<void> _ensureMarks() async {
    final owner = _ownerId;
    if (_owner == owner) return;
    final prefs = await SharedPreferences.getInstance();
    _read
      ..clear()
      ..addAll(prefs.getStringList(_readKey(owner)) ?? const <String>[]);
    _dismissed
      ..clear()
      ..addAll(prefs.getStringList(_dismissedKey(owner)) ?? const <String>[]);
    if (_owner != null) {
      _all = const [];
      _fetched = false;
    }
    _owner = owner;
  }

  Future<void> _persist() async {
    final owner = _owner;
    if (owner == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_readKey(owner), _newest(_read));
      await prefs.setStringList(_dismissedKey(owner), _newest(_dismissed));
    } catch (_) {
      // Storage full / unavailable: the marks still hold for this run.
    }
  }

  List<String> _newest(Set<String> marks) {
    final list = marks.toList(growable: false);
    return list.length <= _maxMarks ? list : list.sublist(list.length - _maxMarks);
  }

  /// Fetch the latest notifications. Never throws: a failure is exposed through [error].
  Future<void> refresh() async {
    if (_loading) return;
    if (!Session.instance.isSignedIn) return;
    _loading = true;
    _error = null;
    notifyListeners();
    final owner = _ownerId;
    try {
      await _ensureMarks();
      final since = DateTime.now().toUtc().subtract(window).toIso8601String();
      final data = await ApiClient.instance.get('/api/app/notifications', query: {'since': since, 'recent': '1'});
      // Signed out or switched account while the request was in flight: drop the answer.
      if (owner == _ownerId && Session.instance.isSignedIn) {
        setFetched(listOf(data['notifications']));
      }
    } on ApiException catch (e) {
      _error = e.message;
    } catch (_) {
      _error = 'Could not load notifications. Check your connection.';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Replace the inbox content with what the server returned (any order), newest first.
  void setFetched(List<Map<String, dynamic>> raw) {
    final seen = <String>{};
    final list = <InboxItem>[];
    for (final json in raw) {
      final item = InboxItem.fromJson(json);
      if (item.id.isEmpty || !seen.add(item.key)) continue;
      list.add(item);
    }
    list.sort((a, b) => b.at.compareTo(a.at));
    _all = list;
    _fetched = true;
    notifyListeners();
  }

  /// Load the stored marks without a network call (used by tests and before the first fetch).
  Future<void> loadMarks() => _ensureMarks();

  Future<void> markRead(InboxItem item) async {
    await _ensureMarks();
    if (!_read.add(item.key)) return;
    notifyListeners();
    await _persist();
  }

  Future<void> markAllRead() async {
    await _ensureMarks();
    var changed = false;
    for (final n in _all) {
      if (!_dismissed.contains(n.key) && _read.add(n.key)) changed = true;
    }
    if (!changed) return;
    notifyListeners();
    await _persist();
  }

  /// Delete one notification from the inbox.
  Future<void> delete(InboxItem item) async {
    // Removed from the list in the same frame (a swiped-away row must disappear immediately).
    final added = _dismissed.add(item.key);
    _read.add(item.key);
    if (added) notifyListeners();
    await _ensureMarks();
    _dismissed.add(item.key);
    _read.add(item.key);
    await _persist();
  }

  /// Delete every notification currently in the inbox.
  Future<void> clearAll() async {
    await _ensureMarks();
    if (_all.every((n) => _dismissed.contains(n.key))) return;
    for (final n in _all) {
      _dismissed.add(n.key);
      _read.add(n.key);
    }
    notifyListeners();
    await _persist();
  }

  /// Forget the in-memory inbox on sign-out. The stored marks stay, keyed by player.
  void reset() {
    _all = const [];
    _read.clear();
    _dismissed.clear();
    _owner = null;
    _fetched = false;
    _loading = false;
    _error = null;
    notifyListeners();
  }
}
