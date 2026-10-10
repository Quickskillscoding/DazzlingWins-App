import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/ui.dart';
import 'api.dart';
import 'theme.dart';

/// In-app updater. Asks the website (/api/app/version) for the newest published build; when it
/// is newer than this install, shows an update pop-up. "Update now" downloads the signed APK from
/// the official release INSIDE the app (no browser tab is opened), checks it, and hands it to
/// Android's installer, which installs it over this app (same signing key, data kept).
/// The pop-up text is fixed in the app: it never prints the release description.
/// Builds below the server's minBuild cannot dismiss the pop-up.
class Updater {
  Updater._();
  static bool _shownThisSession = false;

  static Future<void> check(BuildContext context, {bool userInitiated = false}) async {
    if (_shownThisSession && !userInitiated) return;
    try {
      final info = await PackageInfo.fromPlatform();
      final current = int.tryParse(info.buildNumber) ?? 0;
      final data = await ApiClient.instance.get('/api/app/version', auth: false);
      if (data['available'] != true) {
        if (userInitiated && context.mounted) _snack(context, 'You have the latest version.');
        return;
      }
      final latest = numOf(data['build']).toInt();
      final minBuild = numOf(data['minBuild']).toInt();
      final apkUrl = strOf(data['apkUrl']);
      if (latest <= current || !isTrustedApkUrl(apkUrl)) {
        if (userInitiated && context.mounted) _snack(context, 'You have the latest version (${info.version}).');
        return;
      }
      if (!context.mounted) return;
      _shownThisSession = true;
      final force = current < minBuild;
      await showAppPopup<void>(
        context,
        dismissible: !force,
        builder: (_) => _UpdateCard(version: strOf(data['version']), build: latest, apkUrl: apkUrl, force: force),
      );
    } catch (_) {
      if (userInitiated && context.mounted) _snack(context, 'Could not check for updates. Try again later.');
    }
  }

  static void _snack(BuildContext context, String text) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(text)));
  }
}

/// The app only ever downloads its update from the official GitHub release, over HTTPS.
bool isTrustedApkUrl(String url) {
  final uri = Uri.tryParse(url);
  return uri != null && uri.scheme == 'https' && uri.host == 'github.com' && uri.path.endsWith('.apk');
}

/// First token of a `sha256sum` line ("<64 hex>  file"), lower-case; null when it is not one.
String? parseSha256Line(String text) {
  final first = text.trim().split(RegExp(r'\s+')).first.toLowerCase();
  return RegExp(r'^[0-9a-f]{64}$').hasMatch(first) ? first : null;
}

enum _Stage { idle, downloading, ready, failed }

class _UpdateCard extends StatefulWidget {
  const _UpdateCard({required this.version, required this.build, required this.apkUrl, required this.force});
  final String version;
  final int build;
  final String apkUrl;
  final bool force;

  @override
  State<_UpdateCard> createState() => _UpdateCardState();
}

class _UpdateCardState extends State<_UpdateCard> {
  /// A real build is tens of megabytes; anything tiny is an error page, not the app.
  static const _minApkBytes = 5 * 1024 * 1024;

  _Stage _stage = _Stage.idle;
  double? _progress; // null = size unknown
  String _message = '';
  String _path = '';
  http.Client? _client;
  bool _cancelled = false;

  @override
  void dispose() {
    _cancelled = true;
    _client?.close();
    super.dispose();
  }

  Future<void> _download() async {
    if (_stage == _Stage.downloading) return;
    setState(() {
      _stage = _Stage.downloading;
      _progress = 0;
      _message = '';
    });
    final client = http.Client();
    _client = client;
    IOSink? sink;
    File? file;
    try {
      final dir = Directory.systemTemp;
      // Clear updates left over from earlier versions.
      try {
        await for (final entry in dir.list()) {
          if (entry is File && entry.path.contains('DazzlingWins-update-')) await entry.delete();
        }
      } catch (_) {}

      final target = File('${dir.path}/DazzlingWins-update-${widget.build}.apk');
      file = target;
      final response = await client.send(http.Request('GET', Uri.parse(widget.apkUrl))).timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) throw const _UpdateError('The download is not available right now. Please try again.');
      final total = response.contentLength ?? 0;
      var received = 0;
      var lastShown = -1;
      final out = target.openWrite();
      sink = out;
      await for (final chunk in response.stream.timeout(const Duration(seconds: 45))) {
        if (_cancelled) throw const _UpdateError('cancelled');
        out.add(chunk);
        received += chunk.length;
        if (total > 0) {
          final percent = (received * 100) ~/ total;
          if (percent != lastShown && mounted) {
            lastShown = percent;
            final ratio = received / total;
            setState(() => _progress = ratio > 1 ? 1 : ratio);
          }
        } else if (mounted && _progress != null) {
          setState(() => _progress = null);
        }
      }
      await out.flush();
      await out.close();
      sink = null;

      if (received < _minApkBytes) throw const _UpdateError('The download did not finish. Please try again.');

      // Compare with the checksum published next to the APK. A mismatch means a damaged download.
      final expected = await _publishedChecksum(client);
      if (expected != null) {
        final actual = (await sha256.bind(target.openRead()).first).toString();
        if (actual != expected) throw const _UpdateError('The download was damaged. Please try again.');
      }

      if (!mounted) return;
      setState(() {
        _stage = _Stage.ready;
        _path = target.path;
        _progress = 1;
      });
      await _install();
    } on _UpdateError catch (e) {
      await _cleanup(sink, file);
      if (mounted && e.message != 'cancelled') _fail(e.message);
    } on TimeoutException {
      await _cleanup(sink, file);
      if (mounted) _fail('The connection is slow. Please try again.');
    } catch (_) {
      await _cleanup(sink, file);
      if (mounted) _fail('The download failed. Check your connection and try again.');
    } finally {
      client.close();
      if (identical(_client, client)) _client = null;
    }
  }

  Future<String?> _publishedChecksum(http.Client client) async {
    try {
      final res = await client.get(Uri.parse('${widget.apkUrl}.sha256')).timeout(const Duration(seconds: 15));
      return res.statusCode == 200 ? parseSha256Line(res.body) : null;
    } catch (_) {
      return null; // Android still verifies the app's signature before installing.
    }
  }

  Future<void> _cleanup(IOSink? sink, File? file) async {
    try {
      await sink?.close();
    } catch (_) {}
    try {
      if (file != null && await file.exists()) await file.delete();
    } catch (_) {}
  }

  void _fail(String message) {
    setState(() {
      _stage = _Stage.failed;
      _message = message;
    });
  }

  /// Hands the downloaded file to Android's installer.
  Future<void> _install() async {
    if (_path.isEmpty) return;
    try {
      final result = await OpenFilex.open(_path, type: 'application/vnd.android.package-archive');
      if (!mounted) return;
      if (result.type == ResultType.permissionDenied) {
        setState(() => _message = 'Allow DazzlingWins to install updates, then tap Install again.');
      } else if (result.type != ResultType.done) {
        setState(() => _message = 'Could not open the installer. Tap Install to try again.');
      } else if (_message.isNotEmpty) {
        setState(() => _message = '');
      }
    } catch (_) {
      if (mounted) setState(() => _message = 'Could not open the installer. Tap Install to try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final force = widget.force;
    final downloading = _stage == _Stage.downloading;
    final ready = _stage == _Stage.ready;
    final progress = _progress;
    final percent = progress == null ? null : (progress * 100).round();

    return PopScope(
      // No leaving half-way through a required update or a running download.
      canPop: !force && !downloading,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 22),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(gradient: AppColors.goldGradient, borderRadius: BorderRadius.circular(20)),
              child: Icon(ready ? Icons.verified_rounded : Icons.system_update_rounded, color: const Color(0xFF1A1200), size: 32),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            ready ? 'Update downloaded' : (downloading ? 'Downloading update' : (force ? 'Update required' : 'New version available')),
            style: AppTheme.display(20),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            ready
                ? 'Tap Install, then choose “Update”. Your account stays signed in.'
                : 'Version ${widget.version} is ready with the latest features and fixes.',
            style: AppTheme.body(14, color: AppColors.muted, height: 1.35),
            textAlign: TextAlign.center,
          ),
          if (downloading) ...[
            const SizedBox(height: 20),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 10,
                backgroundColor: AppColors.surface3,
                valueColor: const AlwaysStoppedAnimation<Color>(AppColors.gold),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              percent == null ? 'Downloading…' : 'Downloading… $percent%',
              style: AppTheme.body(13, weight: FontWeight.w700, color: AppColors.gold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text('Keep the app open until it finishes.', style: AppTheme.body(12, color: AppColors.faint), textAlign: TextAlign.center),
          ],
          if (_message.isNotEmpty && !downloading) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
              ),
              child: Text(_message, style: AppTheme.body(13, weight: FontWeight.w600, color: AppColors.warning, height: 1.35), textAlign: TextAlign.center),
            ),
          ],
          if (!downloading) ...[
            const SizedBox(height: 20),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: const Color(0xFF1A1200),
                minimumSize: const Size.fromHeight(54),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              ),
              icon: Icon(ready ? Icons.install_mobile_rounded : Icons.download_rounded),
              label: Text(
                ready ? 'Install' : (_stage == _Stage.failed ? 'Try again' : 'Update now'),
                style: AppTheme.display(15, color: const Color(0xFF1A1200)),
              ),
              onPressed: ready ? _install : _download,
            ),
            if (_stage == _Stage.failed)
              TextButton(
                // Last resort when the in-app download keeps failing.
                onPressed: () => launchUrl(Uri.parse(widget.apkUrl), mode: LaunchMode.externalApplication),
                child: Text('Download in the browser instead', style: AppTheme.body(13, weight: FontWeight.w700, color: AppColors.primaryLight)),
              ),
            if (!force)
              TextButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: Text('Later', style: AppTheme.body(14, weight: FontWeight.w700, color: AppColors.muted)),
              ),
          ],
        ]),
      ),
    );
  }
}

class _UpdateError implements Exception {
  const _UpdateError(this.message);
  final String message;
}
