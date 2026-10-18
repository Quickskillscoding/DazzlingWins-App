import '../../core/api.dart';

// X Rule — the second level rule a player chooses once after sign-up (the XP rule is untouched).
// Same numbers as the website (lib/x-rule.ts) and the database (docs/supabase-x-rule.sql), which
// enforces them; this file only explains them on screen.
//
//  LEVEL: approved deposits + winnings above the cap. Level 0 (starter, below $1,000),
//         1 at $1,000, 2 at $2,000, 3 at $3,000, 4 at $4,000, 5 at $5,000.
//  REDEEM (Current Wallet play), from the LAST approved deposit D: at least 3x D; up to
//         (5 + level)x D goes to the Current Wallet, the rest raises the X Rule level.

const int kXRuleMinMultiple = 3;
const int kXRuleTopLevel = 5;
const List<double> kXRuleThresholds = [0, 1000, 2000, 3000, 4000, 5000];

int xRuleLevel(double progress) {
  var level = 0;
  for (var i = 0; i < kXRuleThresholds.length; i++) {
    if (progress >= kXRuleThresholds[i]) level = i;
  }
  return level;
}

int xRuleMaxMultiple(int level) => 5 + level.clamp(0, kXRuleTopLevel);

double? xRuleNextThreshold(int level) => level >= kXRuleTopLevel ? null : kXRuleThresholds[level.clamp(0, kXRuleTopLevel - 1) + 1];

double _r2(double v) => (v * 100).roundToDouble() / 100;

/// Cash to the Current Wallet and the part that raises the X Rule level, for a redeem of [amount].
({double min, double max, double cash, double points}) xRuleClaim(double deposit, int level, double amount) {
  final d = deposit < 0 ? 0.0 : deposit;
  final total = _r2(amount < 0 ? 0 : amount);
  final min = _r2(d * kXRuleMinMultiple);
  final max = _r2(d * xRuleMaxMultiple(level));
  final cash = _r2(total < max ? total : max);
  return (min: min, max: max, cash: cash, points: _r2(total - cash));
}

String _money(double v) => '\$${v.toStringAsFixed(2)}';

/// One line per level for the rule-choice popup.
List<String> xRuleLevelLines() => [
      for (var level = 0; level <= kXRuleTopLevel; level++)
        level == 0
            ? 'Level 0 (starter): claim ${kXRuleMinMultiple}x–${xRuleMaxMultiple(0)}x your deposit'
            : 'Level $level at \$${kXRuleThresholds[level].toStringAsFixed(0)} deposited: claim ${kXRuleMinMultiple}x–${xRuleMaxMultiple(level)}x',
    ];

const String kXRuleSummary =
    'Your level grows with your deposits. When you redeem, you claim 3x up to 5x–10x (by level) of your last deposit into your Current Wallet; the rest raises your X Rule level.';
const String kXpRuleSummary =
    'The classic XP levels. Your redeem limits follow your XP level, and score above your limit becomes XP that levels you up.';

/// The player's X Rule standing as the website sends it (`xRule` in /api/profile and
/// /api/game-accounts/redeem). Null when the player is on the XP rule.
class XRuleStatus {
  XRuleStatus({required this.level, required this.progress, required this.lastDeposit, required this.minClaim, required this.maxClaim, required this.maxMultiple, this.hint});

  final int level;
  final double progress;
  final double lastDeposit;
  final double minClaim;
  final double maxClaim;
  final int maxMultiple;
  final String? hint;

  static XRuleStatus? from(Object? raw) {
    if (raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw);
    if (m['rule'] != 'x') return null;
    final progress = numOf(m['progress']);
    final level = m['level'] is num ? (m['level'] as num).toInt() : xRuleLevel(progress);
    final dep = numOf(m['lastDeposit']);
    return XRuleStatus(
      level: level,
      progress: progress,
      lastDeposit: dep,
      minClaim: m['minClaim'] is num ? numOf(m['minClaim']) : _r2(dep * kXRuleMinMultiple),
      maxClaim: m['maxClaim'] is num ? numOf(m['maxClaim']) : _r2(dep * xRuleMaxMultiple(level)),
      maxMultiple: m['maxMultiple'] is num ? (m['maxMultiple'] as num).toInt() : xRuleMaxMultiple(level),
      hint: m['hint'] is String ? m['hint'] as String : null,
    );
  }

  /// The redeem window line (same wording as the website).
  String get redeemHint {
    if (hint != null && hint!.isNotEmpty) return hint!;
    if (lastDeposit <= 0) {
      return 'X Rule Level $level: make a deposit first. You can redeem ${kXRuleMinMultiple}x–${maxMultiple}x of your last deposit.';
    }
    return 'X Rule Level $level: redeem at least ${_money(minClaim)} (${kXRuleMinMultiple}x your last ${_money(lastDeposit)} deposit). Up to ${_money(maxClaim)} (${maxMultiple}x) goes to your Current Wallet; the rest raises your X Rule level.';
  }
}
