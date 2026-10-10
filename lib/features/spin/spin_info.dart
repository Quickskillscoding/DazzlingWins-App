import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';

// The Spin & Win rules, with the same numbers the website shows (lib/spin-rules.ts). The server
// enforces every one of them; these constants are only for the text.
const int kFreeSpinCycleDays = 5;
const int kFreeSpinUnlockDeposit = 5;
const int kPaidExtraSpinPrice = 1;
const int kSpinBonusTtlHours = 72;

/// The rules of the wheel, as plain sentences.
const List<({IconData icon, String text})> kSpinRules = [
  (icon: Icons.schedule_rounded, text: 'One free spin every 24 hours for $kFreeSpinCycleDays days.'),
  (
    icon: Icons.lock_clock_outlined,
    text: 'On day ${kFreeSpinCycleDays + 1} the wheel is blocked. Deposit \$$kFreeSpinUnlockDeposit or more to unlock $kFreeSpinCycleDays more days. '
        'Any deposit of \$$kFreeSpinUnlockDeposit+ unlocks exactly $kFreeSpinCycleDays days.',
  ),
  (
    icon: Icons.bolt_rounded,
    text: 'Want an extra spin today? After a \$$kFreeSpinUnlockDeposit+ deposit you can buy one extra spin for \$$kPaidExtraSpinPrice '
        'from your Current Wallet during each 24-hour wait.',
  ),
  (icon: Icons.savings_outlined, text: 'Every slice wins \$1 to \$5, added to your Bonus Wallet right away.'),
  (
    icon: Icons.hourglass_bottom_rounded,
    text: 'Spin winnings must be used within $kSpinBonusTtlHours hours. Any unused spin bonus then expires from your Bonus Wallet.',
  ),
  (icon: Icons.verified_user_outlined, text: 'Your account must be verified (KYC) before you can spin.'),
];

/// "Spin More, Win More!" rules card shown on the Spin tab.
class SpinRulesCard extends StatelessWidget {
  const SpinRulesCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Panel(
      border: AppColors.gold.withValues(alpha: 0.28),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: AppColors.gold.withValues(alpha: 0.14), shape: BoxShape.circle),
            child: const Icon(Icons.menu_book_rounded, color: AppColors.gold, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Spin More, Win More!', style: AppTheme.display(16, color: AppColors.gold)),
              Text('Spin rules', style: AppTheme.body(12, color: AppColors.muted)),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        for (var i = 0; i < kSpinRules.length; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i == kSpinRules.length - 1 ? 0 : 11),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(kSpinRules[i].icon, size: 17, color: AppColors.primaryLight),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(kSpinRules[i].text, style: AppTheme.body(13, color: AppColors.text.withValues(alpha: 0.86), height: 1.4))),
            ]),
          ),
      ]),
    );
  }
}

/// One spin of the player (from the server, so spins made on the website are listed too).
class SpinHistoryEntry {
  const SpinHistoryEntry({required this.id, required this.label, required this.at, required this.amount, required this.purchase});
  final String id;
  final String label;
  final DateTime? at;

  /// Dollars won (0 = no win). For a [purchase] it is the price paid, as a negative number.
  final double amount;

  /// A $1 extra spin bought from the Current Wallet.
  final bool purchase;
}

/// Picks the Spin Wheel rows out of the website's /api/wallet/history answer, newest first.
List<SpinHistoryEntry> spinHistoryFrom(Map<String, dynamic> history) {
  final out = <SpinHistoryEntry>[];
  for (final row in listOf(history['bets'])) {
    if (strOf(row['game']) != 'Spin Wheel') continue;
    final id = strOf(row['id']);
    final amount = numOf(row['amount']);
    out.add(SpinHistoryEntry(
      id: id,
      label: strOf(row['label'], 'Spin'),
      at: parseTime(row['at']),
      amount: amount,
      purchase: id.startsWith('bet-spin-buy-') || amount < 0,
    ));
  }
  out.sort((a, b) => (b.at?.millisecondsSinceEpoch ?? 0).compareTo(a.at?.millisecondsSinceEpoch ?? 0));
  return out;
}

/// The same look-back tabs as the website's Spin History.
const List<({String label, Duration window})> kSpinHistoryWindows = [
  (label: '24 hours', window: Duration(hours: 24)),
  (label: '7 days', window: Duration(days: 7)),
  (label: '30 days', window: Duration(days: 30)),
  (label: '12 months', window: Duration(days: 365)),
];

List<SpinHistoryEntry> filterSpinHistory(List<SpinHistoryEntry> all, Duration window, {DateTime? now}) {
  final cutoff = (now ?? DateTime.now()).subtract(window);
  return all.where((e) => e.at != null && !e.at!.isBefore(cutoff)).toList(growable: false);
}

/// Opens the player's Spin History.
Future<void> showSpinHistorySheet(BuildContext context) {
  return showAppPopup<void>(
    context,
    builder: (_) => const _SpinHistorySheet(),
  );
}

class _SpinHistorySheet extends StatefulWidget {
  const _SpinHistorySheet();
  @override
  State<_SpinHistorySheet> createState() => _SpinHistorySheetState();
}

class _SpinHistorySheetState extends State<_SpinHistorySheet> {
  List<SpinHistoryEntry>? _all;
  String? _error;
  int _tab = 2; // 30 days

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final data = await ApiClient.instance.get('/api/wallet/history');
      if (mounted) setState(() => _all = spinHistoryFrom(data));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load your spin history. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final all = _all;
    final shown = all == null ? const <SpinHistoryEntry>[] : filterSpinHistory(all, kSpinHistoryWindows[_tab].window);
    final spins = shown.where((e) => !e.purchase).length;
    final won = shown.where((e) => !e.purchase).fold<double>(0, (sum, e) => sum + e.amount);

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.82),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 8, 10),
          child: Row(children: [
            Expanded(child: Text('Spin History', style: AppTheme.display(20))),
            IconButton(
              tooltip: 'Close',
              icon: const Icon(Icons.close_rounded, color: AppColors.muted),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ]),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(children: [
            for (var i = 0; i < kSpinHistoryWindows.length; i++)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _FilterChip(label: kSpinHistoryWindows[i].label, selected: i == _tab, onTap: () => setState(() => _tab = i)),
              ),
          ]),
        ),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(children: [
            Expanded(child: _Summary(label: 'Spins', value: all == null ? '—' : compactInt(spins))),
            const SizedBox(width: 10),
            Expanded(child: _Summary(label: 'Total won', value: all == null ? '—' : money(won), gold: true)),
          ]),
        ),
        const SizedBox(height: 12),
        Flexible(
          child: _error != null && all == null
              ? ErrorRetry(message: _error!, onRetry: _load)
              : all == null
                  ? const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
                  : shown.isEmpty
                      ? const SingleChildScrollView(
                          child: EmptyState(
                            icon: Icons.casino_outlined,
                            title: 'No spins in this period',
                            subtitle: 'Spin the wheel and your rewards show up here.',
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
                          itemCount: shown.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (_, i) => _SpinRow(entry: shown[i]),
                        ),
        ),
      ]),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.gold : AppColors.surface2,
      shape: StadiumBorder(side: BorderSide(color: selected ? AppColors.gold : AppColors.stroke)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(label, style: AppTheme.body(13, weight: FontWeight.w800, color: selected ? const Color(0xFF1A1200) : AppColors.muted)),
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.label, required this.value, this.gold = false});
  final String label;
  final String value;
  final bool gold;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.stroke),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: AppTheme.body(12, color: AppColors.muted)),
        const SizedBox(height: 3),
        Text(value, style: AppTheme.display(18, color: gold ? AppColors.gold : AppColors.text), maxLines: 1, overflow: TextOverflow.ellipsis),
      ]),
    );
  }
}

class _SpinRow extends StatelessWidget {
  const _SpinRow({required this.entry});
  final SpinHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final win = !e.purchase && e.amount > 0;
    final color = e.purchase ? AppColors.muted : (win ? AppColors.mint : AppColors.faint);
    final title = e.purchase ? 'Extra spin purchase' : (win ? 'Spin reward' : 'No win');
    final amount = e.purchase ? money(e.amount) : (win ? money(e.amount, sign: true) : money(0));
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 14, 11),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.stroke),
      ),
      child: Row(children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(color: (win ? AppColors.gold : AppColors.muted).withValues(alpha: 0.14), shape: BoxShape.circle),
          child: Icon(e.purchase ? Icons.bolt_rounded : Icons.casino_rounded, size: 19, color: win ? AppColors.gold : AppColors.muted),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: AppTheme.body(14, weight: FontWeight.w800), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(
              e.purchase ? '${shortDateTime(e.at?.millisecondsSinceEpoch)} · Current Wallet' : '${shortDateTime(e.at?.millisecondsSinceEpoch)} · Bonus Wallet',
              style: AppTheme.body(12, color: AppColors.muted),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ]),
        ),
        const SizedBox(width: 10),
        Text(amount, style: AppTheme.display(15, color: color)),
      ]),
    );
  }
}
