import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';
import '../wallet/deposit_screen.dart';
import 'deals_models.dart';

/// Loads the offers and this player's progress from the website.
Future<DealsData> fetchDeals() async => DealsData.fromJson(await ApiClient.instance.get('/api/dazzling-deals'));

/// Dazzling Deals (Promo): the website's two offers, the Exclusive Weekly Reward and the Loyalty
/// Bonus. Offer text, amounts and on/off switches come from the back office and refresh every few
/// seconds while this screen is open, so an admin's change shows up here without an app update.
class DealsScreen extends StatefulWidget {
  const DealsScreen({super.key, this.onPlay});

  /// Opens the Games tab ("Play & earn XP").
  final VoidCallback? onPlay;

  @override
  State<DealsScreen> createState() => _DealsScreenState();
}

class _DealsScreenState extends State<DealsScreen> with WidgetsBindingObserver {
  /// How often the offers are re-read while the screen is open.
  static const _refreshEvery = Duration(seconds: 8);

  DealsData? _data;
  String? _loadError;
  String? _claimError;
  String? _busy; // 'weekly' | 'loyalty' while a claim is running
  bool _loading = false;
  bool _foreground = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _timer = Timer.periodic(_refreshEvery, (_) {
      if (_foreground && _busy == null) _load(quiet: true);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) _load(quiet: true);
  }

  Future<void> _load({bool quiet = false}) async {
    if (_loading) return;
    _loading = true;
    try {
      final data = await fetchDeals();
      if (!mounted) return;
      // A claim finished meanwhile: its answer is newer than this one.
      if (_busy != null) return;
      if (_data == null || _data!.signature != data.signature || _loadError != null) {
        setState(() {
          _data = data;
          _loadError = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted && !quiet && _data == null) setState(() => _loadError = e.message);
    } catch (_) {
      if (mounted && !quiet && _data == null) setState(() => _loadError = 'Could not load Dazzling Deals. Please try again.');
    } finally {
      _loading = false;
    }
  }

  Future<void> _refresh() async {
    await _load(quiet: _data != null);
    unawaited(AppState.instance.refreshProfile().catchError((_) {}));
  }

  Future<void> _claim(String kind) async {
    if (_busy != null) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _busy = kind;
      _claimError = null;
    });
    try {
      final d = await ApiClient.instance.post('/api/dazzling-deals', {'kind': kind});
      if (!mounted) return;
      final amount = numOf(d['amount']);
      final level = d['level'] is num ? (d['level'] as num).toInt() : null;
      final status = DealsStatus.fromJson(d['status']);
      final current = _data;
      setState(() {
        _busy = null;
        if (current != null && status != null) _data = DealsData(settings: current.settings, ready: current.ready, status: status);
      });
      if (d['bonusWallet'] is num) AppState.instance.applyWallet({'bonusWallet': d['bonusWallet']});
      unawaited(AppState.instance.refreshWallet().catchError((_) {}));
      await _showWin(kind: kind, amount: amount, level: level);
      if (mounted) unawaited(_load(quiet: true));
    } on ApiException catch (e) {
      // The server explains every refusal in plain words (not reached, already claimed, paused…).
      if (mounted) {
        setState(() {
          _busy = null;
          _claimError = e.message;
        });
        unawaited(_load(quiet: true));
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = null;
          _claimError = 'Could not claim this offer. Please try again.';
        });
      }
    }
  }

  Future<void> _showWin({required String kind, required double amount, required int? level}) {
    return showAppPopup<void>(
      context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 6, 24, 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 74,
            height: 74,
            decoration: BoxDecoration(
              gradient: AppColors.goldGradient,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: AppColors.gold.withValues(alpha: 0.45), blurRadius: 26)],
            ),
            child: const Icon(Icons.card_giftcard_rounded, color: Color(0xFF1A1200), size: 36),
          ),
          const SizedBox(height: 16),
          Text(
            kind == 'weekly' ? 'Weekly reward claimed' : 'Level ${level ?? ''} loyalty bonus'.replaceAll('  ', ' '),
            style: AppTheme.body(14, weight: FontWeight.w700, color: AppColors.muted),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text('+${dealMoney(amount)}', style: AppTheme.display(40, color: AppColors.gold)),
          const SizedBox(height: 6),
          Text('Added to your Bonus Wallet.', style: AppTheme.body(14, color: AppColors.mint), textAlign: TextAlign.center),
          const SizedBox(height: 22),
          PrimaryButton(label: 'Awesome', gold: true, onPressed: () => Navigator.of(ctx).pop()),
        ]),
      ),
    );
  }

  void _openDeposit() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DepositScreen())).then((_) {
      if (mounted) _load(quiet: true);
    });
  }

  void _play() {
    final onPlay = widget.onPlay;
    Navigator.of(context).maybePop();
    onPlay?.call();
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return Scaffold(
      appBar: AppBar(title: const Text('Dazzling Deals')),
      body: AppBackground(
        child: data == null && _loadError != null
            ? Center(child: ErrorRetry(message: _loadError!, onRetry: _load))
            : RefreshIndicator(
                onRefresh: _refresh,
                color: AppColors.gold,
                backgroundColor: AppColors.surface2,
                child: ListenableBuilder(
                  // Levels and XP names come from the shared app state.
                  listenable: AppState.instance,
                  builder: (context, _) => ListView(
                    physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                    padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
                    children: [
                      const _Header(),
                      const SizedBox(height: 14),
                      if (data != null && !data.ready) ...[
                        const _Note(icon: Icons.hourglass_top_rounded, text: 'Dazzling Deals are being set up. Check back soon.', color: AppColors.muted),
                        const SizedBox(height: 12),
                      ],
                      if (dealLockMessage(data?.status?.lock) != null) ...[
                        _Note(icon: Icons.lock_outline_rounded, text: dealLockMessage(data?.status?.lock)!, color: AppColors.gold),
                        const SizedBox(height: 12),
                      ],
                      if (_claimError != null) ...[
                        _Note(icon: Icons.error_outline_rounded, text: _claimError!, color: AppColors.danger),
                        const SizedBox(height: 12),
                      ],
                      _WeeklyCard(
                        data: data,
                        busy: _busy == 'weekly',
                        locked: _busy != null,
                        onClaim: () => _claim('weekly'),
                        onDeposit: _openDeposit,
                      ),
                      const SizedBox(height: 16),
                      _LoyaltyCard(
                        data: data,
                        busy: _busy == 'loyalty',
                        locked: _busy != null,
                        onClaim: () => _claim('loyalty'),
                        onPlay: _play,
                      ),
                      const SizedBox(height: 16),
                      const _Rules(),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Panel(
      gradient: AppColors.heroGradient,
      border: AppColors.gold.withValues(alpha: 0.3),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: AppColors.gold.withValues(alpha: 0.45)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.auto_awesome_rounded, size: 12, color: AppColors.gold),
            const SizedBox(width: 5),
            Text('PROMO', style: AppTheme.body(10, weight: FontWeight.w800, color: AppColors.gold)),
          ]),
        ),
        const SizedBox(height: 10),
        Text('Dazzling Deals', style: AppTheme.display(28, color: AppColors.goldLight)),
        const SizedBox(height: 6),
        Text(
          'Exclusive rewards for our players. Unlock cashback every week and claim a bigger bonus each time you level up.',
          style: AppTheme.body(13.5, color: AppColors.muted, height: 1.4),
        ),
      ]),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text, required this.color});
  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 14, 11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 17, color: color),
        const SizedBox(width: 9),
        Expanded(child: Text(text, style: AppTheme.body(13, weight: FontWeight.w600, color: color, height: 1.35))),
      ]),
    );
  }
}

/// Coloured status chip on a deal card.
class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color, this.dot = true});
  final String label;
  final Color color;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (dot) ...[
          Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
        ],
        Text(label, style: AppTheme.body(11, weight: FontWeight.w800, color: color)),
      ]),
    );
  }
}

/// The shared frame of a deal card: icon, title, status chip, description, body and button.
class _DealCard extends StatelessWidget {
  const _DealCard({
    required this.accent,
    required this.icon,
    required this.title,
    required this.description,
    required this.pill,
    required this.children,
    required this.cta,
  });
  final Color accent;
  final IconData icon;
  final String title;
  final String description;
  final Widget pill;
  final List<Widget> children;
  final Widget cta;

  @override
  Widget build(BuildContext context) {
    return Panel(
      border: accent.withValues(alpha: 0.35),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(color: accent.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(15)),
            child: Icon(icon, color: accent, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: AppTheme.display(18), maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 6),
              Align(alignment: Alignment.centerLeft, child: pill),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        Text(description, style: AppTheme.body(13.5, color: AppColors.muted, height: 1.4)),
        const SizedBox(height: 16),
        ...children,
        const SizedBox(height: 16),
        cta,
      ]),
    );
  }
}

/// A deal button that cannot be used right now (paused, claimed, locked, loading).
class _MutedCta extends StatelessWidget {
  const _MutedCta({required this.label, this.icon, this.loading = false});
  final String label;
  final IconData? icon;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 54,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.surface3,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.stroke),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (loading)
          const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.muted))
        else if (icon != null)
          Icon(icon, size: 18, color: AppColors.muted),
        if (loading || icon != null) const SizedBox(width: 8),
        Flexible(
          child: Text(label, style: AppTheme.body(14.5, weight: FontWeight.w800, color: AppColors.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ]),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.ratio, required this.color});
  final double ratio;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: ratio.clamp(0.0, 1.0).toDouble()),
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutCubic,
        builder: (_, value, __) => LinearProgressIndicator(
          value: value,
          minHeight: 10,
          backgroundColor: AppColors.surface3,
          valueColor: AlwaysStoppedAnimation<Color>(color),
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value, this.color = AppColors.text});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.stroke)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: AppTheme.body(11, color: AppColors.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 3),
          FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: AppTheme.display(16, color: color))),
        ]),
      ),
    );
  }
}

/// Exclusive Weekly Reward: deposit the target this week, claim the cashback.
class _WeeklyCard extends StatelessWidget {
  const _WeeklyCard({required this.data, required this.busy, required this.locked, required this.onClaim, required this.onDeposit});
  final DealsData? data;
  final bool busy;

  /// Another claim is running: no second tap.
  final bool locked;
  final VoidCallback onClaim;
  final VoidCallback onDeposit;

  @override
  Widget build(BuildContext context) {
    final settings = data?.settings ?? DealsSettings.defaults;
    final status = data?.status;
    final target = settings.weeklyDepositTarget;
    final deposits = status?.weekDeposits ?? 0.0;
    final remaining = status == null ? target : weeklyRemaining(deposits, target);
    final reached = status != null && remaining <= 0;
    final claimed = status?.weeklyClaimed == true;

    final Widget cta;
    if (data == null) {
      cta = const _MutedCta(label: 'Loading…', loading: true);
    } else if (!settings.weeklyEnabled) {
      cta = const _MutedCta(label: 'Paused for now', icon: Icons.pause_circle_outline_rounded);
    } else if (!data!.ready || status == null) {
      cta = const _MutedCta(label: 'Coming soon', icon: Icons.hourglass_top_rounded);
    } else if (claimed) {
      cta = const _MutedCta(label: 'Claimed this week', icon: Icons.check_circle_outline_rounded);
    } else if (status.lock == 'loyalty') {
      cta = const _MutedCta(label: 'Available tomorrow', icon: Icons.lock_outline_rounded);
    } else if (reached) {
      cta = PrimaryButton(
        label: 'Claim ${dealMoney(settings.weeklyCashback)} cashback',
        icon: Icons.card_giftcard_rounded,
        gold: true,
        loading: busy,
        onPressed: locked ? null : onClaim,
      );
    } else {
      cta = PrimaryButton(label: settings.weeklyCta, icon: Icons.south_west_rounded, gold: true, onPressed: onDeposit);
    }

    final Widget pill;
    if (!settings.weeklyEnabled) {
      pill = const _Pill(label: 'Paused', color: AppColors.muted, dot: false);
    } else if (claimed) {
      pill = const _Pill(label: 'Claimed', color: AppColors.muted, dot: false);
    } else if (reached) {
      pill = const _Pill(label: 'Unlocked', color: AppColors.mint);
    } else {
      pill = const _Pill(label: 'Live this week', color: AppColors.gold);
    }

    final timeLeft = weekTimeLeft(status?.weekEnd);
    final line = claimed
        ? 'Reward claimed. A new week starts on Monday.'
        : reached
            ? 'Target reached. Claim your cashback now!'
            : '${dealMoney(remaining)} more in deposits to unlock ${dealMoney(settings.weeklyCashback)} cashback.';

    return _DealCard(
      accent: AppColors.gold,
      icon: Icons.workspace_premium_rounded,
      title: settings.weeklyTitle,
      description: settings.weeklyDescription,
      pill: pill,
      cta: cta,
      children: [
        Row(children: [
          _Fact(label: 'Cashback', value: dealMoney(settings.weeklyCashback), color: AppColors.gold),
          const SizedBox(width: 10),
          _Fact(label: 'Weekly target', value: dealMoney(target)),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: Text(
              status == null ? 'Your deposits this week' : '${dealMoney(deposits)} of ${dealMoney(target)} deposited',
              style: AppTheme.body(12.5, weight: FontWeight.w700),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (timeLeft.isNotEmpty) Text(timeLeft, style: AppTheme.body(11.5, color: AppColors.muted)),
        ]),
        const SizedBox(height: 8),
        _Bar(ratio: status == null ? 0.0 : weeklyProgress(deposits, target), color: AppColors.gold),
        if (status != null) ...[
          const SizedBox(height: 10),
          Text(line, style: AppTheme.body(13, weight: FontWeight.w600, color: reached && !claimed ? AppColors.mint : AppColors.muted, height: 1.35)),
        ],
      ],
    );
  }
}

/// Loyalty Bonus: a bigger Bonus Wallet reward at every XP level, one level per day.
class _LoyaltyCard extends StatelessWidget {
  const _LoyaltyCard({required this.data, required this.busy, required this.locked, required this.onClaim, required this.onPlay});
  final DealsData? data;
  final bool busy;
  final bool locked;
  final VoidCallback onClaim;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final settings = data?.settings ?? DealsSettings.defaults;
    final status = data?.status;

    // Levels 1 and up, in order (Level 0 has no bonus), from the admin-editable XP table.
    final tiers = AppState.instance.levels.where((l) => l.level >= 1).toList()..sort((a, b) => a.level.compareTo(b.level));
    final maxLevel = tiers.isEmpty ? 0 : tiers.last.level;
    double? xpFor(int level) {
      for (final t in tiers) {
        if (t.level == level) return t.xpRequired;
      }
      return null;
    }

    final level = status?.level ?? 0;
    final xp = status?.xp ?? 0.0;
    final claimable = status?.loyaltyClaimableLevel;
    // Claims always take the lowest unclaimed level, so every level below it is claimed.
    final claimedUpTo = claimable != null ? claimable - 1 : level;
    final nextLevel = level + 1 > maxLevel ? maxLevel : level + 1;
    final nextXp = xpFor(nextLevel);
    final atTop = level >= maxLevel;
    final xpToGo = nextXp == null || status == null ? null : (nextXp - xp <= 0 ? 0 : (nextXp - xp).ceil());

    final Widget cta;
    if (data == null) {
      cta = const _MutedCta(label: 'Loading…', loading: true);
    } else if (!settings.loyaltyEnabled) {
      cta = const _MutedCta(label: 'Paused for now', icon: Icons.pause_circle_outline_rounded);
    } else if (!data!.ready || status == null) {
      cta = const _MutedCta(label: 'Coming soon', icon: Icons.hourglass_top_rounded);
    } else if (status.lock == 'weekly') {
      cta = const _MutedCta(label: 'Available next Monday', icon: Icons.lock_outline_rounded);
    } else if (claimable != null && status.loyaltyClaimedToday) {
      cta = const _MutedCta(label: 'Next claim tomorrow', icon: Icons.lock_outline_rounded);
    } else if (claimable != null) {
      cta = PrimaryButton(
        label: '${settings.loyaltyCta} · ${dealMoney(settings.loyaltyReward(claimable))}',
        icon: Icons.card_giftcard_rounded,
        loading: busy,
        onPressed: locked ? null : onClaim,
      );
    } else if (atTop) {
      cta = const _MutedCta(label: 'All levels claimed', icon: Icons.check_circle_outline_rounded);
    } else {
      cta = PrimaryButton(label: 'Play & earn XP', icon: Icons.sports_esports_rounded, onPressed: onPlay);
    }

    final Widget pill;
    if (!settings.loyaltyEnabled) {
      pill = const _Pill(label: 'Paused', color: AppColors.muted, dot: false);
    } else if (claimable != null) {
      pill = _Pill(label: 'Level $claimable ready', color: AppColors.mint);
    } else {
      pill = _Pill(label: status == null ? 'Every level' : 'Level $level', color: AppColors.primaryLight);
    }

    String line = '';
    if (status != null) {
      if (claimable != null) {
        line = 'Your Level $claimable bonus is ready.';
      } else if (!atTop && xpToGo != null) {
        line = '${compactInt(xpToGo)} XP to Level $nextLevel to unlock ${dealMoney(settings.loyaltyReward(nextLevel))}.';
      } else if (atTop) {
        line = 'You reached the top level.';
      }
    }

    return _DealCard(
      accent: AppColors.mint,
      icon: Icons.military_tech_rounded,
      title: settings.loyaltyTitle,
      description: settings.loyaltyDescription,
      pill: pill,
      cta: cta,
      children: [
        for (final tier in tiers)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _LevelRow(
              level: tier.level,
              name: tier.name,
              xpRequired: tier.xpRequired,
              reward: settings.loyaltyReward(tier.level),
              state: status == null
                  ? _LevelState.locked
                  : tier.level <= claimedUpTo
                      ? _LevelState.claimed
                      : tier.level == claimable
                          ? _LevelState.ready
                          : tier.level <= level
                              ? _LevelState.waiting
                              : _LevelState.locked,
            ),
          ),
        if (status != null) ...[
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: Text(atTop ? 'Level $level (max)' : 'Level $level → $nextLevel', style: AppTheme.body(12.5, weight: FontWeight.w700)),
            ),
            Text('${compactInt(xp)} XP', style: AppTheme.body(11.5, color: AppColors.muted)),
          ]),
          const SizedBox(height: 8),
          _Bar(ratio: atTop || nextXp == null || nextXp <= 0 ? 1.0 : xp / nextXp, color: AppColors.mint),
          if (line.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(line, style: AppTheme.body(13, weight: FontWeight.w600, color: claimable != null ? AppColors.mint : AppColors.muted, height: 1.35)),
          ],
        ],
      ],
    );
  }
}

enum _LevelState { claimed, ready, waiting, locked }

/// One level of the Loyalty Bonus ladder.
class _LevelRow extends StatelessWidget {
  const _LevelRow({required this.level, required this.name, required this.xpRequired, required this.reward, required this.state});
  final int level;
  final String name;
  final double xpRequired;
  final double reward;
  final _LevelState state;

  @override
  Widget build(BuildContext context) {
    final ready = state == _LevelState.ready;
    final claimed = state == _LevelState.claimed;
    final locked = state == _LevelState.locked;
    final color = ready ? AppColors.mint : (claimed ? AppColors.muted : (locked ? AppColors.faint : AppColors.primaryLight));
    final note = switch (state) {
      _LevelState.claimed => 'Claimed',
      _LevelState.ready => 'Ready to claim',
      _LevelState.waiting => 'Reached · claim next',
      _LevelState.locked => '${compactInt(xpRequired)} XP',
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 14, 9),
      decoration: BoxDecoration(
        color: ready ? AppColors.mint.withValues(alpha: 0.1) : AppColors.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ready ? AppColors.mint.withValues(alpha: 0.5) : AppColors.stroke),
      ),
      child: Row(children: [
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.16), shape: BoxShape.circle),
          child: claimed
              ? Icon(Icons.check_rounded, size: 18, color: color)
              : locked
                  ? Icon(Icons.lock_outline_rounded, size: 15, color: color)
                  : Text('$level', style: AppTheme.display(14, color: color)),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Level $level · $name', style: AppTheme.body(13.5, weight: FontWeight.w800, color: claimed ? AppColors.muted : AppColors.text), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 1),
            Text(note, style: AppTheme.body(11.5, color: ready ? AppColors.mint : AppColors.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
        const SizedBox(width: 8),
        Text(
          dealMoney(reward),
          style: AppTheme.display(15, color: claimed ? AppColors.faint : (ready ? AppColors.mint : AppColors.gold)).copyWith(
            decoration: claimed ? TextDecoration.lineThrough : null,
            decorationColor: AppColors.faint,
          ),
        ),
      ]),
    );
  }
}

class _Rules extends StatelessWidget {
  const _Rules();

  @override
  Widget build(BuildContext context) {
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('How Dazzling Deals work', style: AppTheme.display(15)),
        const SizedBox(height: 10),
        for (var i = 0; i < kDealRules.length; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i == kDealRules.length - 1 ? 0 : 9),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Container(width: 5, height: 5, decoration: const BoxDecoration(color: AppColors.gold, shape: BoxShape.circle)),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(kDealRules[i], style: AppTheme.body(12.5, color: AppColors.muted, height: 1.4))),
            ]),
          ),
      ]),
    );
  }
}

/// Dazzling Deals entry on the Home tab, with the player's most useful next step.
/// Hidden when the admin switched both offers off.
class DealsBanner extends StatefulWidget {
  const DealsBanner({super.key, this.onPlay});
  final VoidCallback? onPlay;

  @override
  State<DealsBanner> createState() => DealsBannerState();
}

class DealsBannerState extends State<DealsBanner> {
  static const _refreshEvery = Duration(seconds: 45);
  DealsData? _data;
  Timer? _timer;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    reload();
    _timer = Timer.periodic(_refreshEvery, (_) => reload());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Also called by the Home tab's pull-to-refresh.
  Future<void> reload() async {
    if (_loading) return;
    _loading = true;
    try {
      final data = await fetchDeals();
      if (mounted && _data?.signature != data.signature) setState(() => _data = data);
    } catch (_) {
      // Keep showing the last answer.
    } finally {
      _loading = false;
    }
  }

  ({String text, bool ready}) _headline(DealsData? data) {
    const fallback = (text: 'Weekly cashback and a bonus at every level.', ready: false);
    if (data == null) return fallback;
    final s = data.settings;
    final st = data.status;
    if (st == null || !data.ready) return fallback;
    final weeklyOpen = s.weeklyEnabled && !st.weeklyClaimed && st.lock != 'loyalty';
    final remaining = weeklyRemaining(st.weekDeposits, s.weeklyDepositTarget);
    if (weeklyOpen && remaining <= 0) {
      return (text: 'Your ${dealMoney(s.weeklyCashback)} weekly cashback is ready to claim!', ready: true);
    }
    final claimable = st.loyaltyClaimableLevel;
    if (s.loyaltyEnabled && st.lock != 'weekly' && claimable != null && !st.loyaltyClaimedToday) {
      return (text: 'Your Level $claimable bonus of ${dealMoney(s.loyaltyReward(claimable))} is ready to claim!', ready: true);
    }
    if (weeklyOpen) {
      return (text: '${dealMoney(remaining)} more in deposits unlocks ${dealMoney(s.weeklyCashback)} cashback this week.', ready: false);
    }
    return fallback;
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    if (data != null && !data.settings.weeklyEnabled && !data.settings.loyaltyEnabled) return const SizedBox.shrink();
    final headline = _headline(data);
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Panel(
        gradient: AppColors.heroGradient,
        border: AppColors.gold.withValues(alpha: headline.ready ? 0.7 : 0.35),
        padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
        onTap: () {
          HapticFeedback.selectionClick();
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => DealsScreen(onPlay: widget.onPlay))).then((_) => reload());
        },
        child: Row(children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(gradient: AppColors.goldGradient, borderRadius: BorderRadius.circular(15)),
            child: const Icon(Icons.local_offer_rounded, color: Color(0xFF1A1200), size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text('Dazzling Deals', style: AppTheme.display(16, color: AppColors.goldLight), maxLines: 1, overflow: TextOverflow.ellipsis)),
                if (headline.ready) ...[
                  const SizedBox(width: 8),
                  const _Pill(label: 'Ready', color: AppColors.mint),
                ],
              ]),
              const SizedBox(height: 3),
              Text(headline.text, style: AppTheme.body(12.5, color: headline.ready ? AppColors.mint : AppColors.muted, height: 1.35), maxLines: 2, overflow: TextOverflow.ellipsis),
            ]),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppColors.gold),
        ]),
      ),
    );
  }
}
