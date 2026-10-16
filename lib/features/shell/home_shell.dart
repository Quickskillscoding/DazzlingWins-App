import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/access_gate.dart';
import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/notification_inbox.dart';
import '../../core/notifications.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/updater.dart';
import '../../widgets/access_gate_ui.dart';
import '../auth/auth_screen.dart';
import '../games/games_screen.dart';
import '../home/home_screen.dart';
import '../profile/profile_screen.dart';
import '../spin/spin_screen.dart';
import '../wallet/wallet_screen.dart';

/// Signed-in app: five tabs kept alive in an IndexedStack (instant switching, no reloads),
/// a floating glass nav bar with a raised Spin button in the middle.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  static void goTo(BuildContext context, int tab) => context.findAncestorStateOfType<_HomeShellState>()?._select(tab);

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _index = 0;

  /// How often the app asks the website whether this player may still use it (VPN / KYC rules).
  static const _accessEvery = Duration(seconds: 60);
  Timer? _accessTimer;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await AppNotifications.init();
      await AppNotifications.requestPermission();
      unawaited(AppNotifications.checkCampaigns().catchError((_) => 0));
      unawaited(NotificationInbox.instance.refresh());
      if (mounted) unawaited(Updater.check(context));
    });
    unawaited(AppAccess.instance.check());
    _accessTimer = Timer.periodic(_accessEvery, (_) {
      if (_foreground) unawaited(AppAccess.instance.check());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _accessTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.resumed) {
      // Back in the app: a VPN turned on meanwhile signs the player out here.
      unawaited(AppAccess.instance.check());
      unawaited(AppState.instance.refreshWallet().catchError((_) {}));
      unawaited(AppNotifications.checkCampaigns().catchError((_) => 0));
      unawaited(NotificationInbox.instance.refresh());
    }
  }

  /// Sign out from the "Complete your sign up" screen.
  Future<void> _signOut() async {
    await ApiClient.instance.post('/api/auth/activity', {'type': 'logout'}).catchError((_) => <String, dynamic>{});
    await AppNotifications.clearOnSignOut();
    await Session.instance.clear();
    AppState.instance.reset();
    NotificationInbox.instance.reset();
    AppAccess.instance.reset();
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const AuthScreen()), (_) => false);
  }

  void _select(int i) {
    if (i == _index) return;
    HapticFeedback.selectionClick();
    setState(() => _index = i);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppAccess.instance,
      builder: (context, _) {
        // Second account on this internet connection: only KYC, chat and sign-out until approved.
        if (AppAccess.instance.signupKycRequired) {
          return PopScope(canPop: false, child: SignupKycGate(onSignOut: _signOut));
        }
        return _shell(context);
      },
    );
  }

  Widget _shell(BuildContext context) {
    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _select(0);
      },
      child: Scaffold(
        extendBody: true,
        body: IndexedStack(index: _index, children: const [
          HomeScreen(),
          GamesScreen(),
          SpinScreen(),
          WalletScreen(),
          ProfileScreen(),
        ]),
        bottomNavigationBar: _NavBar(index: _index, onSelect: _select),
      ),
    );
  }
}

class _NavBar extends StatelessWidget {
  const _NavBar({required this.index, required this.onSelect});
  final int index;
  final ValueChanged<int> onSelect;

  static const _items = [
    (Icons.home_rounded, 'Home'),
    (Icons.sports_esports_rounded, 'Games'),
    (Icons.casino_rounded, 'Spin'),
    (Icons.account_balance_wallet_rounded, 'Wallet'),
    (Icons.person_rounded, 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(14, 0, 14, bottom > 0 ? bottom : 12),
      child: Container(
        height: 70,
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: AppColors.stroke),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 30, offset: const Offset(0, 12))],
        ),
        child: Row(children: [
          for (var i = 0; i < _items.length; i++)
            Expanded(
              child: i == 2
                  ? _SpinTab(active: index == 2, onTap: () => onSelect(2))
                  : _Tab(icon: _items[i].$1, label: _items[i].$2, active: index == i, onTap: () => onSelect(i)),
            ),
        ]),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.icon, required this.label, required this.active, required this.onTap});
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.gold : AppColors.muted;
    return InkResponse(
      onTap: onTap,
      radius: 36,
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        AnimatedScale(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutBack,
          scale: active ? 1.12 : 1,
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(height: 4),
        AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 200),
          style: AppTheme.body(11, weight: active ? FontWeight.w800 : FontWeight.w600, color: color),
          child: Text(label),
        ),
      ]),
    );
  }
}

class _SpinTab extends StatelessWidget {
  const _SpinTab({required this.active, required this.onTap});
  final bool active;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: AppColors.goldGradient,
            boxShadow: [BoxShadow(color: AppColors.gold.withValues(alpha: active ? 0.6 : 0.3), blurRadius: active ? 24 : 14)],
          ),
          child: const Icon(Icons.casino_rounded, color: Color(0xFF1A1200), size: 28),
        ),
      ),
    );
  }
}
