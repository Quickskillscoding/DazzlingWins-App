import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';
import '../shell/home_shell.dart';
import 'captcha_sheet.dart';

/// Sign in / create account — the website's own /api/auth/login and /api/auth/register, so
/// bans, agent-account blocks, rate limits and the security check all apply exactly as on the site.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _signUp = false;
  bool _busy = false;
  bool _hidePassword = true;
  String? _error;
  String? _notice;
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  final _referral = TextEditingController();

  @override
  void dispose() {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(22, 24, 22, 32),
              child: Form(
                key: _form,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Center(child: Image.asset('assets/brand/logo_full.png', width: 250, fit: BoxFit.contain)),
                  const SizedBox(height: 18),
                  Text(_signUp ? 'Create your account' : 'Welcome back',
                      style: AppTheme.display(28), textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  Text(
                    _signUp ? 'Free spins, rewards and instant play are a minute away.' : 'Sign in to your DazzlingWins account.',
                    style: AppTheme.body(14, color: AppColors.muted),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 26),
                  _Segment(
                    signUp: _signUp,
                    onChanged: (v) => setState(() {
                      _signUp = v;
                      _error = null;
                      _notice = null;
                    }),
                  ),
                  const SizedBox(height: 20),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    child: _signUp
                        ? Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: TextFormField(
                              controller: _name,
                              textCapitalization: TextCapitalization.words,
                              decoration: const InputDecoration(labelText: 'Full name', prefixIcon: Icon(Icons.person_outline_rounded)),
                              validator: (v) => _signUp && (v ?? '').trim().length < 2 ? 'Enter your name' : null,
                            ),
                          )
                        : const SizedBox(width: double.infinity),
                  ),
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
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
                    autofillHints: [_signUp ? AutofillHints.newPassword : AutofillHints.password],
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(
                        icon: Icon(_hidePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                        onPressed: () => setState(() => _hidePassword = !_hidePassword),
                      ),
                    ),
                    validator: (v) => (v ?? '').length < (_signUp ? 8 : 1)
                        ? (_signUp ? 'Use at least 8 characters' : 'Enter your password')
                        : null,
                  ),
                  if (_signUp) ...[
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _referral,
                      autocorrect: false,
                      decoration: const InputDecoration(labelText: 'Referral code (optional)', prefixIcon: Icon(Icons.card_giftcard_rounded)),
                    ),
                  ],
                  if (!_signUp)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _busy ? null : _forgotPassword,
                        child: Text('Forgot password?', style: AppTheme.body(13, weight: FontWeight.w700, color: AppColors.primaryLight)),
                      ),
                    ),
                  const SizedBox(height: 10),
                  if (_error != null) _Banner(text: _error!, error: true),
                  if (_notice != null) _Banner(text: _notice!, error: false),
                  const SizedBox(height: 8),
                  PrimaryButton(label: _signUp ? 'Create account' : 'Sign in', loading: _busy, onPressed: _submit),
                  const SizedBox(height: 22),
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
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({required this.signUp, required this.onChanged});
  final bool signUp;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(18), border: Border.all(color: AppColors.stroke)),
      child: Stack(children: [
        AnimatedAlign(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          alignment: signUp ? Alignment.centerRight : Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: 0.5,
            child: DecoratedBox(decoration: BoxDecoration(gradient: AppColors.primaryGradient, borderRadius: BorderRadius.circular(14))),
          ),
        ),
        Row(children: [
          for (final item in const [(false, 'Sign in'), (true, 'Create account')])
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(item.$1),
                child: Center(
                  child: Text(item.$2,
                      style: AppTheme.body(14, weight: FontWeight.w800, color: signUp == item.$1 ? Colors.white : AppColors.muted)),
                ),
              ),
            ),
        ]),
      ]),
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
