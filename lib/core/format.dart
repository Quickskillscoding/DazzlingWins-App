/// Money / date formatting identical in spirit to the website (2 decimals, US style).
String money(double v, {bool sign = false}) {
  final negative = v < 0;
  final abs = v.abs();
  final fixed = abs.toStringAsFixed(2);
  final parts = fixed.split('.');
  final whole = parts[0];
  final buf = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) buf.write(',');
    buf.write(whole[i]);
  }
  final prefix = negative ? '-' : (sign && v > 0 ? '+' : '');
  return '$prefix\$${buf.toString()}.${parts[1]}';
}

String compactInt(num v) {
  final n = v.round();
  final s = n.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return '${n < 0 ? '-' : ''}$buf';
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

DateTime? parseTime(Object? v) {
  if (v is num) return DateTime.fromMillisecondsSinceEpoch(v.toInt()).toLocal();
  if (v is String && v.isNotEmpty) return DateTime.tryParse(v)?.toLocal();
  return null;
}

String shortDateTime(Object? v) {
  final t = parseTime(v);
  if (t == null) return '';
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final m = t.minute.toString().padLeft(2, '0');
  return '${_months[t.month - 1]} ${t.day}, $h:$m ${t.hour < 12 ? 'AM' : 'PM'}';
}

String relativeTime(Object? v) {
  final t = parseTime(v);
  if (t == null) return '';
  final d = DateTime.now().difference(t);
  if (d.inSeconds < 60) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  if (d.inDays < 7) return '${d.inDays}d ago';
  return shortDateTime(v);
}

/// "approved"/"ready" → Approved, "rejected" → Rejected, else Pending (same as the website).
String statusLabel(Object? status) {
  final s = (status ?? '').toString().toLowerCase();
  if (s == 'approved' || s == 'ready') return 'Approved';
  if (s == 'rejected') return 'Rejected';
  if (s.isEmpty) return '';
  if (s == 'pending') return 'Pending';
  return s[0].toUpperCase() + s.substring(1);
}
