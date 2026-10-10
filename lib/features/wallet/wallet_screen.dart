import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';
import 'deposit_screen.dart';
import 'redeem_screen.dart';
import 'withdraw_screen.dart';

/// Wallet tab: both balances and the same five histories as the website (/api/wallet/history).
class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});
  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> with AutomaticKeepAliveClientMixin {
  static const _tabs = [('wallet', 'Wallet'), ('bonus', 'Bonus'), ('game', 'Game'), ('transfer', 'Transfer'), ('bets', 'Bets')];
  Map<String, List<Map<String, dynamic>>> _history = {};
  String _tab = 'wallet';
  bool _loading = true;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final results = await Future.wait([
        ApiClient.instance.get('/api/wallet/history'),
        AppState.instance.refreshWallet().then((_) => <String, dynamic>{}),
      ]);
      final d = results[0];
      if (!mounted) return;
      setState(() => _history = {for (final t in _tabs) t.$1: listOf(d[t.$1])});
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final rows = _history[_tab] ?? const [];
    return AppBackground(
      child: RefreshIndicator(
        color: AppColors.gold,
        onRefresh: _load,
        child: ListenableBuilder(
          listenable: AppState.instance,
          builder: (context, _) {
            final s = AppState.instance;
            return CustomScrollView(
              physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
              slivers: [
                SliverSafeArea(
                  bottom: false,
                  sliver: SliverPadding(
                    padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
                    sliver: SliverList.list(children: [
                      Text('Wallet', style: AppTheme.display(28)),
                      const SizedBox(height: 16),
                      Row(children: [
                        Expanded(child: _BalanceCard(label: 'Current Wallet', value: s.currentWallet, color: AppColors.goldLight, icon: Icons.account_balance_wallet_rounded)),
                        const SizedBox(width: 12),
                        Expanded(child: _BalanceCard(label: 'Bonus Wallet', value: s.bonusWallet, color: AppColors.mint, icon: Icons.card_giftcard_rounded)),
                      ]),
                      const SizedBox(height: 14),
                      Row(children: [
                        Expanded(child: PrimaryButton(label: 'Deposit', icon: Icons.south_west_rounded, gold: true, onPressed: () => _open(const DepositScreen()))),
                        const SizedBox(width: 12),
                        Expanded(child: PrimaryButton(label: 'Withdraw', icon: Icons.north_east_rounded, onPressed: () => _open(const WithdrawScreen()))),
                      ]),
                      const SizedBox(height: 12),
                      GhostButton(label: 'Redeem game score', icon: Icons.savings_outlined, onPressed: () => _open(const RedeemScreen())),
                      const SizedBox(height: 22),
                      Text('History', style: AppTheme.display(18)),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 40,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          children: [
                            for (final t in _tabs)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: Text(t.$2),
                                  selected: _tab == t.$1,
                                  onSelected: (_) => setState(() => _tab = t.$1),
                                  selectedColor: AppColors.primary,
                                  labelStyle: AppTheme.body(13, weight: FontWeight.w800, color: _tab == t.$1 ? Colors.white : AppColors.muted),
                                  side: const BorderSide(color: AppColors.stroke),
                                  showCheckmark: false,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                    ]),
                  ),
                ),
                if (_loading)
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    sliver: SliverList.separated(
                      itemCount: 5,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, __) => const Skeleton(height: 64, radius: 18),
                    ),
                  )
                else if (_error != null)
                  SliverToBoxAdapter(child: ErrorRetry(message: _error!, onRetry: _load))
                else if (rows.isEmpty)
                  const SliverToBoxAdapter(child: EmptyState(icon: Icons.receipt_long_rounded, title: 'No transactions yet', subtitle: 'Your activity shows up here.'))
                else
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    sliver: SliverList.separated(
                      itemCount: rows.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => _HistoryRow(row: rows[i], bets: _tab == 'bets'),
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
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.label, required this.value, required this.color, required this.icon});
  final String label;
  final double value;
  final Color color;
  final IconData icon;
  @override
  Widget build(BuildContext context) {
    return Panel(
      gradient: AppColors.heroGradient,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 10),
        Text(label, style: AppTheme.body(12, color: AppColors.muted)),
        const SizedBox(height: 2),
        FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(money(value), style: AppTheme.display(22, color: color))),
      ]),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.row, required this.bets});
  final Map<String, dynamic> row;
  final bool bets;
  @override
  Widget build(BuildContext context) {
    final amount = numOf(row['amount']);
    final credit = amount >= 0;
    final title = bets ? '${strOf(row['game'])} · ${strOf(row['label'])}' : strOf(row['label']);
    return Panel(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      radius: 18,
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: (credit ? AppColors.mint : AppColors.danger).withValues(alpha: 0.12), shape: BoxShape.circle),
          child: Icon(credit ? Icons.trending_up_rounded : Icons.trending_down_rounded, color: credit ? AppColors.mint : AppColors.danger, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: AppTheme.body(14, weight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(shortDateTime(row['at']), style: AppTheme.body(12, color: AppColors.faint)),
          ]),
        ),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(money(amount, sign: true), style: AppTheme.display(14, color: credit ? AppColors.mint : AppColors.danger)),
          const SizedBox(height: 4),
          StatusChip(strOf(row['status'])),
        ]),
      ]),
    );
  }
}
