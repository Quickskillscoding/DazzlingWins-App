import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/format.dart';
import '../core/notification_inbox.dart';
import '../core/theme.dart';

/// Opens the notification window directly under the bell.
/// [anchorContext] must be the bell button's own context: the window hangs from its bottom edge,
/// right-aligned with it, with a small pointer aimed at the bell.
Future<void> showNotificationsPopover(BuildContext anchorContext) {
  final navigator = Navigator.of(anchorContext, rootNavigator: true);
  final screen = MediaQuery.of(anchorContext).size;
  final topInset = MediaQuery.of(anchorContext).padding.top;

  // Where the bell is on screen. If it cannot be measured, fall back to the header's bell spot.
  var anchor = Rect.fromLTWH(screen.width - 62, topInset + 12, 44, 44);
  final box = anchorContext.findRenderObject();
  if (box is RenderBox && box.attached && box.hasSize) {
    final measured = box.localToGlobal(Offset.zero) & box.size;
    if (measured.isFinite && !measured.isEmpty) anchor = measured;
  }

  NotificationInbox.instance.refresh();

  return navigator.push<void>(PageRouteBuilder<void>(
    opaque: false,
    barrierDismissible: true,
    barrierLabel: 'Close notifications',
    barrierColor: Colors.black.withValues(alpha: 0.5),
    transitionDuration: const Duration(milliseconds: 210),
    reverseTransitionDuration: const Duration(milliseconds: 150),
    pageBuilder: (_, __, ___) => _PopoverLayer(anchor: anchor),
    transitionsBuilder: (context, animation, _, child) {
      final size = MediaQuery.of(context).size;
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
      // Grow out of the bell.
      final origin = Alignment(
        size.width <= 0 ? 1 : (anchor.center.dx / size.width) * 2 - 1,
        size.height <= 0 ? -1 : (anchor.bottom / size.height) * 2 - 1,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(scale: Tween(begin: 0.9, end: 1.0).animate(curved), alignment: origin, child: child),
      );
    },
  ));
}

class _PopoverLayer extends StatelessWidget {
  const _PopoverLayer({required this.anchor});
  final Rect anchor;

  static const _edge = 12.0; // smallest gap to the screen edges
  static const _gap = 12.0; // gap between the bell and the window
  static const _maxWidth = 380.0;
  static const _pointer = 14.0;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final size = mq.size;

    // Right edge lines up with the bell's right edge.
    final right = math.max(_edge, size.width - anchor.right);
    final width = math.max(240.0, math.min(_maxWidth, size.width - right - _edge));
    final top = math.max(mq.padding.top + _edge, anchor.bottom + _gap);
    final room = size.height - top - mq.padding.bottom - mq.viewInsets.bottom - 24;
    final maxHeight = math.max(220.0, math.min(520.0, room));
    // Pointer centred under the bell, kept clear of the window's rounded corner.
    final pointerRight = right + math.max(18.0, anchor.width / 2 - _pointer / 2);

    return Stack(children: [
      // Tap anywhere outside the window to close it.
      Positioned.fill(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(context).maybePop(),
          child: const SizedBox.expand(),
        ),
      ),
      Positioned(
        top: top - _pointer / 2,
        right: pointerRight,
        child: Transform.rotate(
          angle: math.pi / 4,
          child: Container(
            width: _pointer,
            height: _pointer,
            decoration: BoxDecoration(
              color: AppColors.surface2,
              border: Border.all(color: AppColors.stroke),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
      ),
      Positioned(
        top: top,
        right: right,
        width: width,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: const _NotificationsPanel(),
        ),
      ),
    ]);
  }
}

class _NotificationsPanel extends StatelessWidget {
  const _NotificationsPanel();

  Future<void> _confirmClearAll(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Clear all notifications?', style: AppTheme.display(18)),
        content: Text('This removes every notification from your inbox.', style: AppTheme.body(14, color: AppColors.muted)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Clear all', style: AppTheme.body(14, weight: FontWeight.w800, color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok == true) {
      HapticFeedback.mediumImpact();
      await NotificationInbox.instance.clearAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    final inbox = NotificationInbox.instance;
    return Material(
      type: MaterialType.transparency,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppColors.stroke),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.55), blurRadius: 34, offset: const Offset(0, 16))],
        ),
        clipBehavior: Clip.antiAlias,
        child: ListenableBuilder(
          listenable: inbox,
          builder: (context, _) {
            final items = inbox.items;
            final unread = inbox.unreadCount;
            return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 0),
                child: Row(children: [
                  Flexible(child: Text('Notifications', style: AppTheme.display(17), maxLines: 1, overflow: TextOverflow.ellipsis)),
                  if (unread > 0) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: AppColors.gold.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(99)),
                      child: Text('$unread new', style: AppTheme.body(11, weight: FontWeight.w800, color: AppColors.gold)),
                    ),
                  ],
                  const Spacer(),
                  IconButton(
                    tooltip: 'Close',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close_rounded, size: 20, color: AppColors.muted),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
                child: Row(children: [
                  _HeaderAction(
                    icon: Icons.done_all_rounded,
                    label: 'Mark all read',
                    color: AppColors.primaryLight,
                    onTap: unread > 0
                        ? () {
                            HapticFeedback.selectionClick();
                            inbox.markAllRead();
                          }
                        : null,
                  ),
                  const Spacer(),
                  _HeaderAction(
                    icon: Icons.delete_sweep_outlined,
                    label: 'Clear all',
                    color: AppColors.danger,
                    onTap: items.isNotEmpty ? () => _confirmClearAll(context) : null,
                  ),
                ]),
              ),
              const Divider(height: 1, thickness: 1, color: AppColors.stroke),
              Flexible(child: _body(context, inbox, items)),
            ]);
          },
        ),
      ),
    );
  }

  Widget _body(BuildContext context, NotificationInbox inbox, List<InboxItem> items) {
    if (items.isEmpty) {
      if (inbox.loading && !inbox.fetched) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 44),
          child: Center(child: SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.6))),
        );
      }
      if (inbox.error != null && !inbox.fetched) {
        return _Message(
          icon: Icons.wifi_off_rounded,
          title: 'Could not load notifications',
          subtitle: inbox.error!,
          action: TextButton(
            onPressed: inbox.refresh,
            child: Text('Try again', style: AppTheme.body(14, weight: FontWeight.w800, color: AppColors.primaryLight)),
          ),
        );
      }
      return const _Message(
        icon: Icons.notifications_none_rounded,
        title: 'You are all caught up',
        subtitle: 'Offers and bonuses from DazzlingWins show up here.',
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final item = items[i];
        return _NotificationTile(key: ValueKey(item.key), item: item, read: inbox.isRead(item));
      },
    );
  }
}

class _HeaderAction extends StatelessWidget {
  const _HeaderAction({required this.icon, required this.label, required this.color, required this.onTap});
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final shown = onTap == null ? AppColors.faint : color;
    return TextButton.icon(
      onPressed: onTap,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        minimumSize: const Size(0, 40),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: shown,
        disabledForegroundColor: AppColors.faint,
      ),
      icon: Icon(icon, size: 18, color: shown),
      label: Text(label, style: AppTheme.body(13, weight: FontWeight.w800, color: shown)),
    );
  }
}

/// One notification: tap to mark it read, swipe left or tap the bin to delete it.
class _NotificationTile extends StatelessWidget {
  const _NotificationTile({super.key, required this.item, required this.read});
  final InboxItem item;
  final bool read;

  @override
  Widget build(BuildContext context) {
    final inbox = NotificationInbox.instance;
    final radius = BorderRadius.circular(16);
    return Dismissible(
      key: ValueKey('dismiss-${item.key}'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) {
        HapticFeedback.selectionClick();
        inbox.delete(item);
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 18),
        decoration: BoxDecoration(color: AppColors.danger.withValues(alpha: 0.18), borderRadius: radius),
        child: const Icon(Icons.delete_outline_rounded, color: AppColors.danger, size: 22),
      ),
      child: Material(
        color: read ? AppColors.surface : AppColors.surface3,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: read ? AppColors.stroke : AppColors.primary.withValues(alpha: 0.55)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: read ? null : () => inbox.markRead(item),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 2, 12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Stack(clipBehavior: Clip.none, children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(color: AppColors.gold.withValues(alpha: 0.14), shape: BoxShape.circle),
                  child: const Icon(Icons.card_giftcard_rounded, color: AppColors.gold, size: 19),
                ),
                if (!read)
                  Positioned(
                    top: -1,
                    right: -1,
                    child: Container(
                      width: 11,
                      height: 11,
                      decoration: BoxDecoration(
                        color: AppColors.mint,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.surface3, width: 2),
                      ),
                    ),
                  ),
              ]),
              const SizedBox(width: 11),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    item.title,
                    style: AppTheme.body(13.5, weight: read ? FontWeight.w600 : FontWeight.w800, color: read ? AppColors.muted : AppColors.text, height: 1.3),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (item.body.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      item.body,
                      style: AppTheme.body(12.5, color: read ? AppColors.faint : AppColors.muted, height: 1.35),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(relativeTime(item.at), style: AppTheme.body(11, color: AppColors.faint)),
                ]),
              ),
              IconButton(
                tooltip: 'Delete',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.delete_outline_rounded, size: 19, color: AppColors.faint),
                onPressed: () {
                  HapticFeedback.selectionClick();
                  inbox.delete(item);
                },
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.title, required this.subtitle, this.action});
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 28, 22, 26),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 56,
          height: 56,
          decoration: const BoxDecoration(color: AppColors.surface3, shape: BoxShape.circle),
          child: Icon(icon, color: AppColors.muted, size: 26),
        ),
        const SizedBox(height: 12),
        Text(title, style: AppTheme.body(15, weight: FontWeight.w800), textAlign: TextAlign.center),
        const SizedBox(height: 5),
        Text(subtitle, style: AppTheme.body(13, color: AppColors.muted, height: 1.35), textAlign: TextAlign.center),
        if (action != null) ...[const SizedBox(height: 8), action!],
      ]),
    );
  }
}
