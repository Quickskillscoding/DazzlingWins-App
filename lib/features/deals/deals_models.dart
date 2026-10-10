import '../../core/api.dart';

/// Dazzling Deals, exactly as the website serves them (GET /api/dazzling-deals). Admin edits the
/// offers in the back office; the app only shows what the server answers. Every rule (targets,
/// one claim per week / per level / per day, the lock on other offers) is enforced by the database.
class DealsSettings {
  const DealsSettings({
    required this.weeklyEnabled,
    required this.weeklyDepositTarget,
    required this.weeklyCashback,
    required this.weeklyTitle,
    required this.weeklyDescription,
    required this.weeklyCta,
    required this.loyaltyEnabled,
    required this.loyaltyBase,
    required this.loyaltyStep,
    required this.loyaltyTitle,
    required this.loyaltyDescription,
    required this.loyaltyCta,
  });

  /// Same defaults as the website (lib/dazzling-deals.ts), used only until the server answers.
  static const DealsSettings defaults = DealsSettings(
    weeklyEnabled: true,
    weeklyDepositTarget: 1000,
    weeklyCashback: 100,
    weeklyTitle: 'Exclusive Weekly Reward',
    weeklyDescription: 'Deposit a total of \$1000 this week and get \$100 cashback in your Bonus Wallet.',
    weeklyCta: 'Deposit Now',
    loyaltyEnabled: true,
    loyaltyBase: 50,
    loyaltyStep: 25,
    loyaltyTitle: 'Loyalty Bonus',
    loyaltyDescription: 'Level up with XP and claim a bigger Bonus Wallet reward at every level: \$50 at Level 1, then \$25 more each level.',
    loyaltyCta: 'Claim Bonus',
  );

  factory DealsSettings.fromJson(Map<String, dynamic> j) {
    const d = defaults;
    String text(Object? v, String fallback) {
      final s = strOf(v).trim();
      return s.isEmpty ? fallback : s;
    }

    double amount(Object? v, double fallback) {
      final n = numOf(v, fallback);
      return n.isFinite && n >= 0 ? n : fallback;
    }

    return DealsSettings(
      weeklyEnabled: j['weeklyEnabled'] is bool ? j['weeklyEnabled'] as bool : d.weeklyEnabled,
      weeklyDepositTarget: amount(j['weeklyDepositTarget'], d.weeklyDepositTarget),
      weeklyCashback: amount(j['weeklyCashback'], d.weeklyCashback),
      weeklyTitle: text(j['weeklyTitle'], d.weeklyTitle),
      weeklyDescription: text(j['weeklyDescription'], d.weeklyDescription),
      weeklyCta: text(j['weeklyCta'], d.weeklyCta),
      loyaltyEnabled: j['loyaltyEnabled'] is bool ? j['loyaltyEnabled'] as bool : d.loyaltyEnabled,
      loyaltyBase: amount(j['loyaltyBase'], d.loyaltyBase),
      loyaltyStep: amount(j['loyaltyStep'], d.loyaltyStep),
      loyaltyTitle: text(j['loyaltyTitle'], d.loyaltyTitle),
      loyaltyDescription: text(j['loyaltyDescription'], d.loyaltyDescription),
      loyaltyCta: text(j['loyaltyCta'], d.loyaltyCta),
    );
  }

  final bool weeklyEnabled;
  final double weeklyDepositTarget;
  final double weeklyCashback;
  final String weeklyTitle;
  final String weeklyDescription;
  final String weeklyCta;
  final bool loyaltyEnabled;
  final double loyaltyBase;
  final double loyaltyStep;
  final String loyaltyTitle;
  final String loyaltyDescription;
  final String loyaltyCta;

  /// Loyalty reward for reaching [level]: Level 1 = base, then +step for each level after.
  double loyaltyReward(int level) {
    if (level < 1) return 0;
    return ((loyaltyBase + loyaltyStep * (level - 1)) * 100).round() / 100;
  }

  /// Everything a player can see, as one string: a change means the admin edited the offers.
  String get signature =>
      '$weeklyEnabled|$weeklyDepositTarget|$weeklyCashback|$weeklyTitle|$weeklyDescription|$weeklyCta|'
      '$loyaltyEnabled|$loyaltyBase|$loyaltyStep|$loyaltyTitle|$loyaltyDescription|$loyaltyCta';
}

/// The signed-in player's progress (the website's dazzling_deals_status()).
class DealsStatus {
  const DealsStatus({
    required this.weekEnd,
    required this.weekDeposits,
    required this.weeklyClaimed,
    required this.xp,
    required this.level,
    required this.loyaltyClaimableLevel,
    required this.loyaltyClaimedToday,
    required this.lock,
  });

  static DealsStatus? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final j = Map<String, dynamic>.from(raw);
    final claimable = j['loyaltyClaimableLevel'] is num ? (j['loyaltyClaimableLevel'] as num).toInt() : 0;
    final lock = strOf(j['lock']);
    return DealsStatus(
      weekEnd: DateTime.tryParse(strOf(j['weekEnd'])),
      weekDeposits: numOf(j['weekDeposits']),
      weeklyClaimed: j['weeklyClaimed'] == true,
      xp: numOf(j['xp']),
      level: numOf(j['level']).toInt(),
      loyaltyClaimableLevel: claimable >= 1 ? claimable : null,
      loyaltyClaimedToday: j['loyaltyClaimedToday'] == true,
      lock: lock == 'weekly' || lock == 'loyalty' ? lock : null,
    );
  }

  /// End of the current week (next Monday 00:00 UTC).
  final DateTime? weekEnd;
  final double weekDeposits;
  final bool weeklyClaimed;
  final double xp;
  final int level;

  /// Lowest reached level whose bonus is not claimed yet (null = none).
  final int? loyaltyClaimableLevel;
  final bool loyaltyClaimedToday;

  /// Which deal currently pauses other offers: 'weekly', 'loyalty' or null.
  final String? lock;

  String get signature => '${weekEnd?.toIso8601String()}|$weekDeposits|$weeklyClaimed|$xp|$level|$loyaltyClaimableLevel|$loyaltyClaimedToday|$lock';
}

/// One answer of GET /api/dazzling-deals.
class DealsData {
  const DealsData({required this.settings, required this.ready, required this.status});

  factory DealsData.fromJson(Map<String, dynamic> j) => DealsData(
        settings: DealsSettings.fromJson(mapOf(j['settings'])),
        ready: j['ready'] == true,
        status: DealsStatus.fromJson(j['status']),
      );

  final DealsSettings settings;

  /// False until the offers are installed on the server (nothing can be claimed yet).
  final bool ready;
  final DealsStatus? status;

  String get signature => '$ready|${settings.signature}|${status?.signature}';
}

double weeklyRemaining(double deposits, double target) {
  final left = ((target - deposits) * 100).round() / 100;
  return left > 0 ? left : 0;
}

double weeklyProgress(double deposits, double target) {
  if (target <= 0) return 1;
  final ratio = deposits / target;
  return ratio < 0 ? 0 : (ratio > 1 ? 1 : ratio);
}

/// "$1,000" / "$12.50": whole dollars without cents, like the website's deal cards.
String dealMoney(double value) {
  final v = value.isFinite ? value : 0.0;
  final cents = (v.abs() * 100).round();
  final whole = (cents ~/ 100).toString();
  final buf = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) buf.write(',');
    buf.write(whole[i]);
  }
  final rest = cents % 100;
  final tail = rest == 0 ? '' : '.${rest.toString().padLeft(2, '0')}';
  return '${v < 0 ? '-' : ''}\$$buf$tail';
}

/// "3d 4h left this week" / "5h left this week" ('' when unknown).
String weekTimeLeft(DateTime? weekEnd, {DateTime? now}) {
  if (weekEnd == null) return '';
  final left = weekEnd.difference(now ?? DateTime.now());
  if (left.isNegative) return 'New week starting';
  final days = left.inDays;
  final hours = left.inHours - days * 24;
  return days > 0 ? '${days}d ${hours}h left this week' : '${hours}h left this week';
}

/// Shown when a claimed deal pauses the player's other offers (same words as the website).
String? dealLockMessage(String? lock) {
  if (lock == 'weekly') {
    return 'You claimed the Exclusive Weekly Reward this week, so other offers and promo codes open again next Monday.';
  }
  if (lock == 'loyalty') {
    return 'You claimed a Loyalty Bonus today, so other offers and promo codes open again tomorrow.';
  }
  return null;
}

/// How the app explains the deals (the website's "How Dazzling Deals work").
const List<String> kDealRules = [
  'Weekly deposits count from Monday 00:00 UTC to Sunday 23:59 UTC. Only approved deposits count.',
  'Rewards go to your Bonus Wallet the moment you claim them.',
  'Each level\'s Loyalty Bonus can be claimed once, one level per day.',
  'Claiming the Exclusive Weekly Reward pauses other offers and promo codes until next Monday. Claiming a Loyalty Bonus pauses them until tomorrow.',
];
