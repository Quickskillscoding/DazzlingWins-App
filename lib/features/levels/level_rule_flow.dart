import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';
import 'x_rule.dart';

/// After sign-up: Date of Birth (if missing), then the one-time XP Rule / X Rule choice — the same
/// steps as the website. Neither popup can be closed or skipped. Only players whose profile has no
/// rule yet see it (players from before X Rule are on the XP rule already).
class LevelRuleFlow {
  static bool _running = false;

  static Future<void> ensure(BuildContext context) async {
    if (_running) return;
    _running = true;
    try {
      await AppState.instance.refreshProfile();
      final profile = AppState.instance.profile;
      // Before docs/supabase-x-rule.sql runs, levelRuleReady is false: nothing is asked.
      if (profile['levelRuleReady'] != true || profile['levelRule'] != null) return;
      if (!context.mounted) return;
      if (profile['dateOfBirth'] == null) {
        await showAppPopup<void>(context, dismissible: false, blur: true, builder: (_) => const _ProfileStep());
      }
      if (!context.mounted) return;
      await showAppPopup<void>(context, dismissible: false, blur: true, maxWidth: 520, builder: (_) => const _RuleStep());
      await AppState.instance.refreshProfile();
    } catch (_) {
      // Asked again next time the app opens.
    } finally {
      _running = false;
    }
  }
}

class _ProfileStep extends StatefulWidget {
  const _ProfileStep();

  @override
  State<_ProfileStep> createState() => _ProfileStepState();
}

class _ProfileStepState extends State<_ProfileStep> {
  String _gender = '';
  DateTime? _dob;
  bool _saving = false;
  String? _error;

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year - 25, now.month, now.day),
      firstDate: DateTime(now.year - 100),
      lastDate: now,
    );
    if (picked != null) setState(() => _dob = picked);
  }

  int _age(DateTime born) {
    final now = DateTime.now();
    var age = now.year - born.year;
    if (now.month < born.month || (now.month == born.month && now.day < born.day)) age -= 1;
    return age;
  }

  Future<void> _next() async {
    if (_gender.isEmpty) return setState(() => _error = 'Please choose your gender.');
    if (_dob == null) return setState(() => _error = 'Please enter your date of birth.');
    if (_age(_dob!) < 18) return setState(() => _error = 'You must be at least 18 years old.');
    setState(() {
      _saving = true;
      _error = null;
    });
    final d = _dob!;
    final iso = '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    try {
      await ApiClient.instance.patch('/api/profile', {'gender': _gender, 'dateOfBirth': iso});
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save your profile.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dobText = _dob == null ? 'Select your date of birth' : '${_dob!.month}/${_dob!.day}/${_dob!.year}';
    return PopScope(
      canPop: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Complete your profile', style: AppTheme.display(22)),
          const SizedBox(height: 6),
          Text('Tell us a little about you to continue.', style: AppTheme.body(13, color: AppColors.muted)),
          const SizedBox(height: 18),
          Text('Gender', style: AppTheme.body(12.5, weight: FontWeight.w700)),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final g in const ['Male', 'Female', 'Other'])
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: _Choice(label: g, active: _gender == g, onTap: () => setState(() => _gender = g)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Date of Birth', style: AppTheme.body(12.5, weight: FontWeight.w700)),
          const SizedBox(height: 8),
          InkWell(
            onTap: _pickDate,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.stroke)),
              child: Row(children: [
                const Icon(Icons.calendar_month_rounded, size: 18, color: AppColors.muted),
                const SizedBox(width: 10),
                Text(dobText, style: AppTheme.body(14, color: _dob == null ? AppColors.faint : AppColors.text)),
              ]),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: AppTheme.body(12.5, color: AppColors.danger, weight: FontWeight.w600)),
          ],
          const SizedBox(height: 18),
          PrimaryButton(label: 'Next', gold: true, loading: _saving, onPressed: _next),
        ],
      ),
    );
  }
}

class _RuleStep extends StatefulWidget {
  const _RuleStep();

  @override
  State<_RuleStep> createState() => _RuleStepState();
}

class _RuleStepState extends State<_RuleStep> {
  String? _rule;
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    if (_rule == null) return setState(() => _error = 'Choose XP Rule or X Rule to continue.');
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ApiClient.instance.post('/api/profile/level-rule', {'rule': _rule});
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save your choice.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.82),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('ONE LAST STEP', style: AppTheme.body(11, color: AppColors.gold, weight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('Choose your level rule', style: AppTheme.display(22)),
              const SizedBox(height: 6),
              Text('This applies to your profile and cannot be changed later.', style: AppTheme.body(13, color: AppColors.muted)),
              const SizedBox(height: 16),
              _RuleCard(
                title: 'XP Rule',
                icon: Icons.auto_awesome_rounded,
                summary: kXpRuleSummary,
                points: const [
                  'Levels grow with XP (Bronze, Silver, Gold and up).',
                  'Redeem limits follow your XP level.',
                  'Score above your limit turns into XP.',
                ],
                active: _rule == 'xp',
                onTap: () => setState(() => _rule = 'xp'),
              ),
              const SizedBox(height: 10),
              _RuleCard(
                title: 'X Rule',
                icon: Icons.trending_up_rounded,
                summary: kXRuleSummary,
                points: [
                  ...xRuleLevelLines(),
                  'Example: deposit \$5 and win \$50 at Level 0 → claim \$15 to \$25; the rest raises your level.',
                ],
                active: _rule == 'x',
                onTap: () => setState(() => _rule = 'x'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: AppTheme.body(12.5, color: AppColors.danger, weight: FontWeight.w600)),
              ],
              const SizedBox(height: 16),
              PrimaryButton(
                label: _rule == null ? 'Choose a rule' : 'Continue with ${_rule == 'x' ? 'X Rule' : 'XP Rule'}',
                gold: true,
                loading: _saving,
                onPressed: _rule == null ? null : _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({required this.label, required this.active, required this.onTap});
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? AppColors.gold : AppColors.surface2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: active ? AppColors.gold : AppColors.stroke),
        ),
        child: Text(label, style: AppTheme.body(13.5, weight: FontWeight.w800, color: active ? const Color(0xFF1A1200) : AppColors.text)),
      ),
    );
  }
}

class _RuleCard extends StatelessWidget {
  const _RuleCard({required this.title, required this.icon, required this.summary, required this.points, required this.active, required this.onTap});
  final String title;
  final IconData icon;
  final String summary;
  final List<String> points;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: active ? AppColors.gold.withValues(alpha: 0.1) : AppColors.surface2,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: active ? AppColors.gold : AppColors.stroke, width: active ? 1.6 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, size: 20, color: AppColors.gold),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: AppTheme.display(17))),
              if (active) const Icon(Icons.check_circle_rounded, color: AppColors.gold, size: 22),
            ]),
            const SizedBox(height: 6),
            Text(summary, style: AppTheme.body(12.5, color: AppColors.muted, height: 1.4)),
            const SizedBox(height: 8),
            for (final p in points)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Padding(padding: EdgeInsets.only(top: 6), child: Icon(Icons.circle, size: 5, color: AppColors.gold)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(p, style: AppTheme.body(12, height: 1.35))),
                ]),
              ),
          ],
        ),
      ),
    );
  }
}
