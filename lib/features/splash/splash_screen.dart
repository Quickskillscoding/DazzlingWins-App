import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import '../../core/app_state.dart';
import '../../core/session.dart';
import '../../main.dart' show appStarted;
import '../auth/auth_screen.dart';
import '../shell/home_shell.dart';

/// Casino-style splash: spinning gold chip ring, glowing diamond, floating card suits and a
/// shimmering wordmark. Stays at least [AppConfig.splashMinimum] while the session loads.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.onReady});
  final Future<Widget> Function(BuildContext context) onReady;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat();
  late final AnimationController _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..forward();
  late final AnimationController _shimmer = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat();

  @override
  void initState() {
    super.initState();
    _go();
  }

  Future<void> _go() async {
    final results = await Future.wait<Object?>([
      widget.onReady(context).catchError((Object _) => const AuthScreen()),
      Future<void>.delayed(AppConfig.splashMinimum),
    ]);
    if (!mounted) return;
    var next = results.first as Widget;
    // A Google sign-in may have completed while the splash was showing.
    if (next is AuthScreen && Session.instance.isSignedIn) {
      await AppState.instance.refreshAll().timeout(const Duration(seconds: 6), onTimeout: () {});
      next = const HomeShell();
    }
    if (!mounted) return;
    appStarted.value = true;
    Navigator.of(context).pushReplacement(PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 650),
      pageBuilder: (_, __, ___) => next,
      transitionsBuilder: (_, a, __, child) => FadeTransition(
        opacity: CurvedAnimation(parent: a, curve: Curves.easeOut),
        child: ScaleTransition(scale: Tween(begin: 1.04, end: 1.0).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)), child: child),
      ),
    ));
  }

  @override
  void dispose() {
    _spin.dispose();
    _intro.dispose();
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final intro = CurvedAnimation(parent: _intro, curve: Curves.easeOutBack);
    final fade = CurvedAnimation(parent: _intro, curve: const Interval(0.35, 1, curve: Curves.easeOut));
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(fit: StackFit.expand, children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -0.15),
              radius: 1.0,
              colors: [Color(0xFF2A1E5C), Color(0xFF120C2B), AppColors.bg],
              stops: [0, 0.45, 1],
            ),
          ),
        ),
        RepaintBoundary(child: AnimatedBuilder(animation: _spin, builder: (_, __) => CustomPaint(painter: _SuitsPainter(_spin.value)))),
        Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ScaleTransition(
              scale: intro,
              child: SizedBox(
                width: 210,
                height: 210,
                child: Stack(alignment: Alignment.center, children: [
                  Container(
                    width: 170,
                    height: 170,
                    decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [
                      BoxShadow(color: AppColors.primary.withValues(alpha: 0.55), blurRadius: 80, spreadRadius: 6),
                      BoxShadow(color: AppColors.gold.withValues(alpha: 0.25), blurRadius: 40),
                    ]),
                  ),
                  RepaintBoundary(
                    child: AnimatedBuilder(
                      animation: _spin,
                      builder: (_, child) => Transform.rotate(angle: _spin.value * 2 * math.pi, child: child),
                      child: const CustomPaint(size: Size(210, 210), painter: _ChipRingPainter()),
                    ),
                  ),
                  Image.asset('assets/brand/logo_mark.png', width: 150, height: 150, filterQuality: FilterQuality.medium),
                ]),
              ),
            ),
            const SizedBox(height: 34),
            FadeTransition(
              opacity: fade,
              child: AnimatedBuilder(
                animation: _shimmer,
                builder: (_, child) => ShaderMask(
                  blendMode: BlendMode.srcIn,
                  shaderCallback: (rect) => LinearGradient(
                    begin: Alignment(-1.5 + _shimmer.value * 3, 0),
                    end: Alignment(-0.5 + _shimmer.value * 3, 0),
                    colors: const [AppColors.gold, Color(0xFFFFF6D6), AppColors.gold],
                  ).createShader(rect),
                  child: child,
                ),
                child: Text('DAZZLINGWINS', style: AppTheme.display(30, weight: FontWeight.w800).copyWith(letterSpacing: 4)),
              ),
            ),
            const SizedBox(height: 10),
            FadeTransition(
              opacity: fade,
              child: Text('PLAY  ·  WIN  ·  SHINE', style: AppTheme.body(12, weight: FontWeight.w700, color: AppColors.muted).copyWith(letterSpacing: 5)),
            ),
          ]),
        ),
        Positioned(
          left: 80,
          right: 80,
          bottom: 70,
          child: FadeTransition(
            opacity: fade,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: const LinearProgressIndicator(
                minHeight: 4,
                backgroundColor: AppColors.surface2,
                valueColor: AlwaysStoppedAnimation(AppColors.gold),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

/// Gold casino-chip edge: dashed ring of 16 inserts.
class _ChipRingPainter extends CustomPainter {
  const _ChipRingPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 6;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = AppColors.gold.withValues(alpha: 0.35);
    canvas.drawCircle(c, r, ring);
    final dash = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round
      ..shader = AppColors.goldGradient.createShader(Rect.fromCircle(center: c, radius: r));
    const count = 16;
    for (var i = 0; i < count; i++) {
      final a = i * 2 * math.pi / count;
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), a, 0.18, false, dash);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Card suits drifting upward in the background.
class _SuitsPainter extends CustomPainter {
  _SuitsPainter(this.t);
  final double t;
  static const _suits = ['♠', '♥', '♦', '♣'];

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(7);
    for (var i = 0; i < 18; i++) {
      final x = rnd.nextDouble() * size.width;
      final speed = 0.4 + rnd.nextDouble() * 0.8;
      final phase = rnd.nextDouble();
      final y = size.height * (1.1 - ((t * speed + phase) % 1.0) * 1.2);
      final fontSize = 14 + rnd.nextDouble() * 18;
      final suit = _suits[i % 4];
      final red = suit == '♥' || suit == '♦';
      final tp = TextPainter(
        text: TextSpan(
          text: suit,
          style: TextStyle(
            fontSize: fontSize,
            color: (red ? AppColors.primaryLight : AppColors.gold).withValues(alpha: 0.10 + rnd.nextDouble() * 0.12),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x, y));
    }
  }

  @override
  bool shouldRepaint(covariant _SuitsPainter oldDelegate) => oldDelegate.t != t;
}
