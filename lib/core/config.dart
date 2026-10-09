/// App-wide constants. The app talks ONLY to the website's API over HTTPS; every rule (spins, KYC,
/// caps, XP, deposits, withdrawals) is enforced on the server exactly as on dazzlingwins.com.
class AppConfig {
  AppConfig._();

  /// Website / API origin. Must be HTTPS (Android also blocks cleartext traffic).
  static const String baseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'https://dazzlingwins.com');

  static const String appName = 'DazzlingWins';

  /// Requests that take longer than this fail with a friendly "connection" error.
  static const Duration requestTimeout = Duration(seconds: 25);

  /// Uploads (payment proof, KYC photos) get longer.
  static const Duration uploadTimeout = Duration(seconds: 90);

  /// How long the splash screen stays at least (it also waits for the session check).
  static const Duration splashMinimum = Duration(milliseconds: 2400);

  /// Max image size the server accepts for proofs / KYC (8 MB); the picker downsizes below it.
  static const int maxUploadBytes = 8 * 1024 * 1024;

  static Uri uri(String path, [Map<String, String>? query]) {
    final base = Uri.parse(baseUrl);
    return base.replace(path: path, queryParameters: query == null || query.isEmpty ? null : query);
  }

  /// Absolute URL for a site-relative asset path ("/Game Cards/Juwa.webp").
  static String asset(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    final clean = path.startsWith('/') ? path : '/$path';
    return Uri.parse(baseUrl).replace(path: clean).toString();
  }
}
