import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/theme.dart';
import '../../widgets/image_pick.dart';
import '../../widgets/ui.dart';
import '../games/game_sheet.dart' show AmountField;
import 'payment_catalog.dart';

/// Deposit: pick a method the admin enabled, pay to its details/QR, then submit the amount,
/// the method's proof fields, an optional promo code and the payment screenshot.
/// Same endpoint and checks as the website (/api/deposits).
class DepositScreen extends StatefulWidget {
  const DepositScreen({super.key});
  @override
  State<DepositScreen> createState() => _DepositScreenState();
}

class _DepositScreenState extends State<DepositScreen> {
  List<Map<String, dynamic>> _methods = [];
  Map<String, CatalogEntry> _catalog = {};
  Map<String, dynamic>? _method;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        ApiClient.instance.get('/api/payment-methods'),
        PaymentCatalog.load().then((c) => <String, dynamic>{'c': c}),
      ]);
      if (!mounted) return;
      setState(() {
        _methods = listOf(results[0]['methods']);
        _catalog = results[1]['c'] as Map<String, CatalogEntry>;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_method == null ? 'Deposit' : 'Pay with ${strOf(_method!['label'])}')),
      body: AppBackground(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(child: ErrorRetry(message: _error!, onRetry: _load))
                  : _method == null
                      ? _MethodList(methods: _methods, catalog: _catalog, onPick: (m) => setState(() => _method = m))
                      : _DepositForm(
                          key: ValueKey(_method!['id']),
                          method: _method!,
                          entry: _catalog[strOf(_method!['slug'])],
                          onBack: () => setState(() => _method = null),
                        ),
        ),
      ),
    );
  }
}

class _MethodList extends StatelessWidget {
  const _MethodList({required this.methods, required this.catalog, required this.onPick});
  final List<Map<String, dynamic>> methods;
  final Map<String, CatalogEntry> catalog;
  final ValueChanged<Map<String, dynamic>> onPick;

  @override
  Widget build(BuildContext context) {
    if (methods.isEmpty) {
      return const EmptyState(icon: Icons.credit_card_off_rounded, title: 'No deposit methods right now', subtitle: 'Please check back soon.');
    }
    return ListView.separated(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
      itemCount: methods.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text('Choose how you want to pay', style: AppTheme.body(14, color: AppColors.muted)),
          );
        }
        final m = methods[i - 1];
        final entry = catalog[strOf(m['slug'])];
        final bonus = numOf(m['bonus_percent']);
        return Panel(
          onTap: () => onPick(m),
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Container(
              width: 46,
              height: 46,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
              child: entry == null ? const Icon(Icons.payments_outlined, color: Colors.black54) : NetImage(entry.image, fit: BoxFit.contain, cacheWidth: 120),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(strOf(m['label']), style: AppTheme.body(15, weight: FontWeight.w800)),
                if (bonus > 0) Text('+${bonus.toStringAsFixed(bonus % 1 == 0 ? 0 : 1)}% bonus', style: AppTheme.body(12, weight: FontWeight.w700, color: AppColors.mint)),
              ]),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
          ]),
        );
      },
    );
  }
}

class _DepositForm extends StatefulWidget {
  const _DepositForm({super.key, required this.method, required this.entry, required this.onBack});
  final Map<String, dynamic> method;
  final CatalogEntry? entry;
  final VoidCallback onBack;
  @override
  State<_DepositForm> createState() => _DepositFormState();
}

class _DepositFormState extends State<_DepositForm> {
  final _amount = TextEditingController();
  final _promo = TextEditingController();
  final Map<String, TextEditingController> _proof = {};
  XFile? _screenshot;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    for (final f in widget.entry?.proofFields ?? const <PayField>[]) {
      _proof[f.key] = TextEditingController();
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _promo.dispose();
    for (final c in _proof.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    final amount = double.tryParse(_amount.text) ?? 0;
    if (amount <= 0) {
      toast(context, 'Enter the amount you sent.', error: true);
      return;
    }
    for (final f in widget.entry?.proofFields ?? const <PayField>[]) {
      if (f.required && (_proof[f.key]?.text.trim() ?? '').isEmpty) {
        toast(context, 'Enter ${f.label}.', error: true);
        return;
      }
    }
    if (_screenshot == null) {
      toast(context, 'Upload a screenshot of your payment.', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final details = {for (final e in _proof.entries) e.key: e.value.text.trim()};
      final d = await ApiClient.instance.multipart(
        '/api/deposits',
        {
          'methodId': strOf(widget.method['id']),
          'amount': amount.toStringAsFixed(2),
          'details': jsonEncode(details),
          if (_promo.text.trim().isNotEmpty) 'promoCode': _promo.text.trim(),
        },
        [UploadFile('proof', _screenshot!.path, filename: _screenshot!.name)],
      );
      await AppState.instance.refreshWallet().catchError((_) {});
      if (!mounted) return;
      final promoError = strOf(d['promoError']);
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.check_circle_rounded, color: AppColors.mint, size: 48),
          title: Text('Deposit submitted', style: AppTheme.display(20)),
          content: Text(
            'We are checking your payment. Your wallet is credited as soon as it is approved.'
            '${promoError.isNotEmpty ? '\n\nPromo code: $promoError' : ''}',
            style: AppTheme.body(14, color: AppColors.muted),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done'))],
        ),
      );
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final details = mapOf(widget.method['details']);
    final qr = strOf(widget.method['qr_url']);
    final instructions = strOf(widget.method['instructions']);
    final adminFields = widget.entry?.adminFields ?? const <PayField>[];
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 40),
      children: [
        TextButton.icon(
          onPressed: widget.onBack,
          icon: const Icon(Icons.arrow_back_rounded, size: 18),
          label: const Text('Other methods'),
          style: TextButton.styleFrom(alignment: Alignment.centerLeft, foregroundColor: AppColors.muted),
        ),
        Panel(
          gradient: AppColors.heroGradient,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('1. Send your payment to', style: AppTheme.display(15)),
            const SizedBox(height: 10),
            for (final f in adminFields)
              if (strOf(details[f.key]).isNotEmpty) _DetailRow(label: f.label, value: strOf(details[f.key]), link: f.type == 'url'),
            if (qr.isNotEmpty) ...[
              const SizedBox(height: 10),
              Center(
                child: Container(
                  width: 190,
                  height: 190,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
                  child: NetImage(qr, fit: BoxFit.contain),
                ),
              ),
            ],
            if (instructions.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(instructions, style: AppTheme.body(13, color: AppColors.muted)),
            ],
          ]),
        ),
        const SizedBox(height: 18),
        Text('2. Tell us about your payment', style: AppTheme.display(15)),
        const SizedBox(height: 12),
        AmountField(controller: _amount, label: 'Amount you sent'),
        for (final f in widget.entry?.proofFields ?? const <PayField>[]) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _proof[f.key],
            keyboardType: f.type == 'email' ? TextInputType.emailAddress : TextInputType.text,
            decoration: InputDecoration(labelText: f.required ? '${f.label} *' : f.label, hintText: f.placeholder),
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _promo,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(labelText: 'Promo code (optional)', prefixIcon: Icon(Icons.local_offer_outlined)),
        ),
        const SizedBox(height: 16),
        PhotoField(
          label: 'Payment screenshot',
          required: true,
          file: _screenshot,
          onPick: () async {
            final f = await pickPhoto(context);
            if (f != null) setState(() => _screenshot = f);
          },
        ),
        const SizedBox(height: 22),
        PrimaryButton(label: 'Submit deposit', gold: true, loading: _busy, onPressed: _submit),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value, this.link = false});
  final String label;
  final String value;
  final bool link;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: AppTheme.body(12, color: AppColors.muted)),
            const SizedBox(height: 2),
            Text(value, style: AppTheme.body(15, weight: FontWeight.w800, color: AppColors.goldLight)),
          ]),
        ),
        if (link && value.startsWith('https://'))
          IconButton(
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            onPressed: () => launchUrl(Uri.parse(value), mode: LaunchMode.externalApplication),
          ),
        IconButton(
          icon: const Icon(Icons.copy_rounded, size: 18),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: value));
            toast(context, '$label copied');
          },
        ),
      ]),
    );
  }
}
