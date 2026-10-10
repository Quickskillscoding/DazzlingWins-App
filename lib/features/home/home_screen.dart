import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../widgets/app_header.dart';
import '../../widgets/ui.dart';
import '../games/game_sheet.dart';
import '../games/games_repo.dart';
import '../profile/rewards_panel.dart';
import '../shell/home_shell.dart';
import '../wallet/deposit_screen.dart';
import '../wallet/withdraw_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with AutomaticKeepAliveClientMixin {
  final _rewardsKey = GlobalKey<RewardsPanelState>();
  final _scroll = ScrollController();
  List<Map<String, dynamic>> _games = [];
  bool _gamesLoading = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadGames();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadGames() async {
    try {
      final games = await GamesRepo.instance.load();
      if (mounted) setState(() => _games = games);
    } catch (_) {
      // the Games tab shows the error; Home just hides the strip
    } finally {
      if (mounted) setState(() => _gamesLoading = false);
    }
  }

  Future<void> _refresh() async {
    await Future.wait([
      AppState.instance.refreshAll(),
      _loadGames(),
      _rewardsKey.currentState?.reload() ?? Future<void>.value(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return AppBackground(
      child: RefreshIndicator(
        color: AppColors.gold,
        backgroundColor: AppColors.surface2,
        onRefresh: _refresh,
        child: ListenableBuilder(
          listenable: AppState.instance,
          builder: (context, _) {
            final s = AppState.instance;
            final p = s.progress;
            return CustomScrollView(
              physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
              controller: _scroll,
              slivers: [
                // Avatar + name at the top; sticky logo bar once scrolled (chat + bell in both).
                AppHeaderSliver(controller: _scroll),
                SliverSafeArea(
                  top: false,
                  bottom: false,
                  sliver: SliverPadding(
                    padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
                    sliver: SliverList.list(children: [
                      _BalanceHero(state: s),
                      const SizedBox(height: 16),
                      Row(children: [
                        _QuickAction(icon: Icons.south_west_rounded, label: 'Deposit', color: AppColors.mint, onTap: () => _open(const DepositScreen())),
                        _QuickAction(icon: Icons.north_east_rounded, label: 'Withdraw', color: AppColors.primaryLight, onTap: () => _open(const WithdrawScreen())),
                        _QuickAction(icon: Icons.casino_rounded, label: 'Spin', color: AppColors.gold, onTap: () => HomeShell.goTo(context, 2)),
                        _QuickAction(icon: Icons.sports_esports_rounded, label: 'Games', color: AppColors.warning, onTap: () => HomeShell.goTo(context, 1)),
                      ]),
                      const SizedBox(height: 18),
                      _XpCard(progress: p, xp: s.xp),
                      const SizedBox(height: 8),
                      RewardsPanel(key: _rewardsKey),
                      SectionTitle('Top games',
                          trailing: TextButton(
                            onPressed: () => HomeShell.goTo(context, 1),
                            child: Text('See all', style: AppTheme.body(13, weight: FontWeight.w800, color: AppColors.primaryLight)),
                          )),
                    ]),
                  ),
                ),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 186,
                    child: _gamesLoading
                        ? ListView.separated(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 18),
                            itemCount: 4,
                            separatorBuilder: (_, __) => const SizedBox(width: 12),
                            itemBuilder: (_, __) => const Skeleton(width: 140, height: 186, radius: 20),
                          )
                        : ListView.separated(
                            scrollDirection: Axis.horizontal,
                            physics: const BouncingScrollPhysics(),
                            padding: const EdgeInsets.symmetric(horizontal: 18),
                            itemCount: _games.length > 12 ? 12 : _games.length,
                            separatorBuilder: (_, __) => const SizedBox(width: 12),
                            itemBuilder: (_, i) => _GameTile(game: _games[i]),
                          ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 120)),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _open(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    await AppState.instance.refreshWallet().catchError((_) {});
  }
}

class _BalanceHero extends StatelessWidget {
  const _BalanceHero({required this.state});
  final AppState state;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: AppColors.heroGradient,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
        boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.25), blurRadius: 40, offset: const Offset(0, 16))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('Current Wallet', style: AppTheme.body(13, weight: FontWeight.w700, color: AppColors.muted)),
          const Spacer(),
          const Icon(Icons.shield_moon_outlined, color: AppColors.primaryLight, size: 18),
        ]),
        const SizedBox(height: 8),
        state.walletLoaded
            ? FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(money(state.currentWallet), style: AppTheme.display(40, weight: FontWeight.w800, color: AppColors.goldLight)),
              )
            : const Skeleton(height: 44, width: 180),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(18)),
          child: Row(children: [
            const Icon(Icons.card_giftcard_rounded, color: AppColors.mint, size: 20),
            const SizedBox(width: 10),
            Text('Bonus Wallet', style: AppTheme.body(13, color: AppColors.muted)),
            const Spacer(),
            Text(money(state.bonusWallet), style: AppTheme.display(16, color: AppColors.mint)),
          ]),
        ),
      ]),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.icon, required this.label, required this.color, required this.onTap});
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Panel(
          onTap: onTap,
          padding: const EdgeInsets.symmetric(vertical: 14),
          radius: 20,
          child: Column(children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.14), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(height: 8),
            Text(label, style: AppTheme.body(12, weight: FontWeight.w800)),
          ]),
        ),
      ),
    );
  }
}

class _XpCard extends StatelessWidget {
  const _XpCard({required this.progress, required this.xp});
  final XpProgress progress;
  final double xp;
  @override
  Widget build(BuildContext context) {
    final next = progress.next;
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.bolt_rounded, color: AppColors.gold, size: 20),
          const SizedBox(width: 6),
          Text('XP Level', style: AppTheme.display(15)),
          const Spacer(),
          Text('${compactInt(xp)} XP', style: AppTheme.body(13, weight: FontWeight.w800, color: AppColors.gold)),
        ]),
        const SizedBox(height: 12),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: progress.ratio),
          duration: const Duration(milliseconds: 900),
          curve: Curves.easeOutCubic,
          builder: (_, v, __) => ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: Stack(children: [
              Container(height: 10, color: AppColors.surface3),
              FractionallySizedBox(
                widthFactor: v.clamp(0.0, 1.0).toDouble(),
                child: Container(height: 10, decoration: const BoxDecoration(gradient: AppColors.goldGradient)),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          next == null ? '${progress.current.name} — top level reached' : '${compactInt(progress.remaining)} XP to ${next.name}',
          style: AppTheme.body(12, color: AppColors.muted),
        ),
      ]),
    );
  }
}

class _GameTile extends StatelessWidget {
  const _GameTile({required this.game});
  final Map<String, dynamic> game;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => showGameSheet(context, game),
      child: SizedBox(
        width: 140,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: NetImage(strOf(game['thumbnail']), radius: 20, cacheWidth: 300),
          ),
          const SizedBox(height: 8),
          Text(strOf(game['title']), style: AppTheme.body(13, weight: FontWeight.w800), maxLines: 1, overflow: TextOverflow.ellipsis),
        ]),
      ),
    );
  }
}
