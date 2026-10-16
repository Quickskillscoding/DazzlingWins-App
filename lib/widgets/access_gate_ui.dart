import 'package:flutter/material.dart';

import '../core/access_gate.dart';
import '../core/theme.dart';
import '../features/chat/live_chat_screen.dart';
import '../features/profile/kyc_screen.dart';
import 'ui.dart';

/// "Your IP is not supported – You are blocked" (a VPN or proxy is on).
Future<void> showVpnBlockedPopup(BuildContext context, {String? message}) {
  final text = (message == null || message.trim().isEmpty) ? kVpnBlockedMessage : message.trim();
  return showAppPopup<void>(
    context,
    builder: (ctx) => Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 22),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Center(
          child: Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(color: AppColors.danger.withValues(alpha: 0.15), shape: BoxShape.circle),
            child: const Icon(Icons.gpp_bad_rounded, color: AppColors.danger, size: 38),
          ),
        ),
        const SizedBox(height: 16),
        Text('Your IP is not supported', style: AppTheme.display(22), textAlign: TextAlign.center),
        const SizedBox(height: 4),
        Text('YOU ARE BLOCKED', style: AppTheme.body(12.5, weight: FontWeight.w800, color: AppColors.danger), textAlign: TextAlign.center),
        const SizedBox(height: 12),
        Text(text, style: AppTheme.body(14, color: AppColors.muted, height: 1.45), textAlign: TextAlign.center),
        const SizedBox(height: 22),
        PrimaryButton(label: 'OK', gold: true, onPressed: () => Navigator.of(ctx).maybePop()),
      ]),
    ),
  );
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
