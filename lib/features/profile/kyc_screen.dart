import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/theme.dart';
import '../../widgets/image_pick.dart';
import '../../widgets/ui.dart';

/// KYC: legal name, optional SSN, selfie and driving-license front/back — the website's /api/kyc.
/// The SSN is sent over HTTPS and encrypted by the server before it is stored.
class KycScreen extends StatefulWidget {
  const KycScreen({super.key});
  @override
  State<KycScreen> createState() => _KycScreenState();
}

class _KycScreenState extends State<KycScreen> {
  Map<String, dynamic>? _summary;
  String? _error;
  bool _busy = false;
  final _name = TextEditingController();
  final _ssn = TextEditingController();
  XFile? _selfie;
  XFile? _front;
  XFile? _back;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _ssn.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final d = await ApiClient.instance.get('/api/kyc');
      if (!mounted) return;
      setState(() {
        _summary = d;
        if (_name.text.isEmpty) _name.text = strOf(d['legalName']);
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  /// Same rules as the website (lib/kyc-ssn.ts): 9 digits; area not 000/666/9xx; group not 00; serial not 0000.
  static bool validSsn(String raw) {
    final d = raw.replaceAll(RegExp(r'\D'), '');
    if (!RegExp(r'^\d{3}-?\d{2}-?\d{4}$').hasMatch(raw.trim()) || d.length != 9) return false;
    final area = d.substring(0, 3), group = d.substring(3, 5), serial = d.substring(5);
    if (area == '000' || area == '666' || area.compareTo('900') >= 0) return false;
    return group != '00' && serial != '0000';
  }

  Future<void> _submit() async {
    if (_name.text.trim().length < 2) {
      toast(context, 'Enter your full name as on your license.', error: true);
      return;
    }
    if (_ssn.text.trim().isNotEmpty && !validSsn(_ssn.text)) {
      toast(context, 'Enter a valid 9-digit Social Security Number (e.g. 123-45-6789).', error: true);
      return;
    }
    if (_selfie == null || _front == null || _back == null) {
      toast(context, 'Upload your selfie and both sides of your license.', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final d = await ApiClient.instance.multipart(
        '/api/kyc',
        {'legalName': _name.text.trim(), if (_ssn.text.trim().isNotEmpty) 'ssn': _ssn.text.trim()},
        [
          UploadFile('selfie', _selfie!.path, filename: _selfie!.name),
          UploadFile('licenseFront', _front!.path, filename: _front!.name),
          UploadFile('licenseBack', _back!.path, filename: _back!.name),
        ],
      );
      _ssn.clear();
      await AppState.instance.refreshProfile().catchError((_) {});
      if (!mounted) return;
      setState(() => _summary = d);
      toast(context, 'Submitted! We will review your documents shortly.');
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _summary;
    final status = strOf(s?['status'], 'none');
    final canSubmit = s?['canSubmit'] == true;
    return Scaffold(
      appBar: AppBar(title: const Text('Account verification')),
      body: AppBackground(
        child: s == null
            ? Center(child: _error != null ? ErrorRetry(message: _error!, onRetry: _load) : const CircularProgressIndicator())
            : ListView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
                children: [
                  if (s['verified'] == true)
                    const _Status(icon: Icons.verified_rounded, color: AppColors.mint, text: 'Your account is verified.'),
                  if (status == 'pending') const _Status(icon: Icons.hourglass_top_rounded, color: AppColors.warning, text: 'Your documents are waiting for review.'),
                  if (status == 'rejected')
                    _Status(
                      icon: Icons.error_outline_rounded,
                      color: AppColors.danger,
                      text: strOf(s['adminNote']).isEmpty ? 'Your last request was rejected. Upload clearer documents and submit again.' : 'Rejected: ${strOf(s['adminNote'])}',
                    ),
                  if (canSubmit) ...[
                    Text('Verify once to unlock Spin & Win, faster withdrawals and a 350 XP bonus.', style: AppTheme.body(14, color: AppColors.muted)),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'Full name *', hintText: 'Name as on your license'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _ssn,
                      keyboardType: TextInputType.number,
                      obscureText: true,
                      autocorrect: false,
                      enableSuggestions: false,
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d-]')), LengthLimitingTextInputFormatter(11)],
                      decoration: const InputDecoration(
                        labelText: 'Social Security Number (optional)',
                        hintText: '123-45-6789',
                        helperText: 'Encrypted and only visible to our verification team.',
                      ),
                    ),
                    const SizedBox(height: 16),
                    PhotoField(label: 'Selfie', required: true, file: _selfie, onPick: () => _pick((f) => _selfie = f)),
                    const SizedBox(height: 14),
                    PhotoField(label: 'Driving license front', required: true, file: _front, onPick: () => _pick((f) => _front = f)),
                    const SizedBox(height: 14),
                    PhotoField(label: 'Driving license back', required: true, file: _back, onPick: () => _pick((f) => _back = f)),
                    const SizedBox(height: 22),
                    PrimaryButton(label: 'Submit verification', gold: true, loading: _busy, onPressed: _submit),
                  ],
                ],
              ),
      ),
    );
  }

  Future<void> _pick(void Function(XFile) assign) async {
    final f = await pickPhoto(context);
    if (f != null && mounted) setState(() => assign(f));
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.icon, required this.color, required this.text});
  final IconData icon;
  final Color color;
  final String text;
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16), border: Border.all(color: color.withValues(alpha: 0.35))),
      child: Row(children: [
        Icon(icon, color: color),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: AppTheme.body(14, weight: FontWeight.w700, color: color))),
      ]),
    );
  }
}
