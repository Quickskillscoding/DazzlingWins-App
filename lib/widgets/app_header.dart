import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_state.dart';
import '../core/notification_inbox.dart';
import '../core/theme.dart';
import '../features/profile/support_chat_screen.dart';
import 'notifications_popover.dart';

/// The signed-in app header, pinned at the top of a scroll view.
///  * At the top of the page: the player's avatar and name, with chat and notification buttons.
///  * Once the page is scrolled: a compact sticky bar with the DazzlingWins logo and the same
///    two buttons, on a solid background so content slides underneath it.
/// Put it first in a CustomScrollView's slivers and pass that view's [ScrollController].
class AppHeaderSliver extends StatefulWidget {
  const AppHeaderSliver({super.key, required this.controller});
  final ScrollController controller;

  @override
  State<AppHeaderSliver> createState() => _AppHeaderSliverState();
}

class _AppHeaderSliverState extends State<AppHeaderSliver> {
  /// Scroll distance after which the header switches to the compact logo bar.
  static const _threshold = 28.0;
  final _scrolled = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant AppHeaderSliver oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onScroll);
      widget.controller.addListener(_onScroll);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onScroll);
    _scrolled.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!widget.controller.hasClients) return;
    final next = widget.controller.offset > _threshold;
    if (next != _scrolled.value) _scrolled.value = next;
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return SliverPersistentHeader(
      pinned: true,
      delegate: _HeaderDelegate(topPadding: top, scrolled: _scrolled),
    );
  }
}

class _HeaderDelegate extends SliverPersistentHeaderDelegate {
  _HeaderDelegate({required this.topPadding, required this.scrolled});
  final double topPadding;
  final ValueNotifier<bool> scrolled;

  static const _barHeight = 68.0;

  @override
  double get minExtent => topPadding + _barHeight;
  @override
  double get maxExtent => topPadding + _barHeight;

  @override
  bool shouldRebuild(covariant _HeaderDelegate oldDelegate) =>
      oldDelegate.topPadding != topPadding || oldDelegate.scrolled != scrolled;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return ValueListenableBuilder<bool>(
      valueListenable: scrolled,
      builder: (context, compact, _) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          padding: EdgeInsets.fromLTRB(18, topPadding, 18, 0),
          decoration: BoxDecoration(
            color: compact ? AppColors.bg.withValues(alpha: 0.97) : AppColors.bg.withValues(alpha: 0),
            border: Border(bottom: BorderSide(color: compact ? AppColors.stroke : Colors.transparent)),
            boxShadow: compact ? [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 18, offset: const Offset(0, 6))] : const [],
          ),
          child: SizedBox(
            height: _barHeight,
            child: Row(children: [
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 240),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  layoutBuilder: (current, previous) => Stack(
                    alignment: Alignment.centerLeft,
                    children: [...previous, if (current != null) current],
                  ),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween(begin: const Offset(0, 0.25), end: Offset.zero).animate(animation),
                      child: child,
                    ),
                  ),
                  child: compact ? const _LogoRow(key: ValueKey('logo')) : const _ProfileRow(key: ValueKey('profile')),
                ),
              ),
              const SizedBox(width: 12),
              _RoundAction(
                icon: Icons.chat_bubble_outline_rounded,
                tooltip: 'Support chat',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SupportChatScreen())),
              ),
              const SizedBox(width: 10),
              const _BellAction(),
            ]),
          ),
        );
      },
    );
  }
}

/// Avatar + name (top of the page).
class _ProfileRow extends StatelessWidget {
  const _ProfileRow({super.key});
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.instance,
      builder: (context, _) {
        final name = AppState.instance.displayName;
        final initial = name.trim().isEmpty ? 'P' : name.trim().substring(0, 1).toUpperCase();
        return Row(children: [
          Container(
            width: 46,
            height: 46,
            padding: const EdgeInsets.all(2),
            decoration: const BoxDecoration(gradient: AppColors.goldGradient, shape: BoxShape.circle),
            child: Container(
              decoration: const BoxDecoration(color: AppColors.surface2, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: Text(initial, style: AppTheme.display(19, color: AppColors.goldLight)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(name, style: AppTheme.display(18), maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ]);
      },
    );
  }
}

/// Brand logo (sticky bar after scrolling).
class _LogoRow extends StatelessWidget {
  const _LogoRow({super.key});
  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Image.asset('assets/brand/logo_full.png', height: 44, fit: BoxFit.contain, alignment: Alignment.centerLeft),
    );
  }
}

/// Round violet action button (chat / notifications).
class _RoundAction extends StatelessWidget {
  const _RoundAction({required this.icon, required this.tooltip, required this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          gradient: AppColors.primaryGradient,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.35), blurRadius: 14, offset: const Offset(0, 5))],
        ),
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              onTap();
            },
            child: Icon(icon, color: Colors.white, size: 22),
          ),
        ),
      ),
    );
  }
}

/// The bell: shows how many notifications are unread and opens the notification window under itself.
class _BellAction extends StatelessWidget {
  const _BellAction();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: NotificationInbox.instance,
      builder: (context, _) {
        final unread = NotificationInbox.instance.unreadCount;
        return Stack(clipBehavior: Clip.none, children: [
          // Builder: the popover is anchored to the button itself, not to the badge around it.
          Builder(
            builder: (anchor) => _RoundAction(
              icon: unread > 0 ? Icons.notifications_active_outlined : Icons.notifications_none_rounded,
              tooltip: 'Notifications',
              onTap: () => showNotificationsPopover(anchor),
            ),
          ),
          if (unread > 0)
            Positioned(
              top: -3,
              right: -3,
              child: IgnorePointer(
                child: Container(
                  constraints: const BoxConstraints(minWidth: 19, minHeight: 19),
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.danger,
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: AppColors.bg, width: 2),
                  ),
                  child: Text(
                    unread > 9 ? '9+' : '$unread',
                    style: AppTheme.body(10, weight: FontWeight.w800, color: Colors.white, height: 1.1),
                  ),
                ),
              ),
            ),
        ]);
      },
    );
  }
}
