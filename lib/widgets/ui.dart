import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/config.dart';
import '../core/theme.dart';

/// Rounded surface card with a hairline border (the app's base container).
class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.padding = const EdgeInsets.all(18), this.gradient, this.onTap, this.radius = 22, this.border});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Gradient? gradient;
  final VoidCallback? onTap;
  final double radius;
  final Color? border;

  @override
  Widget build(BuildContext context) {
    final box = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: gradient == null ? AppColors.surface : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: border ?? AppColors.stroke.withValues(alpha: 0.8)),
      ),
      child: child,
    );
    if (onTap == null) return box;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(radius),
      child: InkWell(borderRadius: BorderRadius.circular(radius), onTap: onTap, child: box),
    );
  }
}

/// Main call-to-action: gradient pill with a loading state. Haptic tick on press.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({super.key, required this.label, required this.onPressed, this.loading = false, this.icon, this.gold = false, this.height = 56});
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;
  final bool gold;
  final double height;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    final fg = gold ? const Color(0xFF1A1200) : Colors.white;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: enabled ? 1 : 0.55,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: gold ? AppColors.goldGradient : AppColors.primaryGradient,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: (gold ? AppColors.gold : AppColors.primary).withValues(alpha: enabled ? 0.35 : 0),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: enabled
                ? () {
                    HapticFeedback.lightImpact();
                    onPressed!();
                  }
                : null,
            child: SizedBox(
              height: height,
              child: Center(
                child: loading
                    ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: fg))
                    : Row(mainAxisSize: MainAxisSize.min, children: [
                        if (icon != null) ...[Icon(icon, color: fg, size: 20), const SizedBox(width: 8)],
                        Text(label, style: AppTheme.display(15, color: fg, weight: FontWeight.w700)),
                      ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class GhostButton extends StatelessWidget {
  const GhostButton({super.key, required this.label, required this.onPressed, this.icon});
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        side: const BorderSide(color: AppColors.stroke),
        foregroundColor: AppColors.text,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 18), const SizedBox(width: 8)],
        Text(label, style: AppTheme.body(14, weight: FontWeight.w700)),
      ]),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 12),
      child: Row(children: [
        Expanded(child: Text(text, style: AppTheme.display(18))),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.label, {super.key});
  final String label;
  @override
  Widget build(BuildContext context) {
    final color = switch (label) {
      'Approved' || 'Won' || 'Cashout' || 'Verified' => AppColors.mint,
      'Rejected' || 'Unverified' => AppColors.danger,
      'Pending' => AppColors.warning,
      _ => AppColors.muted,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(99)),
      child: Text(label, style: AppTheme.body(11, weight: FontWeight.w800, color: color)),
    );
  }
}

/// Network image from the website (game cards, payment logos) with a soft placeholder.
class NetImage extends StatelessWidget {
  const NetImage(this.path, {super.key, this.fit = BoxFit.cover, this.radius = 0, this.cacheWidth});
  final String path;
  final BoxFit fit;
  final double radius;
  final int? cacheWidth;

  @override
  Widget build(BuildContext context) {
    // Uri.replace(path:) percent-encodes spaces ("/Game Cards/…").
    final url = AppConfig.asset(path);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: CachedNetworkImage(
        imageUrl: url,
        fit: fit,
        memCacheWidth: cacheWidth,
        fadeInDuration: const Duration(milliseconds: 160),
        placeholder: (_, __) => const ColoredBox(color: AppColors.surface2),
        errorWidget: (_, __, ___) => const ColoredBox(
          color: AppColors.surface2,
          child: Center(child: Icon(Icons.image_not_supported_outlined, color: AppColors.faint)),
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.subtitle});
  final IconData icon;
  final String title;
  final String? subtitle;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      child: Column(children: [
        Container(
          width: 64,
          height: 64,
          decoration: const BoxDecoration(color: AppColors.surface2, shape: BoxShape.circle),
          child: Icon(icon, color: AppColors.muted, size: 28),
        ),
        const SizedBox(height: 14),
        Text(title, style: AppTheme.body(15, weight: FontWeight.w700), textAlign: TextAlign.center),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(subtitle!, style: AppTheme.body(13, color: AppColors.muted), textAlign: TextAlign.center),
        ],
      ]),
    );
  }
}

class ErrorRetry extends StatelessWidget {
  const ErrorRetry({super.key, required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.wifi_off_rounded, color: AppColors.muted, size: 32),
        const SizedBox(height: 10),
        Text(message, style: AppTheme.body(14, color: AppColors.muted), textAlign: TextAlign.center),
        const SizedBox(height: 14),
        TextButton(onPressed: onRetry, child: Text('Try again', style: AppTheme.body(14, weight: FontWeight.w800, color: AppColors.primaryLight))),
      ]),
    );
  }
}

/// Subtle shimmer block for loading skeletons.
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, this.height = 16, this.width = double.infinity, this.radius = 12});
  final double height;
  final double width;
  final double radius;
  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => Container(
        height: widget.height,
        width: widget.width,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius),
          gradient: LinearGradient(
            begin: Alignment(-1 + _c.value * 3, 0),
            end: Alignment(_c.value * 3, 0),
            colors: const [AppColors.surface2, AppColors.surface3, AppColors.surface2],
          ),
        ),
      ),
    );
  }
}

/// The app's pop-up window: a card in the MIDDLE of the screen (never a sheet at the bottom, where
/// the phone's navigation buttons cover its actions). Tap outside or press back to close it, unless
/// [dismissible] is false. It stays clear of the status bar, the navigation bar and the keyboard,
/// and its content scrolls when it is taller than the screen.
Future<T?> showAppPopup<T>(BuildContext context, {required WidgetBuilder builder, bool dismissible = true, double maxWidth = 460}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: dismissible,
    barrierLabel: 'Close',
    barrierColor: Colors.black.withValues(alpha: 0.64),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, _, __) => _AppPopup(maxWidth: maxWidth, child: Builder(builder: builder)),
    transitionsBuilder: (ctx, animation, _, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(scale: Tween<double>(begin: 0.94, end: 1).animate(curved), child: child),
      );
    },
  );
}

class _AppPopup extends StatelessWidget {
  const _AppPopup({required this.maxWidth, required this.child});
  final double maxWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.of(context).viewInsets.bottom;
    return SafeArea(
      child: AnimatedPadding(
        // Lift the card above the keyboard.
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + keyboard),
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Material(
              color: AppColors.surface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26), side: const BorderSide(color: AppColors.stroke)),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.only(top: 20),
                // The keyboard is already handled above: the content must not add room for it again.
                child: MediaQuery.removeViewInsets(
                  context: context,
                  removeBottom: true,
                  // Always the full card width, however narrow the content is.
                  child: SizedBox(width: double.infinity, child: child),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

void toast(BuildContext context, String message, {bool error = false}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Row(children: [
        Icon(error ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
            color: error ? AppColors.danger : AppColors.mint, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(message)),
      ]),
      duration: Duration(milliseconds: error ? 4200 : 2600),
    ));
}

/// The app's background: deep gradient with a soft violet glow at the top.
class AppBackground extends StatelessWidget {
  const AppBackground({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -1.1),
          radius: 1.3,
          colors: [Color(0xFF1E1546), AppColors.bg],
          stops: [0, 0.7],
        ),
      ),
      child: child,
    );
  }
}
