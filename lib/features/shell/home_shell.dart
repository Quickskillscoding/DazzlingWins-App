import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_state.dart';
import '../../core/notifications.dart';
import '../../core/theme.dart';
import '../../core/updater.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await AppNotifications.init();
      await AppNotifications.requestPermission();
      unawaited(AppNotifications.checkCampaigns().catchError((_) => 0));
      if (mounted) unawaited(Updater.check(context));
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(AppState.instance.refreshWallet().catchError((_) {}));
      unawaited(AppNotifications.checkCampaigns().catchError((_) => 0));
    }
  }

  void _select(int i) {
    if (i == _index) return;
    HapticFeedback.selectionClick();
    setState(() => _index = i);
  }

  @override
  Widget build(BuildContext context) {
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
