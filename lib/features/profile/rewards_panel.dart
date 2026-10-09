import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';
import 'kyc_screen.dart';

/// XP rewards waiting for the player (same server rules as the website):
///  * deposit XP — one per approved deposit (/api/deposits/xp-rewards)
///  * KYC XP — 350 XP once, after KYC is approved (/api/kyc/xp-reward)
class RewardsPanel extends StatefulWidget {
  const RewardsPanel({super.key});
  @override
  State<RewardsPanel> createState() => RewardsPanelState();
}

class RewardsPanelState extends State<RewardsPanel> {
  List<Map<String, dynamic>> _deposit = [];
  String _kycState = 'off';
  double _kycXp = 350;
  String? _claiming;

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    try {
      final results = await Future.wait([
        ApiClient.instance.get('/api/deposits/xp-rewards').catchError((_) => <String, dynamic>{}),
        ApiClient.instance.get('/api/kyc/xp-reward').catchError((_) => <String, dynamic>{}),
      ]);
      if (!mounted) return;
      setState(() {
        _deposit = listOf(results[0]['rewards']);
        _kycState = strOf(results[1]['state'], 'off');
        _kycXp = numOf(results[1]['xp'], 350);
      });
    } catch (_) {}
  }

  Future<void> _claimDeposit(String id) async {
    setState(() => _claiming = id);
    try {
      final d = await ApiClient.instance.post('/api/deposits/xp-rewards', {'id': id});
      if (mounted) _celebrate(numOf(d['xp']));
      await AppState.instance.refreshProfile().catchError((_) {});
      await reload();
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _claiming = null);
    }
  }

  Future<void> _claimKyc() async {
    setState(() => _claiming = 'kyc');
    try {
      final d = await ApiClient.instance.post('/api/kyc/xp-reward', {});
      if (mounted) _celebrate(numOf(d['xp'], _kycXp));
      await AppState.instance.refreshProfile().catchError((_) {});
      await reload();
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _claiming = null);
    }
  }

  void _celebrate(double xp) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        child: Padding(
          padding: const EdgeInsets.all(26),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(gradient: AppColors.primaryGradient, shape: BoxShape.circle),
              child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 40),
            ),
            const SizedBox(height: 14),
            Text('+${compactInt(xp)} XP', style: AppTheme.display(38, weight: FontWeight.w800, color: AppColors.goldLight)),
            const SizedBox(height: 6),
            Text('Added to your level', style: AppTheme.body(14, color: AppColors.muted)),
            const SizedBox(height: 18),
            PrimaryButton(label: 'Awesome', gold: true, onPressed: () => Navigator.of(ctx).pop()),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cards = <Widget>[
      if (_kycState == 'claimable')
        _RewardCard(
          icon: Icons.verified_user_rounded,
          title: 'Account verified',
          subtitle: 'Claim your KYC bonus',
          xp: _kycXp,
          busy: _claiming == 'kyc',
          onClaim: _claimKyc,
        ),
      if (_kycState == 'verify')
        _RewardCard(
          icon: Icons.shield_outlined,
          title: 'Verify your account',
          subtitle: 'Complete KYC and claim',
          xp: _kycXp,
          action: 'Verify',
          onClaim: () async {
            await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const KycScreen()));
            reload();
          },
        ),
      for (final r in _deposit)
        _RewardCard(
          icon: Icons.south_west_rounded,
          title: '${money(numOf(r['deposit_amount']))} deposit',
          subtitle: strOf(r['method_label']).isEmpty ? 'Deposit reward' : 'via ${strOf(r['method_label'])}',
          xp: numOf(r['xp_amount']),
          busy: _claiming == strOf(r['id']),
          onClaim: () => _claimDeposit(strOf(r['id'])),
        ),
    ];
    if (cards.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionTitle('Rewards to claim'),
      for (final c in cards) Padding(padding: const EdgeInsets.only(bottom: 10), child: c),
    ]);
  }
}

class _RewardCard extends StatelessWidget {
  const _RewardCard({required this.icon, required this.title, required this.subtitle, required this.xp, required this.onClaim, this.busy = false, this.action = 'Claim'});
  final IconData icon;
  final String title;
  final String subtitle;
  final double xp;
  final VoidCallback onClaim;
  final bool busy;
  final String action;

  @override
  Widget build(BuildContext context) {
    return Panel(
      border: AppColors.primary.withValues(alpha: 0.45),
      padding: const EdgeInsets.all(14),
      child: Row(children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(gradient: AppColors.primaryGradient, borderRadius: BorderRadius.circular(14)),
          child: Icon(icon, color: Colors.white),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: AppTheme.body(14, weight: FontWeight.w800)),
            Text('$subtitle · +${compactInt(xp)} XP', style: AppTheme.body(12, color: AppColors.muted)),
          ]),
        ),
        SizedBox(
          width: 92,
          child: PrimaryButton(label: action, gold: true, height: 42, loading: busy, onPressed: onClaim),
        ),
      ]),
    );
  }
}
