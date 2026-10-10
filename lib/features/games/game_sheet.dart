import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';
import '../wallet/deposit_screen.dart';
import 'game_rules.dart';
import 'games_repo.dart';
import 'lucky_reels.dart';

/// Opens one game's page: create the account (Auto or Manual), see the login, add score, redeem,
/// transfer, game history and play. Every action is the website's own endpoint, so caps, KYC,
/// XP rules and the review flow are identical to the site.
Future<void> showGameSheet(BuildContext context, Map<String, dynamic> game) {
  return Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => GameScreen(game: game)));
}

/// Opens the Redeem Score window for one game: the same window, wording and server rules as the
/// Redeem button on the game's own page. [redeemInfo] is the answer of GET /api/game-accounts/redeem.
/// Returns true when a redeem request was sent.
Future<bool> showRedeemSheet(BuildContext context, Map<String, dynamic> game, Map<String, dynamic> redeemInfo) async {
  final done = await showAppPopup<bool>(context, builder: (_) => _RedeemSheet(game: game, info: redeemInfo));
  return done == true;
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

/// Dollar amount box (deposit, withdraw).
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

/// Game score box (score is points, so no dollar sign).
class _ScoreField extends StatelessWidget {
  const _ScoreField({required this.controller, this.onChanged});
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d{0,7}(\.\d{0,2})?'))],
      style: AppTheme.display(18),
      decoration: const InputDecoration(hintText: 'Enter score'),
    );
  }
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
        Expanded(child: Text(text, style: AppTheme.body(13, weight: FontWeight.w600, color: color, height: 1.35))),
      ]),
    );
  }
}

Text _fieldLabel(String text) => Text(text, style: AppTheme.body(13.5, weight: FontWeight.w800));

double _parseScore(String text) => double.tryParse(text.trim()) ?? 0;

String _scoreText(double v) => money(v).replaceFirst('\$', '');

// ───────────────────────────────────────────────────────────────────────────
// The game page
// ───────────────────────────────────────────────────────────────────────────

enum _CreateStep { choose, manual, score }

class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.game});
  final Map<String, dynamic> game;
  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with WidgetsBindingObserver {
  /// How often the page asks the server while a request is waiting for the team.
  static const _pollEvery = Duration(seconds: 3);

  late Map<String, dynamic> _game = Map<String, dynamic>.from(widget.game);
  Map<String, dynamic>? _account;
  Map<String, dynamic>? _buy;
  Map<String, dynamic>? _redeem;
  Map<String, dynamic>? _transfer;
  Map<String, dynamic> _redeemInfo = const {};
  Map<String, dynamic> _transferInfo = const {};
  bool _loading = true;
  bool _fetching = false;
  bool _foreground = true;
  String? _error;
  String? _notice;
  Timer? _poll;

  // Create account
  _CreateStep _step = _CreateStep.choose;
  String _source = 'auto';
  final _username = TextEditingController();
  final _password = TextEditingController();
  String? _manualError;
  bool _hidePassword = true;

  /// The page saw this account while it was still pending: its approval is celebrated once.
  bool _awaitingAccount = false;
  bool _celebrated = false;

  /// Wait screens the player chose to hide ('buy', 'redeem', 'transfer').
  final Set<String> _hiddenWaits = <String>{};

  String get _slug => strOf(_game['slug']);
  String get _title => strOf(_game['title'], 'Game');
  String get _status => strOf(_account?['status']);

  bool _pendingRow(Map<String, dynamic>? row) => row != null && requestOutcome(row['status']) == 'pending';

  bool get _anythingPending => _status == 'pending' || _pendingRow(_buy) || _pendingRow(_redeem) || _pendingRow(_transfer);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fillFromCatalog();
    _load();
    unawaited(AppState.instance.refreshWallet().catchError((_) {}));
    _poll = Timer.periodic(_pollEvery, (_) {
      if (_foreground && _anythingPending) _load(quiet: true);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) _load(quiet: true);
  }

  /// A page opened with only the slug (My Games, Redeem) gets its picture and links from the catalogue.
  Future<void> _fillFromCatalog() async {
    try {
      final games = await GamesRepo.instance.load();
      final hit = games.where((g) => strOf(g['slug']) == _slug);
      if (hit.isEmpty || !mounted) return;
      // Start from the catalogue entry; keep whatever the caller already knew.
      final merged = Map<String, dynamic>.from(hit.first);
      _game.forEach((key, value) {
        if (value != null && !(value is String && value.isEmpty)) merged[key] = value;
      });
      setState(() => _game = merged);
    } catch (_) {
      // The page still works without the picture and links.
    }
  }

  Future<void> _load({bool quiet = false}) async {
    if (_fetching) return;
    _fetching = true;
    try {
      final q = {'game': _slug};
      Future<Map<String, dynamic>> soft(String path) => ApiClient.instance.get(path, query: q).catchError((_) => <String, dynamic>{});
      final results = await Future.wait([
        ApiClient.instance.get('/api/game-accounts', query: q),
        soft('/api/game-accounts/buy-score'),
        soft('/api/game-accounts/redeem'),
        soft('/api/game-accounts/transfer'),
      ]);
      if (!mounted) return;
      final account = results[0]['account'] is Map ? mapOf(results[0]['account']) : null;
      final buy = results[1]['buy'] is Map ? mapOf(results[1]['buy']) : null;
      final redeem = results[2]['redeem'] is Map ? mapOf(results[2]['redeem']) : null;
      final transfer = results[3]['transfer'] is Map ? mapOf(results[3]['transfer']) : null;

      final before = _status;
      final after = strOf(account?['status']);
      final messages = <({String text, bool error})>[];
      String? notice = _notice;
      var celebrate = false;

      if (after == 'pending') _awaitingAccount = true;
      if (_awaitingAccount && after == 'ready' && !_celebrated) {
        _celebrated = true;
        _awaitingAccount = false;
        celebrate = true;
        notice = null;
      }
      if ((before == 'pending' || _awaitingAccount) && (account == null || after == 'rejected')) {
        _awaitingAccount = false;
        final reason = strOf(account?['admin_note']);
        notice = reason.isEmpty
            ? 'This account request was declined. Ask our agents in Live Chat for the reason.'
            : 'This account request was declined: $reason';
      }

      void settled(String kind, Map<String, dynamic>? old, Map<String, dynamic>? now, String done, String rejected) {
        if (!_pendingRow(old)) return;
        if (now == null || strOf(now['id']) != strOf(old!['id'])) return;
        final outcome = requestOutcome(now['status']);
        if (outcome == 'pending') return;
        _hiddenWaits.remove(kind);
        messages.add((text: outcome == 'done' ? done : rejected, error: outcome != 'done'));
      }

      settled('buy', _buy, buy, 'Score added to $_title.', 'Your add-score request was declined.');
      settled('redeem', _redeem, redeem, 'Your redeem was approved.', 'Your redeem request was declined.');
      settled('transfer', _transfer, transfer, 'Your transfer is done.', 'Your transfer request was declined.');

      setState(() {
        _account = account;
        _buy = buy;
        _redeem = redeem;
        _transfer = transfer;
        _redeemInfo = results[2];
        _transferInfo = results[3];
        _notice = notice;
        _error = null;
        _loading = false;
        if (after == 'ready' || after == 'pending') _step = _CreateStep.choose;
      });

      if (messages.isNotEmpty || celebrate) {
        unawaited(AppState.instance.refreshWallet().catchError((_) {}));
        unawaited(AppState.instance.refreshProfile().catchError((_) {}));
      }
      for (final m in messages) {
        if (mounted) toast(context, m.text, error: m.error);
      }
      if (celebrate && mounted && account != null) {
        HapticFeedback.heavyImpact();
        await showAppPopup<void>(context, builder: (_) => _AccountCreatedCard(account: account));
      }
    } on ApiException catch (e) {
      if (mounted && !quiet) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted && !quiet) {
        setState(() {
          _error = 'Could not load this game. Please try again.';
          _loading = false;
        });
      }
    } finally {
      _fetching = false;
    }
  }

  // ── Create account ─────────────────────────────────────────────────────────

  void _chooseAuto() {
    HapticFeedback.selectionClick();
    setState(() {
      _source = 'auto';
      _step = _CreateStep.score;
      _notice = null;
    });
  }

  void _chooseManual() {
    HapticFeedback.selectionClick();
    setState(() {
      _source = 'manual';
      _step = _CreateStep.manual;
      _manualError = null;
      _notice = null;
    });
  }

  void _manualContinue() {
    final username = _username.text.trim();
    final password = _password.text.trim();
    if (!isValidGameUsername(username)) {
      setState(() => _manualError = kUsernameRule);
      return;
    }
    if (!isValidGamePassword(password)) {
      setState(() => _manualError = 'Enter a password.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _manualError = null;
      _step = _CreateStep.score;
    });
  }

  /// Sends the create-account request. Returns an error text, or null when it was accepted.
  Future<String?> _createAccount(String wallet, double amount) async {
    try {
      final d = await ApiClient.instance.post('/api/game-accounts', {
        'gameSlug': _slug,
        'gameTitle': _title,
        'source': _source,
        if (_source == 'manual') 'username': _username.text.trim(),
        if (_source == 'manual') 'password': _password.text.trim(),
        'wallet': wallet,
        'amount': amount,
      });
      AppState.instance.applyWallet(d);
      if (!mounted) return null;
      final account = d['account'] is Map ? mapOf(d['account']) : null;
      setState(() {
        _awaitingAccount = true;
        _celebrated = false;
        _notice = null;
        // Straight to the wait screen; the next refresh confirms it.
        _account = account ?? <String, dynamic>{'status': 'pending', 'game_slug': _slug, 'game_title': _title};
        _step = _CreateStep.choose;
      });
      unawaited(_load(quiet: true));
      return null;
    } on ApiException catch (e) {
      // A taken username or password: back to the login step with the server's reason.
      if (_source == 'manual' && mounted && (e.message.contains('sername') || e.message.contains('assword') || e.message.contains('redentials'))) {
        setState(() {
          _manualError = e.message;
          _step = _CreateStep.manual;
        });
        return null;
      }
      return e.message;
    } catch (_) {
      return 'Could not create the game account. Please try again.';
    }
  }

  // ── Actions on a ready account ─────────────────────────────────────────────

  Future<void> _addScore() async {
    final done = await showAppPopup<bool>(
      context,
      builder: (ctx) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: _ScoreForm(
          title: 'Buy Score',
          submitLabel: 'Buy Score',
          onCancel: () => Navigator.of(ctx).pop(false),
          onSubmit: (wallet, amount) async {
            try {
              await ApiClient.instance.post('/api/game-accounts/buy-score', {'gameSlug': _slug, 'wallet': wallet, 'amount': amount});
              unawaited(AppState.instance.refreshWallet().catchError((_) {}));
              if (ctx.mounted) Navigator.of(ctx).pop(true);
              return null;
            } on ApiException catch (e) {
              return e.message;
            } catch (_) {
              return 'Could not submit your add-score request. Please try again.';
            }
          },
        ),
      ),
    );
    if (done == true && mounted) {
      _hiddenWaits.remove('buy');
      await _load(quiet: true);
    }
  }

  Future<void> _redeemScore() async {
    final done = await showRedeemSheet(context, _game, _redeemInfo);
    if (done && mounted) {
      _hiddenWaits.remove('redeem');
      await _load(quiet: true);
    }
  }

  Future<void> _transferScore() async {
    final done = await showAppPopup<bool>(context, builder: (_) => _TransferSheet(game: _game, info: _transferInfo));
    if (done == true && mounted) {
      _hiddenWaits.remove('transfer');
      await _load(quiet: true);
    }
  }

  Future<void> _resetPassword() async {
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
    if (ok != true || !mounted) return;
    try {
      final d = await ApiClient.instance.patch('/api/game-accounts', {'gameSlug': _slug});
      if (!mounted) return;
      if (d['account'] is Map) setState(() => _account = mapOf(d['account']));
      toast(context, 'Password reset.');
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } catch (_) {
      if (mounted) toast(context, 'Could not reset this password. Please try again.', error: true);
    }
  }

  Future<void> _open(String url) async {
    if (url.isEmpty) return;
    try {
      final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!ok && mounted) toast(context, 'Could not open the link. Please try again.', error: true);
    } catch (_) {
      if (mounted) toast(context, 'Could not open the link. Please try again.', error: true);
    }
  }

  void _copy(String text, String message) {
    HapticFeedback.selectionClick();
    Clipboard.setData(ClipboardData(text: text));
    toast(context, message);
  }

  // ── UI ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      // Back walks the create steps before it leaves the page.
      canPop: _status == 'ready' || _status == 'pending' || _step == _CreateStep.choose,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        setState(() => _step = _step == _CreateStep.score && _source == 'manual' ? _CreateStep.manual : _CreateStep.choose);
      },
      child: Scaffold(
        appBar: AppBar(title: Text(_title, maxLines: 1, overflow: TextOverflow.ellipsis)),
        body: AppBackground(child: _body()),
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _account == null) return Center(child: ErrorRetry(message: _error!, onRetry: _load));

    if (_status == 'pending') {
      return const LuckyReelsWait(lines: kCreateLines, subtitle: 'Your account is being created and score is being added. Please wait.');
    }
    if (_status != 'ready') return _createFlow();

    if (_pendingRow(_buy) && !_hiddenWaits.contains('buy')) {
      return LuckyReelsWait(
        title: 'Add Score',
        lines: kBuyLines,
        subtitle: 'Your add-score request for $_title is waiting for admin approval. Please wait.',
        onHide: () => setState(() => _hiddenWaits.add('buy')),
      );
    }
    if (_pendingRow(_redeem) && !_hiddenWaits.contains('redeem')) {
      return LuckyReelsWait(
        title: 'Redeem Reels',
        lines: kRedeemLines,
        subtitle: 'Your score is being redeemed and transferred to ${walletName(strOf(_redeem!['wallet']))}. Please wait.',
        onHide: () => setState(() => _hiddenWaits.add('redeem')),
      );
    }
    if (_pendingRow(_transfer) && !_hiddenWaits.contains('transfer')) {
      final t = _transfer!;
      return LuckyReelsWait(
        title: 'Transfer Reels',
        lines: kTransferLines,
        subtitle: 'Your score is being transferred from ${strOf(t['from_game_title'], _title)} to ${strOf(t['to_game_title'], 'your other game')}. Please wait.',
        onHide: () => setState(() => _hiddenWaits.add('transfer')),
      );
    }
    return _overview();
  }

  Widget _gameHeader() {
    final thumbnail = strOf(_game['thumbnail']);
    return Row(children: [
      SizedBox(
        width: 68,
        height: 68,
        child: thumbnail.isEmpty
            ? Container(
                decoration: BoxDecoration(color: AppColors.surface3, borderRadius: BorderRadius.circular(18)),
                child: const Icon(Icons.sports_esports_rounded, color: AppColors.muted),
              )
            : NetImage(thumbnail, radius: 18, cacheWidth: 180),
      ),
      const SizedBox(width: 14),
      Expanded(child: Text(_title, style: AppTheme.display(22), maxLines: 2, overflow: TextOverflow.ellipsis)),
    ]);
  }

  Widget _createFlow() {
    final rejected = _status == 'rejected';
    final Widget content;
    switch (_step) {
      case _CreateStep.choose:
        content = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SizedBox(height: 6),
          Text('Welcome to DazzlingWins Game Hub', style: AppTheme.display(24), textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text('Create account to Enjoy the Game', style: AppTheme.body(14.5, color: AppColors.muted), textAlign: TextAlign.center),
          const SizedBox(height: 24),
          PrimaryButton(label: 'Auto Create Account', icon: Icons.autorenew_rounded, onPressed: _chooseAuto),
          const SizedBox(height: 6),
          Text('We pick a username and password for you.', style: AppTheme.body(12, color: AppColors.faint), textAlign: TextAlign.center),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(children: [
              const Expanded(child: Divider()),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text('or', style: AppTheme.body(12, color: AppColors.faint))),
              const Expanded(child: Divider()),
            ]),
          ),
          GhostButton(label: 'Manual Create Account', icon: Icons.menu_book_outlined, onPressed: _chooseManual),
          const SizedBox(height: 6),
          Text('You choose your own username and password.', style: AppTheme.body(12, color: AppColors.faint), textAlign: TextAlign.center),
        ]);
      case _CreateStep.manual:
        content = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Manual Create Account', style: AppTheme.display(20)),
          const SizedBox(height: 6),
          Text('Enter your username and password, then create the account.', style: AppTheme.body(13.5, color: AppColors.muted)),
          const SizedBox(height: 16),
          TextField(
            controller: _username,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.next,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9._-]')), LengthLimitingTextInputFormatter(24)],
            onChanged: (_) {
              if (_manualError != null) setState(() => _manualError = null);
            },
            decoration: const InputDecoration(labelText: 'Username', hintText: 'yourname123', prefixIcon: Icon(Icons.person_outline_rounded)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: _hidePassword,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.done,
            inputFormatters: [LengthLimitingTextInputFormatter(64)],
            onChanged: (_) {
              if (_manualError != null) setState(() => _manualError = null);
            },
            onSubmitted: (_) => _manualContinue(),
            decoration: InputDecoration(
              labelText: 'Password',
              hintText: 'Your game password',
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              suffixIcon: IconButton(
                icon: Icon(_hidePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                onPressed: () => setState(() => _hidePassword = !_hidePassword),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(kUsernameRule, style: AppTheme.body(12, color: AppColors.faint)),
          if (_manualError != null) ...[
            const SizedBox(height: 10),
            Text(_manualError!, style: AppTheme.body(13, weight: FontWeight.w700, color: AppColors.danger)),
          ],
          const SizedBox(height: 16),
          PrimaryButton(label: 'Continue', gold: true, onPressed: _manualContinue),
          TextButton(
            onPressed: () => setState(() => _step = _CreateStep.choose),
            child: Text('Back', style: AppTheme.body(14, weight: FontWeight.w700, color: AppColors.muted)),
          ),
        ]);
      case _CreateStep.score:
        content = _ScoreForm(
          title: 'Buy Score',
          intro: _source == 'manual'
              ? 'Choose the wallet and the opening score for your account “${_username.text.trim()}”.'
              : 'Choose the wallet and the opening score. We create the login and add the score for you.',
          submitLabel: 'Create account',
          cancelLabel: 'Back',
          onCancel: () => setState(() => _step = _source == 'manual' ? _CreateStep.manual : _CreateStep.choose),
          onSubmit: _createAccount,
        );
    }

    return ListView(
      physics: const BouncingScrollPhysics(),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
      children: [
        _gameHeader(),
        const SizedBox(height: 16),
        if (_notice != null) _InfoBox(icon: Icons.error_outline_rounded, color: AppColors.danger, text: _notice!),
        if (_notice == null && rejected)
          _InfoBox(
            icon: Icons.error_outline_rounded,
            color: AppColors.danger,
            text: strOf(_account?['admin_note']).isEmpty ? 'Your last request was declined. You can request again.' : 'Declined: ${strOf(_account?['admin_note'])}',
          ),
        Panel(child: content),
      ],
    );
  }

  Widget _overview() {
    final account = _account!;
    final username = strOf(account['username']);
    final password = strOf(account['password']);
    final webUrl = strOf(_game['webUrl']);
    final androidUrl = strOf(_game['androidUrl']);
    final buyPending = _pendingRow(_buy);
    final redeemPending = _pendingRow(_redeem);
    final transferPending = _pendingRow(_transfer);

    return RefreshIndicator(
      color: AppColors.gold,
      backgroundColor: AppColors.surface2,
      onRefresh: () => _load(quiet: true),
      child: ListView(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
        children: [
          // Add Score · Redeem · Transfer
          Row(children: [
            Expanded(child: _ActionTile(icon: Icons.add_rounded, label: 'Add Score', color: AppColors.mint, onTap: buyPending ? null : _addScore)),
            const SizedBox(width: 10),
            Expanded(child: _ActionTile(icon: Icons.card_giftcard_rounded, label: 'Redeem', color: AppColors.gold, onTap: redeemPending ? null : _redeemScore)),
            const SizedBox(width: 10),
            Expanded(child: _ActionTile(icon: Icons.swap_horiz_rounded, label: 'Transfer', color: AppColors.primaryLight, onTap: transferPending ? null : _transferScore)),
          ]),
          const SizedBox(height: 14),
          if (buyPending)
            _InfoBox(icon: Icons.hourglass_top_rounded, text: 'Your add-score request of ${_scoreText(numOf(_buy!['requested_amount'] ?? _buy!['amount']))} is waiting for admin approval.'),
          if (redeemPending)
            _InfoBox(icon: Icons.hourglass_top_rounded, text: 'Your redeem of ${_scoreText(numOf(_redeem!['requested_amount'] ?? _redeem!['amount']))} is waiting for approval.'),
          if (transferPending)
            _InfoBox(icon: Icons.hourglass_top_rounded, text: 'Your transfer to ${strOf(_transfer!['to_game_title'], 'your other game')} is waiting for approval.'),
          Panel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _gameHeader(),
              const SizedBox(height: 16),
              _CopyRow(label: 'User Name', value: username, onCopy: () => _copy(username, 'Username copied')),
              const SizedBox(height: 8),
              _CopyRow(label: 'Password', value: password, secret: true, onCopy: () => _copy(password, 'Password copied')),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.stroke)),
                child: Row(children: [
                  Text('Score on file', style: AppTheme.body(13, color: AppColors.muted)),
                  const Spacer(),
                  Text(_scoreText(numOf(account['current_score']) + numOf(account['bonus_score'])), style: AppTheme.display(15, color: AppColors.gold)),
                ]),
              ),
              const SizedBox(height: 14),
              PrimaryButton(
                label: 'Copy Username & Password',
                icon: Icons.copy_all_rounded,
                gold: true,
                onPressed: () => _copy('Username: $username\nPassword: $password', 'Username and password copied'),
              ),
              const SizedBox(height: 10),
              GhostButton(label: 'Reset Password', icon: Icons.refresh_rounded, onPressed: _resetPassword),
            ]),
          ),
          const SizedBox(height: 14),
          if (webUrl.isNotEmpty) ...[
            PrimaryButton(label: 'Play Game', icon: Icons.play_arrow_rounded, onPressed: () => _open(webUrl)),
            const SizedBox(height: 10),
          ],
          GhostButton(
            label: 'Game History',
            icon: Icons.history_rounded,
            onPressed: () => showAppPopup<void>(context, builder: (_) => _HistorySheet(slug: _slug, title: _title)),
          ),
          if (webUrl.isNotEmpty || androidUrl.isNotEmpty) ...[
            const SizedBox(height: 18),
            Panel(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Game Platform', style: AppTheme.body(13.5, weight: FontWeight.w800)),
                const SizedBox(height: 10),
                Wrap(spacing: 10, runSpacing: 10, children: [
                  if (webUrl.isNotEmpty) _PlatformChip(icon: Icons.language_rounded, label: 'Web App', color: AppColors.mint, onTap: () => _open(webUrl)),
                  if (androidUrl.isNotEmpty) _PlatformChip(icon: Icons.android_rounded, label: 'Android', color: AppColors.gold, onTap: () => _open(androidUrl)),
                ]),
                const SizedBox(height: 10),
                Text(
                  'Web App opens the game in your browser. Android downloads the game\'s own app.',
                  style: AppTheme.body(12, color: AppColors.faint, height: 1.35),
                ),
              ]),
            ),
          ],
        ],
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────
// Buy Score form (opening score of a new account, and Add Score)
// ───────────────────────────────────────────────────────────────────────────

class _ScoreForm extends StatefulWidget {
  const _ScoreForm({required this.title, required this.submitLabel, required this.onSubmit, required this.onCancel, this.intro, this.cancelLabel = 'Cancel'});
  final String title;
  final String? intro;
  final String submitLabel;
  final String cancelLabel;

  /// Sends the request. Returns an error text to show, or null when it went through.
  final Future<String?> Function(String wallet, double amount) onSubmit;
  final VoidCallback onCancel;

  @override
  State<_ScoreForm> createState() => _ScoreFormState();
}

class _ScoreFormState extends State<_ScoreForm> {
  final _amount = TextEditingController();
  String _wallet = 'current';
  String? _error;
  bool _needDeposit = false;
  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _deposit() async {
    FocusScope.of(context).unfocus();
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DepositScreen()));
    await AppState.instance.refreshWallet().catchError((_) {});
  }

  Future<void> _submit() async {
    if (_busy) return;
    final amount = _parseScore(_amount.text);
    if (amount <= 0) {
      setState(() {
        _error = 'Enter a score greater than 0.';
        _needDeposit = false;
      });
      return;
    }
    final s = AppState.instance;
    final problem = balanceProblem(wallet: _wallet, amount: amount, currentWallet: s.currentWallet, bonusWallet: s.bonusWallet);
    if (problem != null) {
      setState(() {
        _error = problem;
        _needDeposit = _wallet == 'current';
      });
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
      _needDeposit = false;
    });
    final error = await widget.onSubmit(_wallet, amount);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final note = walletNote(_wallet);
    final noteColor = _wallet == 'bonus' ? AppColors.warning : AppColors.mint;
    final amount = _parseScore(_amount.text);
    return ListenableBuilder(
      // Wallet balances update live (after a deposit, for example).
      listenable: AppState.instance,
      builder: (context, _) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Text(widget.title, style: AppTheme.display(22)),
        if (widget.intro != null) ...[
          const SizedBox(height: 6),
          Text(widget.intro!, style: AppTheme.body(13, color: AppColors.muted, height: 1.35)),
        ],
        const SizedBox(height: 16),
        _fieldLabel('Select Wallet'),
        const SizedBox(height: 8),
        WalletPicker(
          value: _wallet,
          onChanged: (w) => setState(() {
            _wallet = w;
            _error = null;
            _needDeposit = false;
          }),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 11, 14, 11),
          decoration: BoxDecoration(
            color: noteColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: noteColor.withValues(alpha: 0.4)),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.info_outline_rounded, size: 17, color: noteColor),
            const SizedBox(width: 9),
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: '${note.title} ', style: AppTheme.body(12.5, weight: FontWeight.w800, color: noteColor, height: 1.4)),
                  TextSpan(text: note.text, style: AppTheme.body(12.5, color: AppColors.text.withValues(alpha: 0.82), height: 1.4)),
                ]),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 10),
        GhostButton(label: 'Deposit', icon: Icons.account_balance_wallet_outlined, onPressed: _busy ? null : _deposit),
        const SizedBox(height: 16),
        _fieldLabel('Enter Score to Buy'),
        const SizedBox(height: 8),
        _ScoreField(
          controller: _amount,
          onChanged: (_) => setState(() {
            _error = null;
            _needDeposit = false;
          }),
        ),
        const SizedBox(height: 14),
        _fieldLabel('Total Score'),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.stroke)),
          child: Row(children: [
            Expanded(child: Text(_scoreText(amount), style: AppTheme.display(18, color: AppColors.gold))),
            Text('from ${walletName(_wallet)}', style: AppTheme.body(12, color: AppColors.muted)),
          ]),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: AppTheme.body(13, weight: FontWeight.w700, color: AppColors.danger, height: 1.35)),
          if (_needDeposit) ...[
            const SizedBox(height: 10),
            PrimaryButton(label: 'Deposit now', icon: Icons.south_west_rounded, height: 48, onPressed: _deposit),
          ],
        ],
        const SizedBox(height: 18),
        PrimaryButton(label: widget.submitLabel, gold: true, loading: _busy, onPressed: _submit),
        TextButton(
          onPressed: _busy ? null : widget.onCancel,
          child: Text(widget.cancelLabel, style: AppTheme.body(14, weight: FontWeight.w700, color: AppColors.muted)),
        ),
      ]),
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────
// Account Created
// ───────────────────────────────────────────────────────────────────────────

class _AccountCreatedCard extends StatelessWidget {
  const _AccountCreatedCard({required this.account});
  final Map<String, dynamic> account;

  @override
  Widget build(BuildContext context) {
    final username = strOf(account['username']);
    final password = strOf(account['password']);
    final score = numOf(account['score_amount']);
    final wallet = walletName(strOf(account['score_wallet']));
    void copy(String text, String message) {
      HapticFeedback.selectionClick();
      Clipboard.setData(ClipboardData(text: text));
      toast(context, message);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 4, 22, 22),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Center(
          child: Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              gradient: AppColors.goldGradient,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: AppColors.gold.withValues(alpha: 0.45), blurRadius: 24)],
            ),
            child: const Icon(Icons.check_rounded, color: Color(0xFF1A1200), size: 34),
          ),
        ),
        const SizedBox(height: 14),
        Text('Account Created', style: AppTheme.display(24), textAlign: TextAlign.center),
        const SizedBox(height: 4),
        Text('Account created successfully!', style: AppTheme.body(14.5, color: AppColors.muted), textAlign: TextAlign.center),
        const SizedBox(height: 18),
        _CopyRow(label: 'USERNAME', value: username, onCopy: () => copy(username, 'Username copied')),
        const SizedBox(height: 8),
        _CopyRow(label: 'PASSWORD', value: password, onCopy: () => copy(password, 'Password copied')),
        if (score > 0) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.gold.withValues(alpha: 0.45)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('SCORE ADDED', style: AppTheme.body(11, weight: FontWeight.w800, color: AppColors.gold)),
              const SizedBox(height: 3),
              Text('${_scoreText(score).replaceAll('.00', '')} from $wallet', style: AppTheme.body(15, weight: FontWeight.w800)),
            ]),
          ),
        ],
        const SizedBox(height: 10),
        GhostButton(
          label: 'Copy Username & Password',
          icon: Icons.copy_all_rounded,
          onPressed: () => copy('Username: $username\nPassword: $password', 'Username and password copied'),
        ),
        const SizedBox(height: 14),
        Text('Please save these credentials securely!', style: AppTheme.body(13.5, weight: FontWeight.w700, color: AppColors.gold), textAlign: TextAlign.center),
        const SizedBox(height: 16),
        PrimaryButton(label: 'Close', gold: true, onPressed: () => Navigator.of(context).maybePop()),
      ]),
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────
// Redeem Score
// ───────────────────────────────────────────────────────────────────────────

class _RedeemSheet extends StatefulWidget {
  const _RedeemSheet({required this.game, required this.info});
  final Map<String, dynamic> game;
  final Map<String, dynamic> info;
  @override
  State<_RedeemSheet> createState() => _RedeemSheetState();
}

class _RedeemSheetState extends State<_RedeemSheet> {
  final _amount = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final amount = _parseScore(_amount.text);
    if (amount <= 0) {
      setState(() => _error = 'Enter a score greater than 0.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // The website always redeems to the Current Wallet; the server works out the cash / XP split.
      final d = await ApiClient.instance.post('/api/game-accounts/redeem', {'gameSlug': strOf(widget.game['slug']), 'wallet': 'current', 'amount': amount});
      final xp = numOf(d['xpAmount']);
      unawaited(AppState.instance.refreshWallet().catchError((_) {}));
      if (!mounted) return;
      toast(context, xp > 0 ? 'Redeem requested. ${compactInt(xp)} went to your XP (daily cap).' : 'Redeem requested. You will be paid once approved.');
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Could not submit your redeem request. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final starterCap = AppState.instance.progress.current.starterCashCap ?? 100.0;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 22),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Text('Redeem Score', style: AppTheme.display(22)),
        const SizedBox(height: 4),
        Text('From ${strOf(widget.game['title'], 'your game')}', style: AppTheme.body(13.5, color: AppColors.muted)),
        const SizedBox(height: 6),
        Text(redeemHint(widget.info, starterCap), style: AppTheme.body(12.5, color: AppColors.faint, height: 1.4)),
        const SizedBox(height: 16),
        _fieldLabel('How many to redeem'),
        const SizedBox(height: 8),
        _ScoreField(
          controller: _amount,
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: AppTheme.body(13, weight: FontWeight.w700, color: AppColors.danger, height: 1.35)),
        ],
        const SizedBox(height: 18),
        PrimaryButton(label: 'Send Request', gold: true, loading: _busy, onPressed: _submit),
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: Text('Cancel', style: AppTheme.body(14, weight: FontWeight.w700, color: AppColors.muted)),
        ),
      ]),
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────
// Transfer Score
// ───────────────────────────────────────────────────────────────────────────

class _TransferSheet extends StatefulWidget {
  const _TransferSheet({required this.game, required this.info});
  final Map<String, dynamic> game;
  final Map<String, dynamic> info;
  @override
  State<_TransferSheet> createState() => _TransferSheetState();
}

class _TransferSheetState extends State<_TransferSheet> {
  final _amount = TextEditingController();
  List<Map<String, dynamic>>? _targets; // null while loading
  String? _toSlug;
  String? _error;
  bool _busy = false;

  String get _slug => strOf(widget.game['slug']);

  @override
  void initState() {
    super.initState();
    _loadTargets();
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  /// The player's other games with a ready account: the only places score can move to.
  Future<void> _loadTargets() async {
    try {
      final d = await ApiClient.instance.get('/api/game-accounts');
      if (!mounted) return;
      final list = listOf(d['accounts']).where((a) => strOf(a['status']) == 'ready' && strOf(a['game_slug']).isNotEmpty && strOf(a['game_slug']) != _slug).toList()
        ..sort((a, b) => strOf(a['game_title']).toLowerCase().compareTo(strOf(b['game_title']).toLowerCase()));
      setState(() {
        _targets = list;
        if (list.length == 1) _toSlug = strOf(list.first['game_slug']);
      });
    } catch (_) {
      if (mounted) setState(() => _targets = const []);
    }
  }

  Future<void> _submit() async {
    if (_busy) return;
    final to = _toSlug;
    if (to == null) {
      setState(() => _error = 'Choose the game to transfer into.');
      return;
    }
    final amount = _parseScore(_amount.text);
    if (amount <= 0) {
      setState(() => _error = 'Enter a score greater than 0.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ApiClient.instance.post('/api/game-accounts/transfer', {'fromGameSlug': _slug, 'toGameSlug': to, 'amount': amount});
      if (!mounted) return;
      toast(context, 'Transfer requested.');
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Could not submit your transfer. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final targets = _targets;
    final none = targets != null && targets.isEmpty;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 22),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Text('Transfer Score', style: AppTheme.display(22)),
        const SizedBox(height: 4),
        Text('From ${strOf(widget.game['title'], 'your game')}', style: AppTheme.body(13.5, color: AppColors.muted)),
        const SizedBox(height: 6),
        Text(transferHint(widget.info), style: AppTheme.body(12.5, color: AppColors.faint, height: 1.4)),
        const SizedBox(height: 16),
        _fieldLabel('How many to transfer'),
        const SizedBox(height: 8),
        _ScoreField(
          controller: _amount,
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
        ),
        const SizedBox(height: 16),
        _fieldLabel('Transfer to game'),
        const SizedBox(height: 8),
        if (targets == null)
          const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4))))
        else if (none)
          Text(kNoTransferTarget, style: AppTheme.body(13, color: AppColors.muted, height: 1.4))
        else
          DropdownButtonFormField<String>(
            value: _toSlug,
            isExpanded: true,
            dropdownColor: AppColors.surface2,
            decoration: const InputDecoration(hintText: 'Choose a game'),
            items: [
              for (final t in targets)
                DropdownMenuItem<String>(
                  value: strOf(t['game_slug']),
                  child: Text(strOf(t['game_title'], strOf(t['game_slug'])), style: AppTheme.body(14.5, weight: FontWeight.w700), overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: _busy
                ? null
                : (v) => setState(() {
                      _toSlug = v;
                      _error = null;
                    }),
          ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: AppTheme.body(13, weight: FontWeight.w700, color: AppColors.danger, height: 1.35)),
        ],
        const SizedBox(height: 18),
        PrimaryButton(label: 'Transfer', loading: _busy, onPressed: none || targets == null ? null : _submit),
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: Text('Cancel', style: AppTheme.body(14, weight: FontWeight.w700, color: AppColors.muted)),
        ),
      ]),
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────
// Game History
// ───────────────────────────────────────────────────────────────────────────

class _HistorySheet extends StatefulWidget {
  const _HistorySheet({required this.slug, required this.title});
  final String slug;
  final String title;
  @override
  State<_HistorySheet> createState() => _HistorySheetState();
}

class _HistorySheetState extends State<_HistorySheet> {
  static const _ranges = [(label: 'Today', days: 0), (label: '7 days', days: 7), (label: '30 days', days: 30), (label: '12 months', days: 365)];

  int _range = 0;
  bool _showRedeems = false;
  Map<String, dynamic>? _data;
  String? _error;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _data = null;
      _error = null;
    });
    try {
      final now = DateTime.now();
      final from = DateTime(now.year, now.month, now.day).subtract(Duration(days: _ranges[_range].days));
      final to = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
      final d = await ApiClient.instance.get('/api/game-accounts/history', query: {
        'game': widget.slug,
        'from': from.toUtc().toIso8601String(),
        'to': to.toUtc().toIso8601String(),
      });
      if (mounted && request == _request) setState(() => _data = d);
    } on ApiException catch (e) {
      if (mounted && request == _request) setState(() => _error = e.message);
    } catch (_) {
      if (mounted && request == _request) setState(() => _error = 'Could not load your game history. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final rows = data == null ? const <Map<String, dynamic>>[] : listOf(data[_showRedeems ? 'redeems' : 'adds']);
    final more = data != null && data[_showRedeems ? 'redeemsHasMore' : 'addsHasMore'] == true;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.82),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 8, 6),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Game History', style: AppTheme.display(20)),
                Text(widget.title, style: AppTheme.body(12.5, color: AppColors.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
              ]),
            ),
            IconButton(tooltip: 'Close', icon: const Icon(Icons.close_rounded, color: AppColors.muted), onPressed: () => Navigator.of(context).maybePop()),
          ]),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(children: [
            for (var i = 0; i < _ranges.length; i++)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _Chip(
                  label: _ranges[i].label,
                  selected: i == _range,
                  onTap: () {
                    if (i == _range) return;
                    _range = i;
                    _load();
                  },
                ),
              ),
          ]),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(children: [
            Expanded(
              child: _TotalBox(
                label: 'Score added',
                value: data == null ? '—' : _scoreText(numOf(data['addTotal'])),
                selected: !_showRedeems,
                onTap: () => setState(() => _showRedeems = false),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _TotalBox(
                label: 'Redeemed & transferred',
                value: data == null ? '—' : _scoreText(numOf(data['redeemTotal'])),
                selected: _showRedeems,
                onTap: () => setState(() => _showRedeems = true),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        Flexible(
          child: _error != null
              ? ErrorRetry(message: _error!, onRetry: _load)
              : data == null
                  ? const Padding(padding: EdgeInsets.all(36), child: Center(child: CircularProgressIndicator()))
                  : rows.isEmpty
                      ? SingleChildScrollView(
                          child: EmptyState(
                            icon: Icons.history_rounded,
                            title: _showRedeems ? 'No redeems or transfers in this period' : 'No score added in this period',
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(18, 0, 18, 22),
                          itemCount: rows.length + (more ? 1 : 0),
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (_, i) {
                            if (i >= rows.length) {
                              return Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text('Showing the latest entries. Choose a shorter period to see the rest.', style: AppTheme.body(12, color: AppColors.faint), textAlign: TextAlign.center),
                              );
                            }
                            return _HistoryRow(row: rows[i]);
                          },
                        ),
        ),
      ]),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.row});
  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final outcome = requestOutcome(row['status']);
    final color = outcome == 'done' ? AppColors.mint : (outcome == 'rejected' ? AppColors.danger : AppColors.gold);
    final kind = strOf(row['kind']);
    final icon = kind == 'add' ? Icons.add_rounded : (kind == 'transfer' ? Icons.swap_horiz_rounded : Icons.card_giftcard_rounded);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
      decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.stroke)),
      child: Row(children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.14), shape: BoxShape.circle),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(strOf(row['label'], 'Request'), style: AppTheme.body(13.5, weight: FontWeight.w800), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text('${shortDateTime(row['created_at'])} · ${statusLabel(strOf(row['status']))}', style: AppTheme.body(11.5, color: AppColors.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
        const SizedBox(width: 8),
        Text(_scoreText(numOf(row['amount'])), style: AppTheme.display(15, color: color)),
      ]),
    );
  }
}

class _TotalBox extends StatelessWidget {
  const _TotalBox({required this.label, required this.value, required this.selected, required this.onTap});
  final String label;
  final String value;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: selected ? AppColors.gold : AppColors.stroke)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: AppTheme.body(11.5, color: selected ? AppColors.gold : AppColors.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 3),
            Text(value, style: AppTheme.display(17, color: selected ? AppColors.gold : AppColors.text), maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap});
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

// ───────────────────────────────────────────────────────────────────────────
// Small parts
// ───────────────────────────────────────────────────────────────────────────

/// A login value with its copy button (and show / hide when it is a password).
class _CopyRow extends StatefulWidget {
  const _CopyRow({required this.label, required this.value, required this.onCopy, this.secret = false});
  final String label;
  final String value;
  final VoidCallback onCopy;
  final bool secret;
  @override
  State<_CopyRow> createState() => _CopyRowState();
}

class _CopyRowState extends State<_CopyRow> {
  late bool _hidden = widget.secret;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
      decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.stroke)),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.label, style: AppTheme.body(11, weight: FontWeight.w700, color: AppColors.muted)),
            const SizedBox(height: 2),
            Text(
              widget.value.isEmpty ? '—' : (_hidden ? '••••••••' : widget.value),
              style: AppTheme.body(15, weight: FontWeight.w800),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ]),
        ),
        if (widget.secret)
          IconButton(
            tooltip: _hidden ? 'Show password' : 'Hide password',
            visualDensity: VisualDensity.compact,
            icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 19, color: AppColors.muted),
            onPressed: () => setState(() => _hidden = !_hidden),
          ),
        IconButton(
          tooltip: 'Copy',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.copy_rounded, size: 18, color: AppColors.gold),
          onPressed: widget.value.isEmpty ? null : widget.onCopy,
        ),
      ]),
    );
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
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 6),
        radius: 18,
        border: color.withValues(alpha: 0.4),
        child: Column(children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 6),
          FittedBox(fit: BoxFit.scaleDown, child: Text(label, style: AppTheme.body(13, weight: FontWeight.w800), maxLines: 1)),
        ]),
      ),
    );
  }
}

class _PlatformChip extends StatelessWidget {
  const _PlatformChip({required this.icon, required this.label, required this.color, required this.onTap});
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.1),
      shape: StadiumBorder(side: BorderSide(color: color.withValues(alpha: 0.6))),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 17, color: color),
            const SizedBox(width: 7),
            Text(label, style: AppTheme.body(13.5, weight: FontWeight.w800, color: color)),
          ]),
        ),
      ),
    );
  }
}
