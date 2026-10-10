import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// The game-style wait screen ("Lucky Reels") shown while the team works on a request: three
/// spinning reels, a line that changes every couple of seconds, and a moving bar.
/// It only entertains: the page behind it keeps asking the server whether the request is done.
class LuckyReelsWait extends StatefulWidget {
  const LuckyReelsWait({super.key, required this.lines, required this.subtitle, this.title = 'Lucky Reels', this.onHide});
  final String title;
  final List<String> lines;
  final String subtitle;

  /// Shows a "Hide" button when set (the request keeps running in the background).
  final VoidCallback? onHide;

  @override
  State<LuckyReelsWait> createState() => _LuckyReelsWaitState();
}

class _LuckyReelsWaitState extends State<LuckyReelsWait> {
  static const _symbols = ['7', '★', '♦', '🍒', '💎', '🎰'];
  final _random = Random();
  late List<int> _reels = [5, 0, 1];
  int _line = 0;
  Timer? _reelTimer;
  Timer? _lineTimer;

  @override
  void initState() {
    super.initState();
    _reelTimer = Timer.periodic(const Duration(milliseconds: 420), (_) {
      if (!mounted) return;
      setState(() => _reels = [for (var i = 0; i < 3; i++) _random.nextInt(_symbols.length)]);
    });
    _lineTimer = Timer.periodic(const Duration(milliseconds: 2300), (_) {
      if (!mounted || widget.lines.isEmpty) return;
      setState(() => _line = (_line + 1) % widget.lines.length);
    });
  }

  @override
  void dispose() {
    _reelTimer?.cancel();
    _lineTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final line = widget.lines.isEmpty ? '' : widget.lines[_line % widget.lines.length];
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(colors: [Color(0xFF2A1258), Color(0xFF070B14)], radius: 0.95),
      ),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
                decoration: BoxDecoration(
                  color: const Color(0xFF120A2A),
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: AppColors.gold.withValues(alpha: 0.45)),
                  boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.35), blurRadius: 40)],
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(widget.title.toUpperCase(), style: AppTheme.body(12, weight: FontWeight.w800, color: AppColors.gold).copyWith(letterSpacing: 3.5)),
                  const SizedBox(height: 16),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    for (var i = 0; i < 3; i++)
                      Padding(
                        padding: EdgeInsets.only(left: i == 0 ? 0 : 10),
                        child: Container(
                          width: 66,
                          height: 82,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF2B2150), Color(0xFF17112F)]),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                          ),
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 160),
                            transitionBuilder: (child, animation) => FadeTransition(
                              opacity: animation,
                              child: SlideTransition(position: Tween(begin: const Offset(0, -0.35), end: Offset.zero).animate(animation), child: child),
                            ),
                            child: Text(
                              _symbols[_reels[i]],
                              key: ValueKey('$i-${_reels[i]}'),
                              style: const TextStyle(fontSize: 34, color: Colors.white, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ),
                  ]),
                ]),
              ),
              const SizedBox(height: 30),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 240),
                child: Text(line, key: ValueKey(line), style: AppTheme.display(18), textAlign: TextAlign.center),
              ),
              const SizedBox(height: 10),
              Text(widget.subtitle, style: AppTheme.body(14, color: AppColors.muted, height: 1.4), textAlign: TextAlign.center),
              const SizedBox(height: 26),
              SizedBox(
                width: 230,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    minHeight: 6,
                    backgroundColor: Colors.white.withValues(alpha: 0.1),
                    valueColor: const AlwaysStoppedAnimation<Color>(AppColors.gold),
                  ),
                ),
              ),
              if (widget.onHide != null) ...[
                const SizedBox(height: 22),
                TextButton(
                  onPressed: widget.onHide,
                  child: Text('Hide', style: AppTheme.body(14, weight: FontWeight.w800, color: AppColors.primaryLight)),
                ),
                Text('Your request keeps running. We will show the result here.', style: AppTheme.body(12, color: AppColors.faint), textAlign: TextAlign.center),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}
