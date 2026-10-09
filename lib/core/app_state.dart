
import 'package:flutter/foundation.dart';

import 'api.dart';

class XpLevel {
  XpLevel({
    required this.level,
    required this.name,
    required this.xpRequired,
    required this.maxRedeem,
    required this.maxTransfer,
    required this.bonusPoints,
    this.starterCashCap,
  });
  final int level;
  final String name;
  final double xpRequired;
  final double maxRedeem;
  final double maxTransfer;
  final double bonusPoints;
  final double? starterCashCap;

  factory XpLevel.fromJson(Map<String, dynamic> j) => XpLevel(
        level: numOf(j['level']).toInt(),
        name: strOf(j['name'], 'Level'),
        xpRequired: numOf(j['xpRequired']),
        maxRedeem: numOf(j['maxRedeem']),
        maxTransfer: numOf(j['maxTransfer']),
        bonusPoints: numOf(j['bonusPoints']),
        starterCashCap: j['starterCashCap'] == null ? null : numOf(j['starterCashCap']),
      );

  /// Built-in table (same defaults as the website) until /api/xp-levels answers.
  static final List<XpLevel> defaults = [
    XpLevel(level: 0, name: 'Bronze', xpRequired: 0, maxRedeem: 300, maxTransfer: 300, bonusPoints: 100, starterCashCap: 100),
    XpLevel(level: 1, name: 'Silver', xpRequired: 1000, maxRedeem: 300, maxTransfer: 300, bonusPoints: 200, starterCashCap: 150),
    XpLevel(level: 2, name: 'Gold', xpRequired: 5000, maxRedeem: 300, maxTransfer: 300, bonusPoints: 300),
    XpLevel(level: 3, name: 'Platinum', xpRequired: 10000, maxRedeem: 500, maxTransfer: 500, bonusPoints: 500),
    XpLevel(level: 4, name: 'Diamond', xpRequired: 15000, maxRedeem: 1000, maxTransfer: 1000, bonusPoints: 1000),
  ];
}

class XpProgress {
  XpProgress(this.current, this.next, this.ratio, this.remaining);
  final XpLevel current;
  final XpLevel? next;
  final double ratio;
  final double remaining;
}

/// Everything the tabs share. Server is the source of truth; this only caches the last answer.
class AppState extends ChangeNotifier {
  AppState._();
  static final AppState instance = AppState._();

  double currentWallet = 0;
  double bonusWallet = 0;
  int? freeSpinsLeft;
  String? lastFreeSpinAt;
  String? freeSpinCycleEndsAt;
  bool freeSpinUnlockedByDeposit = false;
  String? lastPaidSpinAt;
  bool walletLoaded = false;

  Map<String, dynamic> profile = {};
  bool profileLoaded = false;

  List<XpLevel> levels = XpLevel.defaults;

  double get xp => numOf(profile['xp']);
  String get displayName => strOf(profile['fullName'], 'Player');
  bool get kycVerified => profile['kycVerified'] == true;
  String get kycStatus => strOf(profile['kycStatus'], 'none');

  XpProgress get progress {
    final sorted = [...levels]..sort((a, b) => a.xpRequired.compareTo(b.xpRequired));
    var current = sorted.first;
    for (final l in sorted) {
      if (xp >= l.xpRequired) current = l;
    }
    final i = sorted.indexOf(current);
    final next = i + 1 < sorted.length ? sorted[i + 1] : null;
    if (next == null) return XpProgress(current, null, 1, 0);
    final span = next.xpRequired - current.xpRequired;
    if (span <= 0) return XpProgress(current, next, 1, 0);
    final into = (xp - current.xpRequired).clamp(0.0, span).toDouble();
    final ratio = into / span;
    final remaining = (next.xpRequired - xp).clamp(0.0, double.infinity).toDouble();
    return XpProgress(current, next, ratio, remaining);
  }

  Future<void> refreshWallet() async {
    final d = await ApiClient.instance.get('/api/wallet');
    currentWallet = numOf(d['currentWallet']);
    bonusWallet = numOf(d['bonusWallet']);
    freeSpinsLeft = d['freeSpinsLeft'] is num ? (d['freeSpinsLeft'] as num).toInt() : null;
    lastFreeSpinAt = d['lastFreeSpinAt'] as String?;
    freeSpinCycleEndsAt = d['freeSpinCycleEndsAt'] as String?;
    freeSpinUnlockedByDeposit = d['freeSpinUnlockedByDeposit'] == true;
    lastPaidSpinAt = d['lastPaidSpinAt'] as String?;
    walletLoaded = true;
    notifyListeners();
  }

  void applyWallet(Map<String, dynamic> d) {
    if (d['currentWallet'] is num) currentWallet = numOf(d['currentWallet']);
    if (d['bonusWallet'] is num) bonusWallet = numOf(d['bonusWallet']);
    if (d.containsKey('freeSpinsLeft')) {
      freeSpinsLeft = d['freeSpinsLeft'] is num ? (d['freeSpinsLeft'] as num).toInt() : freeSpinsLeft;
    }
    if (d['lastFreeSpinAt'] is String) lastFreeSpinAt = d['lastFreeSpinAt'] as String;
    if (d['freeSpinCycleEndsAt'] is String) freeSpinCycleEndsAt = d['freeSpinCycleEndsAt'] as String;
    if (d['lastPaidSpinAt'] is String) lastPaidSpinAt = d['lastPaidSpinAt'] as String;
    notifyListeners();
  }

  Future<void> refreshProfile() async {
    profile = await ApiClient.instance.get('/api/profile');
    profileLoaded = true;
    notifyListeners();
  }

  Future<void> refreshLevels() async {
    try {
      final d = await ApiClient.instance.get('/api/xp-levels', auth: false);
      final list = listOf(d['levels']).map(XpLevel.fromJson).toList();
      if (list.length >= 2) {
        levels = list;
        notifyListeners();
      }
    } catch (_) {
      // keep the built-in table
    }
  }

  /// Loads everything the home screen needs; errors per part never block the others.
  Future<void> refreshAll() async {
    await Future.wait([
      refreshWallet().catchError((_) {}),
      refreshProfile().catchError((_) {}),
      refreshLevels(),
    ]);
  }

  void reset() {
    currentWallet = 0;
    bonusWallet = 0;
    freeSpinsLeft = null;
    lastFreeSpinAt = null;
    freeSpinCycleEndsAt = null;
    freeSpinUnlockedByDeposit = false;
    lastPaidSpinAt = null;
    walletLoaded = false;
    profile = {};
    profileLoaded = false;
    notifyListeners();
  }
}
