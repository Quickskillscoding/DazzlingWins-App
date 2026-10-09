import '../../core/api.dart';

/// The site's playable brand games (/api/app/games), cached for the session.
class GamesRepo {
  GamesRepo._();
  static final GamesRepo instance = GamesRepo._();

  List<Map<String, dynamic>>? _cache;
  Future<List<Map<String, dynamic>>>? _loading;

  Future<List<Map<String, dynamic>>> load({bool force = false}) {
    if (!force && _cache != null) return Future.value(_cache);
    return _loading ??= ApiClient.instance.get('/api/app/games', auth: false).then((d) {
      _cache = listOf(d['games']);
      return _cache!;
    }).whenComplete(() => _loading = null);
  }

  String titleFor(String slug) {
    final hit = _cache?.where((g) => g['slug'] == slug);
    return hit == null || hit.isEmpty ? slug : strOf(hit.first['title'], slug);
  }
}
