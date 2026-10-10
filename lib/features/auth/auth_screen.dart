import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';
import '../shell/home_shell.dart';
import 'captcha_sheet.dart';
import '../../main.dart' show googleAuthError;
import 'google_auth.dart';

/// Sign in / create account — the website's own /api/auth/login and /api/auth/register, so
/// bans, agent-account blocks, rate limits and the security check all apply exactly as on the site.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> with WidgetsBindingObserver {
  bool _signUp = false;
  bool _busy = false;
  bool _googleBusy = false;
  bool _showReferral = false;
  bool _hidePassword = true;
  String? _error;
  String? _notice;
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  final _referral = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    googleAuthError.addListener(_onGoogleError);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    googleAuthError.removeListener(_onGoogleError);
    _email.dispose();
    _password.dispose();
    _name.dispose();
    _referral.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await _attempt(null);
    } on ApiException catch (e) {
      if (e.captchaRequired && mounted) {
        final token = await runCaptcha(context);
        if (token == null) {
          _fail('Complete the security check to continue.');
          return;
        }
        try {
          await _attempt(token);
        } on ApiException catch (e2) {
          _fail(e2.message);
        }
      } else {
        _fail(e.message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _attempt(String? captchaToken) async {
    final email = _email.text.trim();
    final password = _password.text;
    final Map<String, dynamic> data;
    if (_signUp) {
      data = await ApiClient.instance.post('/api/auth/register', {
        'email': email,
        'password': password,
        'name': _name.text.trim(),
        if (_referral.text.trim().isNotEmpty) 'referralCode': _referral.text.trim(),
        if (captchaToken != null && captchaToken.isNotEmpty) 'captchaToken': captchaToken,
      }, auth: false);
    } else {
      data = await ApiClient.instance.post('/api/auth/login', {
        'email': email,
        'password': password,
        if (captchaToken != null && captchaToken.isNotEmpty) 'captchaToken': captchaToken,
      }, auth: false);
    }

    final session = data['session'];
    if (session is! Map<String, dynamic>) {
      // Sign-up with email confirmation: no session yet.
      if (mounted) {
        setState(() {
          _signUp = false;
          _notice = strOf(data['message'], 'Account created! Check your email to confirm, then sign in.');
        });
      }
      return;
    }
    await Session.instance.saveFromJson(session, user: data['user'] as Map<String, dynamic>?);
    await _enterApp();
  }

  /// Signed in (email or Google): load the player's data and open the app.
  Future<void> _enterApp() async {
    await AppState.instance.refreshAll().timeout(const Duration(seconds: 6), onTimeout: () {});
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 500),
        pageBuilder: (_, __, ___) => const HomeShell(),
        transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
      ),
      (_) => false,
    );
  }

  Future<void> _google() async {
    setState(() {
      _googleBusy = true;
      _error = null;
      _notice = null;
    });
    googleAuthError.value = null;
    try {
      // Opens Chrome; the result comes back to the app as a link (see main.dart).
      await GoogleAuth.start();
    } on ApiException catch (e) {
      _fail(e.message);
      if (mounted) setState(() => _googleBusy = false);
    } catch (_) {
      _fail('Could not open Google sign-in. Please try again.');
      if (mounted) setState(() => _googleBusy = false);
    }
  }

  void _onGoogleError() {
    final message = googleAuthError.value;
    if (message == null || !mounted) return;
    setState(() {
      _googleBusy = false;
      _error = message;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from the browser without finishing: let the player try again after a moment.
    if (state == AppLifecycleState.resumed && _googleBusy) {
      Future<void>.delayed(const Duration(seconds: 4), () {
        if (mounted && _googleBusy) setState(() => _googleBusy = false);
      });
    }
  }

  void _fail(String message) {
    if (mounted) setState(() => _error = message);
  }

  Future<void> _forgotPassword() async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      setState(() => _error = 'Enter your email first, then tap “Forgot password”.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ApiClient.instance.post('/api/auth/reset-password', {'email': email}, auth: false);
      if (mounted) setState(() => _notice = 'Check your email for a link to reset your password.');
    } on ApiException catch (e) {
      if (e.captchaRequired && mounted) {
        final token = await runCaptcha(context);
        if (token != null) {
          try {
            await ApiClient.instance.post('/api/auth/reset-password', {'email': email, 'captchaToken': token}, auth: false);
            if (mounted) setState(() => _notice = 'Check your email for a link to reset your password.');
          } on ApiException catch (e2) {
            _fail(e2.message);
          }
        }
      } else {
        _fail(e.message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _switchMode(bool signUp) {
    FocusScope.of(context).unfocus();
    setState(() {
      _signUp = signUp;
      _error = null;
      _notice = null;
      _showReferral = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final working = _busy || _googleBusy;
    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(22, 24, 22, 32),
              child: Form(
                key: _form,
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Center(child: Image.asset('assets/brand/logo_full.png', width: 250, fit: BoxFit.contain)),
                    const SizedBox(height: 18),
                    Text(_signUp ? 'Create your account' : 'Welcome back', style: AppTheme.display(28), textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    Text(
                      _signUp ? 'Free spins, rewards and instant play are a minute away.' : 'Sign in to your DazzlingWins account.',
                      style: AppTheme.body(14, color: AppColors.muted),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 26),

                    // ── Email form ───────────────────────────────────────────────
                    if (_signUp) ...[
                      TextFormField(
                        controller: _name,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.name],
                        decoration: const InputDecoration(labelText: 'Full name', prefixIcon: Icon(Icons.person_outline_rounded)),
                        validator: (v) => (v ?? '').trim().length < 2 ? 'Enter your full name' : null,
                      ),
                      const SizedBox(height: 14),
                    ],
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.email],
                      autocorrect: false,
                      decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.alternate_email_rounded)),
                      validator: (v) {
                        final s = (v ?? '').trim();
                        return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s) ? null : 'Enter a valid email';
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _password,
                      obscureText: _hidePassword,
                      textInputAction: TextInputAction.done,
                      autofillHints: [_signUp ? AutofillHints.newPassword : AutofillHints.password],
                      onChanged: (_) {
                        if (_signUp) setState(() {});
                      },
                      onFieldSubmitted: (_) {
                        if (!working) _submit();
                      },
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        suffixIcon: IconButton(
                          icon: Icon(_hidePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                          onPressed: () => setState(() => _hidePassword = !_hidePassword),
                        ),
                      ),
                      validator: (v) {
                        final value = v ?? '';
                        if (!_signUp) return value.isEmpty ? 'Enter your password' : null;
                        return PasswordStrength.of(value).meetsRules ? null : 'Password does not meet the rules below';
                      },
                    ),
                    if (_signUp) ...[
                      const SizedBox(height: 10),
                      _PasswordMeter(strength: PasswordStrength.of(_password.text)),
                      const SizedBox(height: 6),
                      if (_showReferral)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: TextFormField(
                            controller: _referral,
                            autocorrect: false,
                            decoration: const InputDecoration(labelText: 'Referral code (optional)', prefixIcon: Icon(Icons.card_giftcard_rounded)),
                          ),
                        )
                      else
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed: () => setState(() => _showReferral = true),
                            child: Text('Have a referral code?', style: AppTheme.body(13, weight: FontWeight.w700, color: AppColors.primaryLight)),
                          ),
                        ),
                    ] else
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: working ? null : _forgotPassword,
                          child: Text('Forgot password?', style: AppTheme.body(13, weight: FontWeight.w700, color: AppColors.primaryLight)),
                        ),
                      ),
                    const SizedBox(height: 8),
                    if (_error != null) _Banner(text: _error!, error: true),
                    if (_notice != null) _Banner(text: _notice!, error: false),
                    const SizedBox(height: 4),
                    PrimaryButton(label: _signUp ? 'Create account' : 'Sign in', loading: _busy, onPressed: _googleBusy ? null : _submit),

                    // ── Google ───────────────────────────────────────────────────
                    const SizedBox(height: 20),
                    Row(children: [
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text('or', style: AppTheme.body(12, color: AppColors.faint)),
                      ),
                      const Expanded(child: Divider()),
                    ]),
                    const SizedBox(height: 20),
                    _GoogleButton(
                      label: _signUp ? 'Sign up with Google' : 'Continue with Google',
                      loading: _googleBusy,
                      onPressed: working ? null : _google,
                    ),

                    // ── Switch between sign in / sign up ─────────────────────────
                    const SizedBox(height: 22),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(_signUp ? 'Already have an account?' : 'Don’t have an account?', style: AppTheme.body(14, color: AppColors.muted)),
                      TextButton(
                        onPressed: working ? null : () => _switchMode(!_signUp),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: const Size(0, 36),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(_signUp ? 'Sign in' : 'Sign up now', style: AppTheme.body(14, weight: FontWeight.w800, color: AppColors.gold)),
                      ),
                    ]),
                    const SizedBox(height: 14),
                    Text(
                      'By continuing you confirm you are 18+ and agree to the DazzlingWins Terms.',
                      style: AppTheme.body(12, color: AppColors.faint),
                      textAlign: TextAlign.center,
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Sign-up password rules: at least 8 characters with an upper-case letter, a lower-case letter,
/// a number and a special character. Score 0–5 = how many of the five rules are met.
class PasswordStrength {
  const PasswordStrength._(this.length, this.upper, this.lower, this.digit, this.special);

  factory PasswordStrength.of(String value) => PasswordStrength._(
        value.length >= 8,
        RegExp(r'[A-Z]').hasMatch(value),
        RegExp(r'[a-z]').hasMatch(value),
        RegExp(r'[0-9]').hasMatch(value),
        RegExp(r'[^A-Za-z0-9]').hasMatch(value),
      );

  final bool length;
  final bool upper;
  final bool lower;
  final bool digit;
  final bool special;

  int get score => [length, upper, lower, digit, special].where((ok) => ok).length;
  bool get meetsRules => score == 5;

  String get label => switch (score) {
        0 || 1 || 2 => 'Weak',
        3 => 'Fair',
        4 => 'Good',
        _ => 'Strong',
      };

  Color get color => switch (score) {
        0 || 1 || 2 => AppColors.danger,
        3 => AppColors.warning,
        4 => AppColors.gold,
        _ => AppColors.mint,
      };
}

/// Strength line + the checklist of rules, updating as the player types.
class _PasswordMeter extends StatelessWidget {
  const _PasswordMeter({required this.strength});
  final PasswordStrength strength;

  @override
  Widget build(BuildContext context) {
    final s = strength;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: Stack(children: [
              Container(height: 6, color: AppColors.surface3),
              AnimatedFractionallySizedBox(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                alignment: Alignment.centerLeft,
                widthFactor: s.score / 5,
                child: AnimatedContainer(duration: const Duration(milliseconds: 220), height: 6, color: s.color),
              ),
            ]),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 52,
          child: Text(s.label, textAlign: TextAlign.right, style: AppTheme.body(12, weight: FontWeight.w800, color: s.color)),
        ),
      ]),
      const SizedBox(height: 10),
      Wrap(spacing: 14, runSpacing: 6, children: [
        _Rule(ok: s.length, text: '8+ characters'),
        _Rule(ok: s.upper, text: 'Upper-case letter'),
        _Rule(ok: s.lower, text: 'Lower-case letter'),
        _Rule(ok: s.digit, text: 'Number'),
        _Rule(ok: s.special, text: 'Special character'),
      ]),
    ]);
  }
}

class _Rule extends StatelessWidget {
  const _Rule({required this.ok, required this.text});
  final bool ok;
  final String text;
  @override
  Widget build(BuildContext context) {
    final color = ok ? AppColors.mint : AppColors.faint;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(ok ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, size: 14, color: color),
      const SizedBox(width: 5),
      Text(text, style: AppTheme.body(12, weight: FontWeight.w600, color: color)),
    ]);
  }
}

class _GoogleButton extends StatelessWidget {
  const _GoogleButton({required this.label, required this.loading, required this.onPressed});
  final String label;
  final bool loading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onPressed,
        child: SizedBox(
          height: 56,
          child: Center(
            child: loading
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Color(0xFF1F1F1F)))
                : Row(mainAxisSize: MainAxisSize.min, children: [
                    Image.asset('assets/brand/google_g.png', width: 22, height: 22),
                    const SizedBox(width: 12),
                    Text(label, style: AppTheme.body(15, weight: FontWeight.w800, color: const Color(0xFF1F1F1F))),
                  ]),
          ),
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text, required this.error});
  final String text;
  final bool error;
  @override
  Widget build(BuildContext context) {
    final color = error ? AppColors.danger : AppColors.mint;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14), border: Border.all(color: color.withValues(alpha: 0.3))),
      child: Text(text, style: AppTheme.body(13, weight: FontWeight.w600, color: color)),
    );
  }
}
