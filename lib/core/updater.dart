import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';
import '../widgets/ui.dart';
import 'theme.dart';

/// In-app updater. Asks the website (/api/app/version) for the newest published build; when it
/// is newer than this install, shows an update pop-up. The pop-up text is fixed in the app: it never
/// prints the release description (that is developer text, not something for players). "Update now" downloads the signed APK from
/// the official release; Android then installs it over this app (same signing key, data kept).
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
      // Only ever download from the official GitHub release over HTTPS.
      final trusted = apkUrl.startsWith('https://github.com/') || apkUrl.startsWith('https://objects.githubusercontent.com/');
      if (latest <= current || !trusted) {
        if (userInitiated && context.mounted) _snack(context, 'You have the latest version (${info.version}).');
        return;
      }
      if (!context.mounted) return;
      _shownThisSession = true;
      await _show(context, version: strOf(data['version']), apkUrl: apkUrl, force: current < minBuild);
    } catch (_) {
      if (userInitiated && context.mounted) _snack(context, 'Could not check for updates. Try again later.');
    }
  }

  static void _snack(BuildContext context, String text) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(text)));
  }

  static Future<void> _show(BuildContext context, {required String version, required String apkUrl, required bool force}) {
    return showAppPopup<void>(
      context,
      dismissible: !force,
      builder: (ctx) => PopScope(
        canPop: !force,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Center(
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(gradient: AppColors.goldGradient, borderRadius: BorderRadius.circular(20)),
                  child: const Icon(Icons.system_update_rounded, color: Color(0xFF1A1200), size: 32),
                ),
              ),
              const SizedBox(height: 16),
              Text(force ? 'Update required' : 'New version available', style: AppTheme.display(20), textAlign: TextAlign.center),
              const SizedBox(height: 6),
              Text('Version $version is ready with the latest features and fixes.',
                  style: AppTheme.body(14, color: AppColors.muted), textAlign: TextAlign.center),
              const SizedBox(height: 20),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.gold,
                  foregroundColor: const Color(0xFF1A1200),
                  minimumSize: const Size.fromHeight(54),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                ),
                icon: const Icon(Icons.download_rounded),
                label: Text('Update now', style: AppTheme.display(15, color: const Color(0xFF1A1200))),
                onPressed: () => launchUrl(Uri.parse(apkUrl), mode: LaunchMode.externalApplication),
              ),
              if (!force)
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text('Later', style: AppTheme.body(14, weight: FontWeight.w700, color: AppColors.muted)),
                ),
              const SizedBox(height: 4),
              Text('After the download, tap the file and choose “Update”. Your account stays signed in.',
                  style: AppTheme.body(12, color: AppColors.faint), textAlign: TextAlign.center),
            ]),
          ),
        ),
      ),
    );
  }
}
