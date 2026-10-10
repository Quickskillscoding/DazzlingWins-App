import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';
import 'game_sheet.dart';
import 'games_repo.dart';
import 'my_games_screen.dart';

class GamesScreen extends StatefulWidget {
  const GamesScreen({super.key});
  @override
  State<GamesScreen> createState() => _GamesScreenState();
}

class _GamesScreenState extends State<GamesScreen> with AutomaticKeepAliveClientMixin {
  List<Map<String, dynamic>> _games = [];
  Set<String> _mine = {};
  bool _loading = true;
  String? _error;
  String _query = '';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool force = false}) async {
    setState(() {
      _error = null;
      if (_games.isEmpty) _loading = true;
    });
    try {
      final results = await Future.wait([
        GamesRepo.instance.load(force: force),
        ApiClient.instance.get('/api/game-accounts').catchError((_) => <String, dynamic>{}),
      ]);
      final games = results[0] as List<Map<String, dynamic>>;
      final accounts = listOf((results[1] as Map<String, dynamic>)['accounts']);
      if (!mounted) return;
      setState(() {
        _games = games;
        _mine = accounts.map((a) => strOf(a['game_slug'])).toSet();
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final q = _query.trim().toLowerCase();
    final shown = q.isEmpty ? _games : _games.where((g) => strOf(g['title']).toLowerCase().contains(q)).toList();
    final mine = shown.where((g) => _mine.contains(g['slug'])).toList();
    final others = shown.where((g) => !_mine.contains(g['slug'])).toList();

    return AppBackground(
      child: RefreshIndicator(
        color: AppColors.gold,
        onRefresh: () => _load(force: true),
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          slivers: [
            SliverSafeArea(
              bottom: false,
              sliver: SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
                sliver: SliverList.list(children: [
                  Row(children: [
                    Expanded(child: Text('Games', style: AppTheme.display(28))),
                    _MyGamesButton(
                      count: _mine.length,
                      onTap: () async {
                        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MyGamesScreen()));
                        if (mounted) _load();
                      },
                    ),
                  ]),
                  const SizedBox(height: 4),
                  Text('Create an account, add score and redeem — all from here.', style: AppTheme.body(13, color: AppColors.muted)),
                  const SizedBox(height: 16),
                  TextField(
                    onChanged: (v) => setState(() => _query = v),
                    decoration: const InputDecoration(hintText: 'Search games', prefixIcon: Icon(Icons.search_rounded)),
                  ),
                  const SizedBox(height: 8),
                ]),
              ),
            ),
            if (_loading)
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                sliver: SliverGrid.count(
                  crossAxisCount: 2,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                  childAspectRatio: 0.78,
                  children: List.generate(6, (_) => const Skeleton(height: 200, radius: 22)),
                ),
              )
            else if (_error != null)
              SliverToBoxAdapter(child: ErrorRetry(message: _error!, onRetry: () => _load(force: true)))
            else ...[
              if (mine.isNotEmpty) ...[
                const SliverPadding(padding: EdgeInsets.fromLTRB(18, 8, 18, 0), sliver: SliverToBoxAdapter(child: SectionTitle('My games'))),
                _grid(mine, owned: true),
              ],
              if (others.isNotEmpty) ...[
                const SliverPadding(padding: EdgeInsets.fromLTRB(18, 8, 18, 0), sliver: SliverToBoxAdapter(child: SectionTitle('All games'))),
                _grid(others, owned: false),
              ],
              if (shown.isEmpty) const SliverToBoxAdapter(child: EmptyState(icon: Icons.search_off_rounded, title: 'No games match your search')),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 120)),
          ],
        ),
      ),
    );
  }

  Widget _grid(List<Map<String, dynamic>> games, {required bool owned}) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      sliver: SliverGrid.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 14,
          crossAxisSpacing: 14,
          childAspectRatio: 0.78,
        ),
        itemCount: games.length,
        itemBuilder: (_, i) => _GameCard(
          game: games[i],
          owned: owned,
          onTap: () async {
            await showGameSheet(context, games[i]);
            _load();
          },
        ),
      ),
    );
  }
}

/// "My Games" pill next to the page title: the player's game logins.
class _MyGamesButton extends StatelessWidget {
  const _MyGamesButton({required this.count, required this.onTap});
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface2,
      shape: StadiumBorder(side: BorderSide(color: AppColors.gold.withValues(alpha: 0.45))),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.vpn_key_rounded, size: 16, color: AppColors.gold),
            const SizedBox(width: 6),
            Text(count > 0 ? 'My Games ($count)' : 'My Games', style: AppTheme.body(13, weight: FontWeight.w800, color: AppColors.gold)),
          ]),
        ),
      ),
    );
  }
}

class _GameCard extends StatelessWidget {
  const _GameCard({required this.game, required this.owned, required this.onTap});
  final Map<String, dynamic> game;
  final bool owned;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: owned ? AppColors.gold.withValues(alpha: 0.5) : AppColors.stroke),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: NetImage(strOf(game['thumbnail']), cacheWidth: 360)),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Row(children: [
              Expanded(child: Text(strOf(game['title']), style: AppTheme.body(14, weight: FontWeight.w800), maxLines: 1, overflow: TextOverflow.ellipsis)),
              if (owned) const Icon(Icons.verified_rounded, size: 18, color: AppColors.gold),
            ]),
          ),
        ]),
      ),
    );
  }
}
