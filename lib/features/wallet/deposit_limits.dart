import '../../core/api.dart';

/// A payment method's minimum / maximum deposit, set by admins on the website (Deposit Methods).
/// null = no limit of that kind. The website refuses amounts outside them; the app shows them and
/// checks first so the player is told before uploading anything.
class DepositLimits {
  const DepositLimits({this.min, this.max});

  factory DepositLimits.of(Map<String, dynamic> method) =>
      DepositLimits(min: _limit(method['min_deposit']), max: _limit(method['max_deposit']));

  final double? min;
  final double? max;

  bool get any => min != null || max != null;

  static double? _limit(Object? v) {
    if (v == null) return null;
    final n = numOf(v, -1);
    if (!n.isFinite || n <= 0) return null;
    return (n * 100).round() / 100;
  }

  static String _dollars(double v) => v == v.roundToDouble() ? '\$${v.toStringAsFixed(0)}' : '\$${v.toStringAsFixed(2)}';

  /// "Min $10 · Max $500", "Min $10", "Max $500" or "" (same wording as the website).
  String get text => [
        if (min != null) 'Min ${_dollars(min!)}',
        if (max != null) 'Max ${_dollars(max!)}',
      ].join(' · ');

  /// Why `amount` is not allowed for this method, or null when it is.
  String? errorFor(double amount, String methodLabel) {
    if (min != null && amount < min!) return 'The minimum deposit with $methodLabel is ${_dollars(min!)}.';
    if (max != null && amount > max!) return 'The maximum deposit with $methodLabel is ${_dollars(max!)}.';
    return null;
  }
}
