import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';
import '../profile/kyc_screen.dart';
import '../wallet/deposit_screen.dart';

/// Same wheel as the website: five cash slices in this exact order (lib/spin-rules.ts
/// SPIN_WHEEL_PRIZES). The SERVER draws the slice, credits the Bonus Wallet and enforces every
/// rule (24 h cooldown, 5 per cycle, $5 deposit unlock, $1 extra spin, mandatory KYC).
const List<int> kSpinPrizes = [1, 4, 2, 5, 3];

class SpinScreen extends StatefulWidget {
  const SpinScreen({super.key});
  @override
  State<SpinScreen> createState() => _SpinScreenState();
}

class _SpinScreenState extends State<SpinScreen> with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 5200));
  double _from = 0;
  double _to = 0;
  bool _busy = false;
  bool _offerPaid = false;
  String? _message;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  double get _angle => _from + (_to - _from) * Curves.easeOutQuart.transform(_c.value);

  Future<void> _spin({bool paid = false}) async {
    if (_busy) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _busy = true;
      _message = null;
      _offerPaid = false;
    });
    try {
      final d = await ApiClient.instance.post('/api/wallet', paid ? {'paid': true} : {});
      final segment = math.max(0, math.min(kSpinPrizes.length - 1, numOf(d['segment']).toInt()));
      final amount = numOf(d['amount'], kSpinPrizes[segment].toDouble());
      await _animateTo(segment);
      AppState.instance.applyWallet(d);
      if (mounted) _celebrate(amount);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.kycRequired) {
        _askKyc(e.message);
      } else {
        final canBuy = e.data['locked'] == true && AppState.instance.freeSpinUnlockedByDeposit && !paid;
        setState(() {
          _message = e.message;
          _offerPaid = canBuy;
        });
      }
      await AppState.instance.refreshWallet().catchError((_) {});
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _animateTo(int segment) async {
    const n = 5;
    const slice = 2 * math.pi / n;
    final current = _angle % (2 * math.pi);
    // Slice i is centred at (i + 0.5) * slice from the top; bring it under the top pointer.
    final target = (2 * math.pi - (segment + 0.5) * slice) % (2 * math.pi);
    var delta = target - current;
    if (delta < 0) delta += 2 * math.pi;
    _from = _angle;
    _to = _from + 6 * 2 * math.pi + delta;
    _c.value = 0;
    await _c.forward();
    HapticFeedback.heavyImpact();
  }

  void _celebrate(double amount) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        child: Padding(
          padding: const EdgeInsets.all(26),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 76,
              height: 76,
              decoration: const BoxDecoration(gradient: AppColors.goldGradient, shape: BoxShape.circle),
              child: const Icon(Icons.emoji_events_rounded, size: 40, color: Color(0xFF1A1200)),
            ),
            const SizedBox(height: 16),
            Text('You won', style: AppTheme.body(14, color: AppColors.muted)),
            Text(money(amount), style: AppTheme.display(44, weight: FontWeight.w800, color: AppColors.goldLight)),
            const SizedBox(height: 6),
            Text('Added to your Bonus Wallet', style: AppTheme.body(13, color: AppColors.mint)),
            const SizedBox(height: 20),
            PrimaryButton(label: 'Awesome', gold: true, onPressed: () => Navigator.of(ctx).pop()),
          ]),
        ),
      ),
    );
  }

  void _askKyc(String message) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(gradient: AppColors.goldGradient, borderRadius: BorderRadius.circular(22)),
              child: const Icon(Icons.lock_rounded, size: 34, color: Color(0xFF1A1200)),
            ),
            const SizedBox(height: 14),
            Text('Verify to spin', style: AppTheme.display(22)),
            const SizedBox(height: 6),
            Text(
              AppState.instance.kycStatus == 'pending'
                  ? 'Your documents are being reviewed. The wheel unlocks as soon as your KYC is approved.'
                  : message,
              style: AppTheme.body(14, color: AppColors.muted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            if (AppState.instance.kycStatus != 'pending')
              PrimaryButton(
                label: 'Complete KYC',
                gold: true,
                onPressed: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const KycScreen()));
                },
              ),
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Maybe later')),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return AppBackground(
      child: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: AppState.instance,
          builder: (context, _) {
            final s = AppState.instance;
            return ListView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 130),
              children: [
                Text('Spin & Win', style: AppTheme.display(28)),
                const SizedBox(height: 4),
                Text('One free spin every 24 hours. Every slice pays real Bonus Wallet cash.', style: AppTheme.body(13, color: AppColors.muted)),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(child: _Stat(label: 'Free spins left', value: s.freeSpinsLeft == null ? '—' : '${s.freeSpinsLeft}')),
                  const SizedBox(width: 10),
                  Expanded(child: _Stat(label: 'Bonus Wallet', value: money(s.bonusWallet), gold: true)),
                ]),
                const SizedBox(height: 26),
                Center(
                  child: SizedBox(
                    width: 310,
                    height: 330,
                    child: Stack(alignment: Alignment.topCenter, children: [
                      Positioned(
                        top: 20,
                        child: Container(
                          width: 300,
                          height: 300,
                          decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [
                            BoxShadow(color: AppColors.primary.withValues(alpha: 0.45), blurRadius: 50),
                          ]),
                          child: RepaintBoundary(
                            child: AnimatedBuilder(
                              animation: _c,
                              builder: (_, __) => Transform.rotate(angle: _angle, child: const CustomPaint(painter: _WheelPainter())),
                            ),
                          ),
                        ),
                      ),
                      const Positioned(top: 0, child: _Pointer()),
                      Positioned(
                        top: 135,
                        child: GestureDetector(
                          onTap: _busy ? null : () => _spin(),
                          child: Container(
                            width: 90,
                            height: 90,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: AppColors.goldGradient,
                              border: Border.all(color: AppColors.bg, width: 5),
                              boxShadow: [BoxShadow(color: AppColors.gold.withValues(alpha: 0.5), blurRadius: 20)],
                            ),
                            child: Center(
                              child: _busy
                                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.6, color: Color(0xFF1A1200)))
                                  : Text('SPIN', style: AppTheme.display(18, weight: FontWeight.w800, color: const Color(0xFF1A1200))),
                            ),
                          ),
                        ),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(height: 20),
                if (_message != null)
                  Panel(
                    border: AppColors.warning.withValues(alpha: 0.4),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Row(children: [
                        const Icon(Icons.info_outline_rounded, color: AppColors.warning, size: 20),
                        const SizedBox(width: 8),
                        Expanded(child: Text(_message!, style: AppTheme.body(13, weight: FontWeight.w600, color: AppColors.warning))),
                      ]),
                      if (_offerPaid) ...[
                        const SizedBox(height: 12),
                        PrimaryButton(label: 'Spin again for \$1', gold: true, onPressed: () => _spin(paid: true)),
                      ] else ...[
                        const SizedBox(height: 12),
                        GhostButton(
                          label: 'Deposit to unlock more spins',
                          icon: Icons.south_west_rounded,
                          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DepositScreen())),
                        ),
                      ],
                    ]),
                  )
                else
                  PrimaryButton(label: 'Spin the wheel', icon: Icons.casino_rounded, gold: true, loading: _busy, onPressed: () => _spin()),
                const SizedBox(height: 14),
                if (s.lastFreeSpinAt != null)
                  Text('Last free spin: ${shortDateTime(s.lastFreeSpinAt)}', style: AppTheme.body(12, color: AppColors.faint), textAlign: TextAlign.center),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.gold = false});
  final String label;
  final String value;
  final bool gold;
  @override
  Widget build(BuildContext context) {
    return Panel(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: AppTheme.body(12, color: AppColors.muted)),
        const SizedBox(height: 4),
        Text(value, style: AppTheme.display(20, color: gold ? AppColors.gold : AppColors.text)),
      ]),
    );
  }
}

class _Pointer extends StatelessWidget {
  const _Pointer();
  @override
  Widget build(BuildContext context) {
    return const CustomPaint(size: Size(34, 40), painter: _PointerPainter());
  }
}

class _PointerPainter extends CustomPainter {
  const _PointerPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawShadow(path, Colors.black, 6, true);
    canvas.drawPath(path, Paint()..shader = AppColors.goldGradient.createShader(Offset.zero & size));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _WheelPainter extends CustomPainter {
  const _WheelPainter();
  static const _colors = [Color(0xFF2A1E5C), Color(0xFF5B3DF5), Color(0xFF1C1640), Color(0xFF7C5CFF), Color(0xFF231A52)];

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final rect = Rect.fromCircle(center: c, radius: r - 10);
    const n = 5;
    const slice = 2 * math.pi / n;
    for (var i = 0; i < n; i++) {
      final start = -math.pi / 2 + i * slice;
      canvas.drawArc(rect, start, slice, true, Paint()..color = _colors[i]);
      canvas.drawArc(rect, start, slice, true, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = AppColors.gold.withValues(alpha: 0.6));
      // Label
      final mid = start + slice / 2;
      final labelPos = c + Offset(math.cos(mid), math.sin(mid)) * (r * 0.62);
      canvas.save();
      canvas.translate(labelPos.dx, labelPos.dy);
      canvas.rotate(mid + math.pi / 2);
      final tp = TextPainter(
        text: TextSpan(
          text: '\$${kSpinPrizes[i]}',
          style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: AppColors.goldLight),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }
    // Rim with light bulbs
    canvas.drawCircle(c, r - 5, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..shader = AppColors.goldGradient.createShader(Rect.fromCircle(center: c, radius: r)));
    for (var i = 0; i < 20; i++) {
      final a = i * 2 * math.pi / 20;
      canvas.drawCircle(c + Offset(math.cos(a), math.sin(a)) * (r - 5), 3, Paint()..color = i.isEven ? Colors.white : AppColors.bg);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
