import 'package:flutter/material.dart';

import '../core/access_gate.dart';
import '../core/theme.dart';
import '../features/chat/live_chat_screen.dart';
import '../features/profile/kyc_screen.dart';
import 'ui.dart';

/// "Your IP is not supported – You are blocked" (a VPN or proxy is on), over a blurred screen.
Future<void> showVpnBlockedPopup(BuildContext context, {String? message}) {
  final custom = message != null && message.trim().isNotEmpty && !message.trim().toLowerCase().startsWith('your ip is not supported');
  return showAppPopup<void>(
    context,
    blur: true,
    maxWidth: 420,
    builder: (ctx) => _VpnBlockedCard(message: custom ? message!.trim() : null),
  );
}

class _VpnBlockedCard extends StatelessWidget {
  const _VpnBlockedCard({this.message});
  final String? message;

  static const _steps = [
    (Icons.wifi_off_rounded, 'Turn off your VPN, proxy or private relay.'),
    (Icons.wifi_rounded, 'Reconnect to your normal Wi-Fi or mobile data.'),
    (Icons.login_rounded, 'Sign in again. Everything works as usual.'),
  ];

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        // A soft red glow behind the shield that fades out before the card's edges.
        gradient: RadialGradient(center: Alignment(0, -0.75), radius: 0.85, colors: [Color(0x33FF5C7A), Color(0x00FF5C7A)]),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 6, 22, 22),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(
            child: Container(
              width: 82,
              height: 82,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [AppColors.danger.withValues(alpha: 0.32), AppColors.danger.withValues(alpha: 0.08)],
                ),
                border: Border.all(color: AppColors.danger.withValues(alpha: 0.45)),
                boxShadow: [BoxShadow(color: AppColors.danger.withValues(alpha: 0.35), blurRadius: 34)],
              ),
              child: const Icon(Icons.gpp_bad_rounded, color: Color(0xFFFF9AAE), size: 42),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: AppColors.danger.withValues(alpha: 0.45)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 6, height: 6, decoration: const BoxDecoration(color: AppColors.danger, shape: BoxShape.circle)),
                const SizedBox(width: 7),
                Text('YOU ARE BLOCKED', style: AppTheme.body(11, weight: FontWeight.w800, color: const Color(0xFFFF9AAE)).copyWith(letterSpacing: 1.6)),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          Text('Your IP is not supported', style: AppTheme.display(24), textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(
            message ?? 'A VPN, proxy or private relay is turned on. DazzlingWins only works on your normal internet connection.',
            style: AppTheme.body(14, color: AppColors.muted, height: 1.45),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          for (var i = 0; i < _steps.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 11, 14, 11),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.035),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
                ),
                child: Row(children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(color: AppColors.gold.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(11)),
                    child: Icon(_steps[i].$1, size: 17, color: AppColors.gold),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text.rich(TextSpan(children: [
                      TextSpan(text: '${i + 1}. ', style: AppTheme.body(13.5, weight: FontWeight.w800, color: AppColors.gold)),
                      TextSpan(text: _steps[i].$2, style: AppTheme.body(13.5, weight: FontWeight.w600, color: AppColors.text.withValues(alpha: 0.85))),
                    ])),
                  ),
                ]),
              ),
            ),
          const SizedBox(height: 12),
          PrimaryButton(label: 'OK, got it', gold: true, onPressed: () => Navigator.of(context).maybePop()),
        ]),
      ),
    );
  }
}

/// Full-screen "Complete your sign up" for a second account on the same internet connection.
/// Only KYC, Live Chat and signing out are possible until the KYC is approved.
class SignupKycGate extends StatelessWidget {
  const SignupKycGate({super.key, required this.onSignOut});
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppAccess.instance,
      builder: (context, _) {
        final access = AppAccess.instance;
        final pending = access.kycStatus == 'pending';
        final rejected = access.kycStatus == 'rejected';
        return Material(
          color: AppColors.bg,
          child: AppBackground(
            child: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
                  child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Center(
                      child: Container(
                        width: 84,
                        height: 84,
                        decoration: BoxDecoration(
                          color: AppColors.gold.withValues(alpha: 0.14),
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.gold.withValues(alpha: 0.5)),
                        ),
                        child: Icon(pending ? Icons.hourglass_top_rounded : Icons.verified_user_outlined, color: AppColors.gold, size: 40),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(pending ? 'KYC under review' : 'Complete your sign up', style: AppTheme.display(26), textAlign: TextAlign.center),
                    const SizedBox(height: 10),
                    Text(
                      pending
                          ? 'Your KYC was received and is being reviewed. Your account opens as soon as it is approved.'
                          : (access.message.isEmpty ? kSignupKycMessage : access.message),
                      style: AppTheme.body(14.5, color: AppColors.muted, height: 1.45),
                      textAlign: TextAlign.center,
                    ),
                    if (rejected) ...[
                      const SizedBox(height: 10),
                      Text('Your last KYC was not approved. Please submit it again.',
                          style: AppTheme.body(13, weight: FontWeight.w700, color: AppColors.danger), textAlign: TextAlign.center),
                    ],
                    const SizedBox(height: 26),
                    if (!pending)
                      PrimaryButton(
                        label: 'Submit KYC',
                        icon: Icons.badge_outlined,
                        gold: true,
                        onPressed: () async {
                          await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const KycScreen()));
                          await AppAccess.instance.check();
                        },
                      )
                    else
                      PrimaryButton(label: 'Check again', icon: Icons.refresh_rounded, gold: true, onPressed: AppAccess.instance.check),
                    const SizedBox(height: 10),
                    GhostButton(
                      label: 'Live Chat',
                      icon: Icons.chat_bubble_outline_rounded,
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LiveChatScreen())),
                    ),
                    const SizedBox(height: 4),
                    TextButton(
                      onPressed: onSignOut,
                      child: Text('Sign out', style: AppTheme.body(14, weight: FontWeight.w700, color: AppColors.muted)),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
