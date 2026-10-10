import '../../core/api.dart';

// Wording and input rules of the website's game-account windows (Create Account, Buy Score,
// Redeem Score, Transfer Score). The server enforces every rule; this file only mirrors what the
// player reads and catches obvious mistakes before a request is sent.

/// Manual account: 3–24 letters, numbers, dots, - or _ (lib/game-accounts.ts isValidManualUsername).
bool isValidGameUsername(String value) => RegExp(r'^[a-zA-Z0-9._-]{3,24}$').hasMatch(value);

/// Manual account: any non-empty password up to 64 characters (isValidManualPassword).
bool isValidGamePassword(String value) {
  final v = value.trim();
  return v.isNotEmpty && v.length <= 64;
}

const String kUsernameRule = 'Username must be 3–24 letters, numbers, dots, - or _.';

/// The note under the wallet choice, exactly as on the website's Buy Score window.
({String title, String text}) walletNote(String wallet) => wallet == 'bonus'
    ? (title: 'Bonus Wallet score:', text: 'You can get 10% of your winnings in your Current Wallet when you redeem. The rest goes to your XP.')
    : (title: 'Current Wallet score:', text: 'You can claim your winnings according to your XP level. Level up to claim more when you redeem.');

String walletName(String wallet) => wallet == 'bonus' ? 'Bonus Wallet' : 'Current Wallet';

String _whole(double v) => v.isFinite ? v.toStringAsFixed(0) : '0';

/// The line under "Redeem Score". [info] is the answer of GET /api/game-accounts/redeem;
/// [starterCap] is the cash cap of the player's level (Bronze 100, Silver 150).
String redeemHint(Map<String, dynamic> info, double starterCap) {
  if (info['starter'] == true) {
    final cap = _whole(starterCap);
    return 'No redeem limit. At your level you receive 80% of a redeem up to $cap, or $cap for anything above that. The rest goes to your XP.';
  }
  return 'Level cap ${_whole(numOf(info['dailyCap']))} / day · ${_whole(numOf(info['dailyRemaining']))} left today. Max 100 per request. Extra score converts to XP.';
}

/// The line under "Transfer Score". [info] is the answer of GET /api/game-accounts/transfer.
String transferHint(Map<String, dynamic> info) =>
    'Level cap ${_whole(numOf(info['dailyCap']))} / day · ${_whole(numOf(info['dailyRemaining']))} left today. Max 100 per request. Extra score converts to XP.';

const String kNoTransferTarget = 'Create an account on another game first. Only games with a ready account appear here.';

/// Why a score cannot be bought from [wallet] right now, or null when the balance covers it.
String? balanceProblem({required String wallet, required double amount, required double currentWallet, required double bonusWallet}) {
  final balance = wallet == 'bonus' ? bonusWallet : currentWallet;
  if (amount <= balance + 0.000001) return null;
  return wallet == 'bonus'
      ? 'Your Bonus Wallet does not have enough balance for this score.'
      : 'Your Current Wallet does not have enough balance. Deposit first, then try again.';
}

/// Lines shown one after another on the wait screens (same as the website).
const List<String> kCreateLines = [
  'Creating your game account…',
  'Adding score to your vault…',
  'Locking in username & password…',
  'Almost there — stay on this page…',
];
const List<String> kBuyLines = ['Sending your add-score request…', 'Waiting for admin to add score…', 'Almost there — stay on this page…'];
const List<String> kRedeemLines = ['Redeeming your game score…', 'Moving score into your wallet…', 'Almost there — stay on this page…'];
const List<String> kTransferLines = ['Moving score to your other game…', 'Balancing both game vaults…', 'Almost there — stay on this page…'];

/// "done" for an approved request, "rejected" for a declined one, "pending" otherwise.
String requestOutcome(Object? status) {
  final s = strOf(status).toLowerCase();
  if (s == 'ready' || s == 'approved' || s == 'done') return 'done';
  if (s == 'rejected' || s == 'declined' || s == 'cancelled') return 'rejected';
  return 'pending';
}
