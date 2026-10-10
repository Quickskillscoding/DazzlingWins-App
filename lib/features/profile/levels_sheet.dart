import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';

/// Level perks — the admin-editable table from /api/xp-levels (same as the website's dialog).
Future<void> showLevelsSheet(BuildContext context) {
  return showAppPopup<void>(
    context,
    builder: (_) {
      final s = AppState.instance;
      final current = s.progress.current.level;
      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 28),
          children: [
            Text('Level perks & rewards', style: AppTheme.display(20)),
            const SizedBox(height: 14),
            for (final l in s.levels)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Panel(
                  border: l.level == current ? AppColors.gold : null,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Text(l.name, style: AppTheme.display(17, color: l.level == current ? AppColors.gold : AppColors.text)),
                      const SizedBox(width: 8),
                      if (l.level == current) const StatusChip('Current'),
                      const Spacer(),
                      Text('${compactInt(l.xpRequired)} XP', style: AppTheme.body(12, color: AppColors.muted)),
                    ]),
                    const SizedBox(height: 10),
                    _Perk('Max redeem', l.starterCashCap != null ? '${money(l.starterCashCap!)} cash' : '${money(l.maxRedeem)}/day'),
                    _Perk('Max transfer', '${money(l.maxTransfer)}/day'),
                    _Perk('Bonus points', '+${compactInt(l.bonusPoints)}'),
                  ]),
                ),
              ),
          ],
        ),
      );
    },
  );
}

class _Perk extends StatelessWidget {
  const _Perk(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Text(label, style: AppTheme.body(13, color: AppColors.muted)),
        const Spacer(),
        Text(value, style: AppTheme.body(13, weight: FontWeight.w800)),
      ]),
    );
  }
}
