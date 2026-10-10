import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';
import 'games_repo.dart';

/// One game: create the account, see the login, add score, redeem, transfer and play.
/// Every action is the website's own endpoint, so caps, KYC, XP rules and review flow are identical.
Future<void> showGameSheet(BuildContext context, Map<String, dynamic> game) {
  return showAppPopup<void>(
    context,
    builder: (_) => _GameSheet(game: game),
  );
}

class _GameSheet extends StatefulWidget {
  const _GameSheet({required this.game});
  final Map<String, dynamic> game;
  @override
  State<_GameSheet> createState() => _GameSheetState();
}

class _GameSheetState extends State<_GameSheet> {
  Map<String, dynamic>? _account;
  Map<String, dynamic>? _pendingBuy;
  Map<String, dynamic>? _pendingRedeem;
  Map<String, dynamic> _redeemCap = {};
  bool _loading = true;
  String? _error;

  String get _slug => strOf(widget.game['slug']);
  String get _title => strOf(widget.game['title']);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final q = {'game': _slug};
      final results = await Future.wait([
        ApiClient.instance.get('/api/game-accounts', query: q),
        ApiClient.instance.get('/api/game-accounts/buy-score', query: q).catchError((_) => <String, dynamic>{}),
        ApiClient.instance.get('/api/game-accounts/redeem', query: q).catchError((_) => <String, dynamic>{}),
      ]);
      if (!mounted) return;
      final buy = mapOf(results[1]['buy']);
      final redeem = mapOf(results[2]['redeem']);
      setState(() {
        _account = results[0]['account'] is Map ? mapOf(results[0]['account']) : null;
        _pendingBuy = strOf(buy['status']) == 'pending' ? buy : null;
        _pendingRedeem = strOf(redeem['status']) == 'pending' ? redeem : null;
        _redeemCap = results[2];
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _play() async {
    final url = strOf(widget.game['webUrl']);
    if (url.isEmpty) return;
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  Future<void> _downloadGame() async {
    final url = strOf(widget.game['androidUrl']);
    if (url.isEmpty) return;
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              SizedBox(width: 64, height: 64, child: NetImage(strOf(widget.game['thumbnail']), radius: 16, cacheWidth: 160)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_title, style: AppTheme.display(20)),
                  const SizedBox(height: 4),
                  if (_account != null) StatusChip(_accountLabel(strOf(_account!['status']))),
                ]),
              ),
            ]),
            const SizedBox(height: 18),
            if (_loading)
              const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              ErrorRetry(message: _error!, onRetry: _load)
            else if (_account == null || strOf(_account!['status']) == 'rejected')
              _CreateAccount(slug: _slug, title: _title, rejected: _account != null, note: strOf(_account?['admin_note']), onDone: _load)
            else if (strOf(_account!['status']) == 'pending')
              const _InfoBox(icon: Icons.hourglass_top_rounded, text: 'Your game account is being created. You will see your login here as soon as it is ready.')
            else
              _ReadyAccount(
                game: widget.game,
                account: _account!,
                pendingBuy: _pendingBuy,
                pendingRedeem: _pendingRedeem,
                redeemCap: _redeemCap,
                onChanged: _load,
                onPlay: _play,
                onDownload: _downloadGame,
              ),
          ]),
        ),
      ),
    );
  }

  String _accountLabel(String status) => switch (status) {
        'ready' => 'Approved',
        'rejected' => 'Rejected',
        _ => 'Pending',
      };
}

class _InfoBox extends StatelessWidget {
  const _InfoBox({required this.icon, required this.text, this.color = AppColors.warning});
  final IconData icon;
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16), border: Border.all(color: color.withValues(alpha: 0.3))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: AppTheme.body(13, weight: FontWeight.w600, color: color))),
      ]),
    );
  }
}

/// Current Wallet / Bonus Wallet picker (score always comes from one of the two).
class WalletPicker extends StatelessWidget {
  const WalletPicker({super.key, required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) {
    final s = AppState.instance;
    return Row(children: [
      for (final w in const [('current', 'Current Wallet'), ('bonus', 'Bonus Wallet')])
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: w.$1 == 'current' ? 8 : 0),
            child: Panel(
              onTap: () => onChanged(w.$1),
              padding: const EdgeInsets.all(12),
              radius: 16,
              border: value == w.$1 ? AppColors.gold : null,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(w.$2, style: AppTheme.body(12, weight: FontWeight.w700, color: AppColors.muted)),
                const SizedBox(height: 4),
                Text(money(w.$1 == 'current' ? s.currentWallet : s.bonusWallet), style: AppTheme.display(15, color: value == w.$1 ? AppColors.gold : AppColors.text)),
              ]),
            ),
          ),
        ),
    ]);
  }
}

class AmountField extends StatelessWidget {
  const AmountField({super.key, required this.controller, this.label = 'Amount', this.hint = '0.00'});
  final TextEditingController controller;
  final String label;
  final String hint;
  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d{0,7}(\.\d{0,2})?'))],
      style: AppTheme.display(18),
      decoration: InputDecoration(labelText: label, hintText: hint, prefixText: '\$ '),
    );
  }
}

class _CreateAccount extends StatefulWidget {
  const _CreateAccount({required this.slug, required this.title, required this.rejected, required this.note, required this.onDone});
  final String slug;
  final String title;
  final bool rejected;
  final String note;
  final VoidCallback onDone;
  @override
  State<_CreateAccount> createState() => _CreateAccountState();
}

class _CreateAccountState extends State<_CreateAccount> {
  String _wallet = 'current';
  final _amount = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amount = double.tryParse(_amount.text) ?? 0;
    if (amount <= 0) {
      toast(context, 'Enter a score greater than 0.', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final d = await ApiClient.instance.post('/api/game-accounts', {
        'gameSlug': widget.slug,
        'gameTitle': widget.title,
        'source': 'auto',
        'wallet': _wallet,
        'amount': amount,
      });
      AppState.instance.applyWallet(d);
      if (mounted) toast(context, 'Account requested. It will be ready shortly.');
      widget.onDone();
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (widget.rejected)
        _InfoBox(
          icon: Icons.error_outline_rounded,
          color: AppColors.danger,
          text: widget.note.isEmpty ? 'Your last request was rejected. You can request again.' : 'Rejected: ${widget.note}',
        ),
      Text('Create your ${widget.title} account', style: AppTheme.display(16)),
      const SizedBox(height: 6),
      Text('Choose the wallet and the score to load. We create the login and add the score for you.',
          style: AppTheme.body(13, color: AppColors.muted)),
      const SizedBox(height: 14),
      WalletPicker(value: _wallet, onChanged: (w) => setState(() => _wallet = w)),
      const SizedBox(height: 12),
      AmountField(controller: _amount, label: 'Starting score'),
      const SizedBox(height: 16),
      PrimaryButton(label: 'Create account', gold: true, loading: _busy, onPressed: _submit),
    ]);
  }
}

class _ReadyAccount extends StatelessWidget {
  const _ReadyAccount({
    required this.game,
    required this.account,
    required this.pendingBuy,
    required this.pendingRedeem,
    required this.redeemCap,
    required this.onChanged,
    required this.onPlay,
    required this.onDownload,
  });
  final Map<String, dynamic> game;
  final Map<String, dynamic> account;
  final Map<String, dynamic>? pendingBuy;
  final Map<String, dynamic>? pendingRedeem;
  final Map<String, dynamic> redeemCap;
  final VoidCallback onChanged;
  final VoidCallback onPlay;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final username = strOf(account['username']);
    final password = strOf(account['password']);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Panel(
        padding: const EdgeInsets.all(14),
        child: Column(children: [
          _CopyRow(label: 'Username', value: username),
          const Divider(height: 18),
          _CopyRow(label: 'Password', value: password, secret: true),
          const Divider(height: 18),
          Row(children: [
            Text('Score on file', style: AppTheme.body(13, color: AppColors.muted)),
            const Spacer(),
            Text(money(numOf(account['current_score']) + numOf(account['bonus_score'])).replaceFirst('\$', ''),
                style: AppTheme.display(15, color: AppColors.gold)),
          ]),
        ]),
      ),
      const SizedBox(height: 12),
      if (pendingBuy != null)
        _InfoBox(icon: Icons.hourglass_top_rounded, text: 'Add score of ${money(numOf(pendingBuy!['requested_amount'] ?? pendingBuy!['amount']))} is being processed.'),
      if (pendingRedeem != null)
        _InfoBox(icon: Icons.hourglass_top_rounded, text: 'Redeem of ${money(numOf(pendingRedeem!['requested_amount'] ?? pendingRedeem!['amount']))} is waiting for approval.'),
      Row(children: [
        if (strOf(game['webUrl']).isNotEmpty)
          Expanded(child: PrimaryButton(label: 'Play now', icon: Icons.play_arrow_rounded, onPressed: onPlay)),
        if (strOf(game['androidUrl']).isNotEmpty) ...[
          const SizedBox(width: 10),
          Expanded(child: GhostButton(label: 'Get game app', icon: Icons.android_rounded, onPressed: onDownload)),
        ],
      ]),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
          child: _ActionTile(
            icon: Icons.add_circle_outline_rounded,
            label: 'Add score',
            color: AppColors.mint,
            onTap: pendingBuy != null ? null : () => _scoreAction(context, _ScoreAction.add),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ActionTile(
            icon: Icons.savings_outlined,
            label: 'Redeem',
            color: AppColors.gold,
            onTap: pendingRedeem != null ? null : () => _scoreAction(context, _ScoreAction.redeem),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ActionTile(
            icon: Icons.swap_horiz_rounded,
            label: 'Transfer',
            color: AppColors.primaryLight,
            onTap: () => _scoreAction(context, _ScoreAction.transfer),
          ),
        ),
      ]),
      const SizedBox(height: 8),
      TextButton.icon(
        onPressed: () => _resetPassword(context),
        icon: const Icon(Icons.key_rounded, size: 18, color: AppColors.muted),
        label: Text('Reset game password', style: AppTheme.body(13, weight: FontWeight.w700, color: AppColors.muted)),
      ),
    ]);
  }

  Future<void> _resetPassword(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Reset password?', style: AppTheme.display(18)),
        content: Text('A new password is set for this game account.', style: AppTheme.body(14, color: AppColors.muted)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reset')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ApiClient.instance.patch('/api/game-accounts', {'gameSlug': strOf(game['slug'])});
      if (context.mounted) toast(context, 'Password reset.');
      onChanged();
    } on ApiException catch (e) {
      if (context.mounted) toast(context, e.message, error: true);
    }
  }

  Future<void> _scoreAction(BuildContext context, _ScoreAction action) async {
    final done = await showAppPopup<bool>(
      context,
      builder: (_) => _ScoreActionSheet(game: game, action: action, redeemCap: redeemCap),
    );
    if (done == true) onChanged();
  }
}

class _CopyRow extends StatefulWidget {
  const _CopyRow({required this.label, required this.value, this.secret = false});
  final String label;
  final String value;
  final bool secret;
  @override
  State<_CopyRow> createState() => _CopyRowState();
}

class _CopyRowState extends State<_CopyRow> {
  late bool _hidden = widget.secret;
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Text(widget.label, style: AppTheme.body(13, color: AppColors.muted)),
      const Spacer(),
      Flexible(
        child: Text(_hidden ? '••••••••' : widget.value,
            style: AppTheme.body(14, weight: FontWeight.w800), overflow: TextOverflow.ellipsis),
      ),
      if (widget.secret)
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 18),
          onPressed: () => setState(() => _hidden = !_hidden),
        ),
      IconButton(
        visualDensity: VisualDensity.compact,
        icon: const Icon(Icons.copy_rounded, size: 18),
        onPressed: () {
          Clipboard.setData(ClipboardData(text: widget.value));
          toast(context, '${widget.label} copied');
        },
      ),
    ]);
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.icon, required this.label, required this.color, required this.onTap});
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? 0.45 : 1,
      child: Panel(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(vertical: 14),
        radius: 18,
        child: Column(children: [
          Icon(icon, color: color),
          const SizedBox(height: 6),
          Text(label, style: AppTheme.body(12, weight: FontWeight.w800)),
        ]),
      ),
    );
  }
}

enum _ScoreAction { add, redeem, transfer }

class _ScoreActionSheet extends StatefulWidget {
  const _ScoreActionSheet({required this.game, required this.action, required this.redeemCap});
  final Map<String, dynamic> game;
  final _ScoreAction action;
  final Map<String, dynamic> redeemCap;
  @override
  State<_ScoreActionSheet> createState() => _ScoreActionSheetState();
}

class _ScoreActionSheetState extends State<_ScoreActionSheet> {
  String _wallet = 'current';
  String? _toSlug;
  List<Map<String, dynamic>> _myOtherGames = [];
  final _amount = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.action == _ScoreAction.transfer) _loadMine();
  }

  Future<void> _loadMine() async {
    try {
      final d = await ApiClient.instance.get('/api/game-accounts');
      final slug = strOf(widget.game['slug']);
      if (!mounted) return;
      setState(() {
        _myOtherGames = listOf(d['accounts']).where((a) => strOf(a['status']) == 'ready' && strOf(a['game_slug']) != slug).toList();
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  String get _title => switch (widget.action) {
        _ScoreAction.add => 'Add score',
        _ScoreAction.redeem => 'Redeem score',
        _ScoreAction.transfer => 'Transfer score',
      };

  Future<void> _submit() async {
    final amount = double.tryParse(_amount.text) ?? 0;
    if (amount <= 0) {
      toast(context, 'Enter a score greater than 0.', error: true);
      return;
    }
    final slug = strOf(widget.game['slug']);
    setState(() => _busy = true);
    try {
      switch (widget.action) {
        case _ScoreAction.add:
          await ApiClient.instance.post('/api/game-accounts/buy-score', {'gameSlug': slug, 'wallet': _wallet, 'amount': amount});
          if (mounted) toast(context, 'Add score requested. It is added once confirmed.');
        case _ScoreAction.redeem:
          final d = await ApiClient.instance.post('/api/game-accounts/redeem', {'gameSlug': slug, 'wallet': _wallet, 'amount': amount});
          final xp = numOf(d['xpAmount']);
          if (mounted) {
            toast(context, xp > 0 ? 'Redeem requested. ${compactInt(xp)} went to your XP (daily cap).' : 'Redeem requested. You will be paid once approved.');
          }
        case _ScoreAction.transfer:
          if (_toSlug == null) {
            toast(context, 'Choose the game to transfer into.', error: true);
            return;
          }
          await ApiClient.instance.post('/api/game-accounts/transfer', {'fromGameSlug': slug, 'toGameSlug': _toSlug, 'amount': amount});
          if (mounted) toast(context, 'Transfer requested.');
      }
      await AppState.instance.refreshWallet().catchError((_) {});
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cap = widget.redeemCap;
    final starter = cap['starter'] == true;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(_title, style: AppTheme.display(20)),
          const SizedBox(height: 6),
          Text(
            switch (widget.action) {
              _ScoreAction.add => 'Score is taken from the wallet you choose and loaded onto ${strOf(widget.game['title'])}.',
              _ScoreAction.redeem => starter
                  ? 'At your level part of a redeem is paid as cash and the rest boosts your XP, decided when it is approved.'
                  : 'Daily redeem left today: ${money(numOf(cap['dailyRemaining']))}. Anything above it goes to XP.',
              _ScoreAction.transfer => 'Move score from ${strOf(widget.game['title'])} to another of your games.',
            },
            style: AppTheme.body(13, color: AppColors.muted),
          ),
          const SizedBox(height: 14),
          if (widget.action != _ScoreAction.transfer) WalletPicker(value: _wallet, onChanged: (w) => setState(() => _wallet = w)),
          if (widget.action == _ScoreAction.transfer)
            _myOtherGames.isEmpty
                ? Text('You need another ready game account to transfer into.', style: AppTheme.body(13, color: AppColors.warning))
                : Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final g in _myOtherGames)
                      ChoiceChip(
                        label: Text(GamesRepo.instance.titleFor(strOf(g['game_slug']))),
                        selected: _toSlug == strOf(g['game_slug']),
                        onSelected: (_) => setState(() => _toSlug = strOf(g['game_slug'])),
                        selectedColor: AppColors.primary,
                      ),
                  ]),
          const SizedBox(height: 12),
          AmountField(controller: _amount, label: 'Score'),
          const SizedBox(height: 16),
          PrimaryButton(label: _title, gold: widget.action != _ScoreAction.transfer, loading: _busy, onPressed: _submit),
        ]),
      ),
    );
  }
}
