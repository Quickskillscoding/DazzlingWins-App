import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/config.dart';
import '../../core/format.dart';
import '../../core/notification_inbox.dart';
import '../../core/notifications.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/updater.dart';
import '../../widgets/ui.dart';
import '../auth/auth_screen.dart';
import 'kyc_screen.dart';
import 'levels_sheet.dart';
import 'rewards_panel.dart';
import 'support_chat_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> with AutomaticKeepAliveClientMixin {
  final _rewards = GlobalKey<RewardsPanelState>();
  Map<String, dynamic> _referral = {};
  String _version = '';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadExtras();
  }

  Future<void> _loadExtras() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _version = '${info.version} (${info.buildNumber})');
    } catch (_) {}
    try {
      final r = await ApiClient.instance.get('/api/referrals');
      if (mounted) setState(() => _referral = r);
    } catch (_) {}
  }

  Future<void> _refresh() async {
    await Future.wait([
      AppState.instance.refreshAll(),
      _rewards.currentState?.reload() ?? Future<void>.value(),
      _loadExtras(),
    ]);
  }

  Future<void> _signOut() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Sign out?', style: AppTheme.display(18)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sign out')),
        ],
      ),
    );
    if (ok != true) return;
    // Record the logout on the server (Player History), then forget the tokens on this device.
    await ApiClient.instance.post('/api/auth/activity', {'type': 'logout'}).catchError((_) => <String, dynamic>{});
    await AppNotifications.clearOnSignOut();
    await Session.instance.clear();
    AppState.instance.reset();
    NotificationInbox.instance.reset();
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const AuthScreen()), (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return AppBackground(
      child: RefreshIndicator(
        color: AppColors.gold,
        onRefresh: _refresh,
        child: ListenableBuilder(
          listenable: AppState.instance,
          builder: (context, _) {
            final s = AppState.instance;
            final p = s.progress;
            return ListView(
              physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
              padding: EdgeInsets.fromLTRB(18, MediaQuery.of(context).padding.top + 14, 18, 130),
              children: [
                Row(children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: const BoxDecoration(gradient: AppColors.goldGradient, shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: Text(
                      s.displayName.isEmpty ? 'P' : s.displayName.substring(0, 1).toUpperCase(),
                      style: AppTheme.display(26, color: const Color(0xFF1A1200)),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(s.displayName, style: AppTheme.display(20), maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text(strOf(s.profile['email'], Session.instance.email ?? ''), style: AppTheme.body(13, color: AppColors.muted)),
                      const SizedBox(height: 6),
                      StatusChip(s.kycVerified ? 'Verified' : (s.kycStatus == 'pending' ? 'Pending' : 'Unverified')),
                    ]),
                  ),
                ]),
                const SizedBox(height: 18),
                Panel(
                  onTap: () => showLevelsSheet(context),
                  gradient: AppColors.heroGradient,
                  child: Row(children: [
                    const Icon(Icons.workspace_premium_rounded, color: AppColors.gold, size: 30),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${p.current.name} · ${compactInt(s.xp)} XP', style: AppTheme.display(16)),
                        Text(p.next == null ? 'Top level reached' : '${compactInt(p.remaining)} XP to ${p.next!.name}',
                            style: AppTheme.body(12, color: AppColors.muted)),
                      ]),
                    ),
                    Text('Perks', style: AppTheme.body(13, weight: FontWeight.w800, color: AppColors.primaryLight)),
                    const Icon(Icons.chevron_right_rounded, color: AppColors.primaryLight),
                  ]),
                ),
                const SizedBox(height: 8),
                RewardsPanel(key: _rewards),
                const SizedBox(height: 8),
                _Tile(
                  icon: Icons.verified_user_outlined,
                  title: 'Account verification',
                  subtitle: s.kycVerified ? 'Verified' : 'Required to spin — earns 350 XP',
                  onTap: () async {
                    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const KycScreen()));
                    await _refresh();
                  },
                ),
                if (strOf(_referral['shareUrl']).isNotEmpty)
                  _Tile(
                    icon: Icons.group_add_outlined,
                    title: 'Invite friends',
                    subtitle: 'Code ${strOf(_referral['code'])} · tap to copy your link',
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: strOf(_referral['shareUrl'])));
                      toast(context, 'Invite link copied');
                    },
                  ),
                _Tile(
                  icon: Icons.support_agent_rounded,
                  title: 'Live support',
                  subtitle: 'Chat with our team',
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SupportChatScreen())),
                ),
                _Tile(
                  icon: Icons.system_update_rounded,
                  title: 'Check for updates',
                  subtitle: _version.isEmpty ? 'DazzlingWins for Android' : 'Version $_version',
                  onTap: () => Updater.check(context, userInitiated: true),
                ),
                _Tile(
                  icon: Icons.policy_outlined,
                  title: 'Terms & privacy',
                  subtitle: 'dazzlingwins.com',
                  onTap: () => launchUrl(AppConfig.uri('/'), mode: LaunchMode.externalApplication),
                ),
                const SizedBox(height: 10),
                GhostButton(label: 'Sign out', icon: Icons.logout_rounded, onPressed: _signOut),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Panel(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        radius: 18,
        child: Row(children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: AppColors.surface3, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: AppColors.primaryLight, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: AppTheme.body(14, weight: FontWeight.w800)),
              Text(subtitle, style: AppTheme.body(12, color: AppColors.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
        ]),
      ),
    );
  }
}
