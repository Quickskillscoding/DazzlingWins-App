import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';
import '../games/game_sheet.dart';
import '../games/games_repo.dart';

/// A game the player can redeem from: an approved game account and the score on file for it.
class RedeemGame {
  const RedeemGame({required this.slug, required this.title, required this.score});

  factory RedeemGame.fromAccount(Map<String, dynamic> a) => RedeemGame(
        slug: strOf(a['game_slug']),
        title: strOf(a['game_title'], 'Game'),
        score: numOf(a['current_score']) + numOf(a['bonus_score']),
      );

  final String slug;
  final String title;

  /// Score on file (Current Wallet score + Bonus Wallet score), as the website shows it.
  final double score;
}

/// Approved game accounts only (a pending account has nothing to redeem), by title.
List<RedeemGame> redeemGamesFrom(Map<String, dynamic> answer) {
  final list = listOf(answer['accounts'])
      .where((a) => strOf(a['status']) == 'ready' && strOf(a['game_slug']).isNotEmpty)
      .map(RedeemGame.fromAccount)
      .toList();
  list.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  return list;
}

/// How redeeming works. The level names and cash caps come from the XP table the admin edits,
/// so this text follows a change made in the back office.
List<String> redeemRules(List<XpLevel> levels) {
  final starters = levels.where((l) => l.starterCashCap != null).toList()..sort((a, b) => a.level.compareTo(b.level));
  final caps = starters.map((l) => '${money(l.starterCashCap!).replaceAll('.00', '')} at ${l.name}').join(', ');
  return [
    'Redeem takes score out of a game. Our team checks it, and once approved the cash is added to your Current Wallet.',
    'If a redeem for a game is still waiting for approval, wait for it before sending another for that game.',
    if (starters.isNotEmpty)
      'At ${starters.map((l) => l.name).join(' and ')} level you receive 80% of a redeem in cash up to the cap of your level, '
          'or the cap itself for anything above it ($caps). The rest goes to your XP.',
    'At higher levels an approved redeem is paid in full, up to the daily redeem limit of your level. Anything above the limit goes to XP.',
    'Score added from the Bonus Wallet pays 10% to your Current Wallet; the rest goes to XP.',
    'To take money out of your Current Wallet, use Withdraw.',
  ];
}

/// Redeem: pick one of your games and redeem its score. Every rule (pending check, daily cap,
/// level split, bonus-score share) is the website's own, applied by the server on the same
/// endpoint the game page uses.
class RedeemScreen extends StatefulWidget {
  const RedeemScreen({super.key});
  @override
  State<RedeemScreen> createState() => _RedeemScreenState();
}

class _RedeemScreenState extends State<RedeemScreen> {
  List<RedeemGame>? _games;
  Map<String, Map<String, dynamic>> _catalog = const {};
  String? _error;
  String? _opening; // slug whose redeem window is being prepared
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool quiet = false}) async {
    if (_loading) return;
    _loading = true;
    try {
      final catalog = await GamesRepo.instance.load().catchError((_) => <Map<String, dynamic>>[]);
      final answer = await ApiClient.instance.get('/api/game-accounts');
      if (!mounted) return;
      setState(() {
        _games = redeemGamesFrom(answer);
        _catalog = {for (final g in catalog) strOf(g['slug']): g};
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted && (!quiet || _games == null)) setState(() => _error = e.message);
    } catch (_) {
      if (mounted && (!quiet || _games == null)) setState(() => _error = 'Could not load your games. Please try again.');
    } finally {
      _loading = false;
    }
  }

  Future<void> _redeem(RedeemGame game) async {
    if (_opening != null) return;
    HapticFeedback.selectionClick();
    setState(() => _opening = game.slug);
    try {
      // The server says whether a redeem is already waiting, and today's cap for this player.
      final info = await ApiClient.instance.get('/api/game-accounts/redeem', query: {'game': game.slug});
      if (!mounted) return;
      setState(() => _opening = null);
      final pending = mapOf(info['redeem']);
      if (strOf(pending['status']) == 'pending') {
        final amount = numOf(pending['requested_amount'] ?? pending['amount']);
        toast(context, 'A redeem of ${money(amount)} for ${game.title} is waiting for approval.', error: true);
        return;
      }
      final details = _catalog[game.slug] ?? <String, dynamic>{'slug': game.slug, 'title': game.title};
      final done = await showRedeemSheet(context, details, info);
      if (done && mounted) {
        unawaited(_load(quiet: true));
        unawaited(AppState.instance.refreshProfile().catchError((_) {}));
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _opening = null);
        toast(context, e.message, error: true);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _opening = null);
        toast(context, 'Could not open Redeem. Please try again.', error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final games = _games;
    return Scaffold(
      appBar: AppBar(title: const Text('Redeem')),
      body: AppBackground(
        child: games == null
            ? (_error != null ? Center(child: ErrorRetry(message: _error!, onRetry: _load)) : const Center(child: CircularProgressIndicator()))
            : RefreshIndicator(
                color: AppColors.gold,
                backgroundColor: AppColors.surface2,
                onRefresh: () => _load(quiet: true),
                child: ListView(
                  physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
                  children: [
                    Text('Choose the game you want to redeem score from.', style: AppTheme.body(13.5, color: AppColors.muted, height: 1.4)),
                    const SizedBox(height: 16),
                    if (games.isEmpty)
                      Panel(
                        child: Column(children: [
                          const EmptyState(
                            icon: Icons.savings_outlined,
                            title: 'Nothing to redeem yet',
                            subtitle: 'Redeem works on your approved game accounts. Create one from the Games tab first.',
                          ),
                          GhostButton(label: 'Back', icon: Icons.arrow_back_rounded, onPressed: () => Navigator.of(context).maybePop()),
                        ]),
                      )
                    else
                      for (final game in games)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _GameRow(
                            game: game,
                            thumbnail: strOf(_catalog[game.slug]?['thumbnail']),
                            opening: _opening == game.slug,
                            onTap: () => _redeem(game),
                          ),
                        ),
                    const SizedBox(height: 10),
                    const _RulesCard(),
                  ],
                ),
              ),
      ),
    );
  }
}

class _GameRow extends StatelessWidget {
  const _GameRow({required this.game, required this.thumbnail, required this.opening, required this.onTap});
  final RedeemGame game;
  final String thumbnail;
  final bool opening;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Panel(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
      child: Row(children: [
        SizedBox(
          width: 54,
          height: 54,
          child: thumbnail.isEmpty
              ? Container(
                  decoration: BoxDecoration(color: AppColors.surface3, borderRadius: BorderRadius.circular(14)),
                  child: const Icon(Icons.sports_esports_rounded, color: AppColors.muted),
                )
              : NetImage(thumbnail, radius: 14, cacheWidth: 150),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(game.title, style: AppTheme.display(16), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 3),
            Text('Score on file: ${money(game.score).replaceFirst('\$', '')}', style: AppTheme.body(12.5, color: AppColors.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(gradient: AppColors.goldGradient, borderRadius: BorderRadius.circular(99)),
          child: opening
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF1A1200)))
              : Text('Redeem', style: AppTheme.body(13, weight: FontWeight.w800, color: const Color(0xFF1A1200))),
        ),
      ]),
    );
  }
}

class _RulesCard extends StatelessWidget {
  const _RulesCard();

  @override
  Widget build(BuildContext context) {
    final rules = redeemRules(AppState.instance.levels);
    return Panel(
      border: AppColors.gold.withValues(alpha: 0.28),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.menu_book_rounded, color: AppColors.gold, size: 18),
          const SizedBox(width: 8),
          Text('How Redeem works', style: AppTheme.display(15, color: AppColors.gold)),
        ]),
        const SizedBox(height: 12),
        for (var i = 0; i < rules.length; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i == rules.length - 1 ? 0 : 9),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Container(width: 5, height: 5, decoration: const BoxDecoration(color: AppColors.gold, shape: BoxShape.circle)),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(rules[i], style: AppTheme.body(12.5, color: AppColors.muted, height: 1.4))),
            ]),
          ),
      ]),
    );
  }
}
