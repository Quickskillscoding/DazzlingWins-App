import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api.dart';
import '../core/app_state.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../features/profile/support_chat_screen.dart';
import 'ui.dart';

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
              _RoundAction(
                icon: Icons.notifications_none_rounded,
                tooltip: 'Notifications',
                onTap: () => showNotificationsSheet(context),
              ),
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

/// The player's recent promo notifications (last 30 days), same source as the system notifications.
Future<void> showNotificationsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const _NotificationsSheet(),
  );
}

class _NotificationsSheet extends StatefulWidget {
  const _NotificationsSheet();
  @override
  State<_NotificationsSheet> createState() => _NotificationsSheetState();
}

class _NotificationsSheetState extends State<_NotificationsSheet> {
  List<Map<String, dynamic>>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final since = DateTime.now().toUtc().subtract(const Duration(days: 30)).toIso8601String();
      final d = await ApiClient.instance.get('/api/app/notifications', query: {'since': since});
      if (mounted) setState(() => _items = listOf(d['notifications']).reversed.toList());
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Text('Notifications', style: AppTheme.display(20)),
        ),
        Flexible(
          child: _error != null
              ? ErrorRetry(message: _error!, onRetry: _load)
              : items == null
                  ? const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
                  : items.isEmpty
                      ? const EmptyState(
                          icon: Icons.notifications_none_rounded,
                          title: 'No notifications yet',
                          subtitle: 'Offers and bonuses from DazzlingWins show up here.',
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
                          itemCount: items.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (_, i) {
                            final n = items[i];
                            return Panel(
                              padding: const EdgeInsets.all(14),
                              radius: 18,
                              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(color: AppColors.gold.withValues(alpha: 0.14), shape: BoxShape.circle),
                                  child: const Icon(Icons.card_giftcard_rounded, color: AppColors.gold, size: 20),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(strOf(n['title'], 'New offer for you'), style: AppTheme.body(14, weight: FontWeight.w800)),
                                    if (strOf(n['body']).isNotEmpty) ...[
                                      const SizedBox(height: 3),
                                      Text(strOf(n['body']), style: AppTheme.body(13, color: AppColors.muted, height: 1.35)),
                                    ],
                                    const SizedBox(height: 6),
                                    Text(relativeTime(n['at']), style: AppTheme.body(11, color: AppColors.faint)),
                                  ]),
                                ),
                              ]),
                            );
                          },
                        ),
        ),
      ]),
    );
  }
}
