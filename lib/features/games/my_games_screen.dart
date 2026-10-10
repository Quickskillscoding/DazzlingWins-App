import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';
import 'game_sheet.dart';
import 'games_repo.dart';

/// One of the player's game accounts (a row of the website's /api/game-accounts).
class MyGameAccount {
  const MyGameAccount({
    required this.id,
    required this.slug,
    required this.title,
    required this.username,
    required this.password,
    required this.status,
  });

  factory MyGameAccount.fromJson(Map<String, dynamic> j) => MyGameAccount(
        id: strOf(j['id']),
        slug: strOf(j['game_slug']),
        title: strOf(j['game_title'], 'Game'),
        username: strOf(j['username']),
        password: strOf(j['password']),
        status: strOf(j['status'], 'pending'),
      );

  final String id;
  final String slug;
  final String title;
  final String username;
  final String password;

  /// "ready" = approved by staff (the login can be used), anything else = still pending.
  final String status;

  bool get approved => status == 'ready';

  /// Both lines, ready to paste (same text as the website's "Copy Username & Password").
  String get loginText => 'Username: $username\nPassword: $password';

  String get signature => '$id|$slug|$title|$username|$password|$status';
}

/// The list the website's My Games page shows: approved accounts first, then pending, by title.
List<MyGameAccount> myGameAccountsFrom(Map<String, dynamic> answer) {
  final list = listOf(answer['accounts']).map(MyGameAccount.fromJson).where((a) => a.slug.isNotEmpty).toList();
  list.sort((a, b) {
    if (a.approved != b.approved) return a.approved ? -1 : 1;
    return a.title.toLowerCase().compareTo(b.title.toLowerCase());
  });
  return list;
}

/// My Games: every game account the player created, with its username and password, so they can
/// copy the login and open the game. The same data as the website's My Games page; a login shows
/// only after staff approved the create-account request. Refreshes while the screen is open.
class MyGamesScreen extends StatefulWidget {
  const MyGamesScreen({super.key});
  @override
  State<MyGamesScreen> createState() => _MyGamesScreenState();
}

class _MyGamesScreenState extends State<MyGamesScreen> with WidgetsBindingObserver {
  static const _refreshEvery = Duration(seconds: 8);

  List<MyGameAccount>? _accounts;
  Map<String, Map<String, dynamic>> _games = const {};
  String? _error;
  String? _resetting; // game slug whose password is being reset
  bool _loading = false;
  bool _foreground = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _timer = Timer.periodic(_refreshEvery, (_) {
      if (_foreground && _resetting == null) _load(quiet: true);
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
      // Game card images and play links; the accounts still show if this part fails.
      final games = await GamesRepo.instance.load().catchError((_) => <Map<String, dynamic>>[]);
      final answer = await ApiClient.instance.get('/api/game-accounts');
      if (!mounted || _resetting != null) return;
      final accounts = myGameAccountsFrom(answer);
      final bySlug = {for (final g in games) strOf(g['slug']): g};
      final same = _accounts != null &&
          _accounts!.map((a) => a.signature).join('\n') == accounts.map((a) => a.signature).join('\n') &&
          _games.length == bySlug.length;
      if (!same || _error != null) {
        setState(() {
          _accounts = accounts;
          _games = bySlug;
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted && !quiet && _accounts == null) setState(() => _error = e.message);
    } catch (_) {
      if (mounted && !quiet && _accounts == null) setState(() => _error = 'Could not load your games. Please try again.');
    } finally {
      _loading = false;
    }
  }

  Future<void> _resetPassword(MyGameAccount account) async {
    if (_resetting != null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Reset this password?', style: AppTheme.display(18)),
        content: Text(
          'You get a new password for ${account.title}. The old one stops being shown here.',
          style: AppTheme.body(14, color: AppColors.muted),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reset password')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _resetting = account.slug);
    try {
      final d = await ApiClient.instance.patch('/api/game-accounts', {'gameSlug': account.slug});
      if (!mounted) return;
      final updated = d['account'] is Map ? MyGameAccount.fromJson(mapOf(d['account'])) : null;
      setState(() {
        _resetting = null;
        if (updated != null && _accounts != null) {
          _accounts = [for (final a in _accounts!) a.slug == updated.slug ? updated : a];
        }
      });
      toast(context, 'New password ready');
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _resetting = null);
        toast(context, e.message, error: true);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _resetting = null);
        toast(context, 'Could not reset this password. Please try again.', error: true);
      }
    }
    if (mounted) unawaited(_load(quiet: true));
  }

  Future<void> _open(String url) async {
    if (url.isEmpty) return;
    try {
      final opened = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!opened && mounted) toast(context, 'Could not open the game. Please try again.', error: true);
    } catch (_) {
      if (mounted) toast(context, 'Could not open the game. Please try again.', error: true);
    }
  }

  /// Copies the whole login, then opens the game: the player only has to paste.
  Future<void> _play(MyGameAccount account, String url) async {
    HapticFeedback.selectionClick();
    await Clipboard.setData(ClipboardData(text: account.loginText));
    if (mounted) toast(context, 'Username and password copied. Opening ${account.title}…');
    await _open(url);
  }

  Future<void> _details(MyGameAccount account) async {
    final game = _games[account.slug] ?? <String, dynamic>{'slug': account.slug, 'title': account.title};
    await showGameSheet(context, game);
    if (mounted) unawaited(_load(quiet: true));
  }

  @override
  Widget build(BuildContext context) {
    final accounts = _accounts;
    return Scaffold(
      appBar: AppBar(title: const Text('My Games')),
      body: AppBackground(
        child: accounts == null
            ? (_error != null ? Center(child: ErrorRetry(message: _error!, onRetry: _load)) : const Center(child: CircularProgressIndicator()))
            : RefreshIndicator(
                color: AppColors.gold,
                backgroundColor: AppColors.surface2,
                onRefresh: () => _load(quiet: true),
                child: ListView(
                  physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
                  children: [
                    Text(
                      'Game usernames and passwords appear here after your create-account request is approved.',
                      style: AppTheme.body(13.5, color: AppColors.muted, height: 1.4),
                    ),
                    const SizedBox(height: 16),
                    if (accounts.isEmpty)
                      Panel(
                        child: Column(children: [
                          const EmptyState(
                            icon: Icons.sports_esports_outlined,
                            title: 'No game accounts yet',
                            subtitle: 'Create an account from a game. After approval, the login shows here.',
                          ),
                          GhostButton(label: 'Browse all games', icon: Icons.grid_view_rounded, onPressed: () => Navigator.of(context).maybePop()),
                        ]),
                      )
                    else
                      for (final account in accounts)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: _AccountCard(
                            key: ValueKey('acct-${account.id}'),
                            account: account,
                            game: _games[account.slug],
                            resetting: _resetting == account.slug,
                            busy: _resetting != null,
                            onPlay: (url) => _play(account, url),
                            onGetApp: _open,
                            onReset: () => _resetPassword(account),
                            onDetails: () => _details(account),
                          ),
                        ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({
    super.key,
    required this.account,
    required this.game,
    required this.resetting,
    required this.busy,
    required this.onPlay,
    required this.onGetApp,
    required this.onReset,
    required this.onDetails,
  });
  final MyGameAccount account;

  /// The game's card image and links (null while the catalogue is unavailable).
  final Map<String, dynamic>? game;
  final bool resetting;
  final bool busy;
  final ValueChanged<String> onPlay;
  final ValueChanged<String> onGetApp;
  final VoidCallback onReset;
  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context) {
    final a = account;
    final webUrl = strOf(game?['webUrl']);
    final androidUrl = strOf(game?['androidUrl']);
    final thumbnail = strOf(game?['thumbnail']);
    final color = a.approved ? AppColors.mint : AppColors.gold;

    return Panel(
      padding: const EdgeInsets.all(14),
      border: a.approved ? AppColors.stroke : AppColors.gold.withValues(alpha: 0.35),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onDetails,
          child: Row(children: [
            SizedBox(
              width: 62,
              height: 62,
              child: thumbnail.isEmpty
                  ? Container(
                      decoration: BoxDecoration(color: AppColors.surface3, borderRadius: BorderRadius.circular(16)),
                      child: const Icon(Icons.sports_esports_rounded, color: AppColors.muted),
                    )
                  : NetImage(thumbnail, radius: 16, cacheWidth: 160),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(a.title, style: AppTheme.display(17), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(99)),
                  child: Text(a.approved ? 'APPROVED' : 'PENDING', style: AppTheme.body(10, weight: FontWeight.w800, color: color)),
                ),
              ]),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.faint),
          ]),
        ),
        const SizedBox(height: 14),
        if (!a.approved)
          Text(
            'Waiting for our team to mark this account Done. Your username and password will show here after approval.',
            style: AppTheme.body(13, weight: FontWeight.w600, color: AppColors.gold, height: 1.4),
          )
        else ...[
          _LoginField(label: 'Username', value: a.username),
          const SizedBox(height: 8),
          _LoginField(label: 'Password', value: a.password, secret: true),
          const SizedBox(height: 12),
          if (webUrl.isNotEmpty) ...[
            PrimaryButton(label: 'Copy login & play', icon: Icons.play_arrow_rounded, gold: true, onPressed: () => onPlay(webUrl)),
            const SizedBox(height: 10),
          ],
          Row(children: [
            Expanded(
              child: GhostButton(
                label: 'Copy login',
                icon: Icons.copy_all_rounded,
                onPressed: () {
                  HapticFeedback.selectionClick();
                  Clipboard.setData(ClipboardData(text: a.loginText));
                  toast(context, 'Username and password copied');
                },
              ),
            ),
            if (androidUrl.isNotEmpty) ...[
              const SizedBox(width: 10),
              Expanded(child: GhostButton(label: 'Get game app', icon: Icons.android_rounded, onPressed: () => onGetApp(androidUrl))),
            ],
          ]),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: busy ? null : onReset,
              icon: resetting
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.muted))
                  : const Icon(Icons.refresh_rounded, size: 17, color: AppColors.primaryLight),
              label: Text(
                resetting ? 'Resetting…' : 'Reset password',
                style: AppTheme.body(13, weight: FontWeight.w800, color: busy ? AppColors.faint : AppColors.primaryLight),
              ),
            ),
          ),
        ],
      ]),
    );
  }
}

/// A username / password box with a copy button (and show / hide for the password).
class _LoginField extends StatefulWidget {
  const _LoginField({required this.label, required this.value, this.secret = false});
  final String label;
  final String value;
  final bool secret;

  @override
  State<_LoginField> createState() => _LoginFieldState();
}

class _LoginFieldState extends State<_LoginField> {
  late bool _hidden = widget.secret;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.stroke),
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.label, style: AppTheme.body(11, color: AppColors.muted)),
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
          tooltip: 'Copy ${widget.label.toLowerCase()}',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.copy_rounded, size: 18, color: AppColors.gold),
          onPressed: widget.value.isEmpty
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  Clipboard.setData(ClipboardData(text: widget.value));
                  toast(context, '${widget.label} copied');
                },
        ),
      ]),
    );
  }
}
