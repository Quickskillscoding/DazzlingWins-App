import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../widgets/image_pick.dart';
import '../../widgets/ui.dart';
import '../games/game_sheet.dart' show AmountField;
import 'payment_catalog.dart';

/// Withdraw from the Current Wallet to the player's own account. Same endpoint and rules as the
/// website (/api/withdraws): method minimum, daily cash limit, optional tip, payout QR.
class WithdrawScreen extends StatefulWidget {
  const WithdrawScreen({super.key});
  @override
  State<WithdrawScreen> createState() => _WithdrawScreenState();
}

class _WithdrawScreenState extends State<WithdrawScreen> {
  List<Map<String, dynamic>> _methods = [];
  Map<String, CatalogEntry> _catalog = {};
  Map<String, dynamic> _limits = {};
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
        ApiClient.instance.get('/api/withdraw-methods'),
        ApiClient.instance.get('/api/withdraws').catchError((_) => <String, dynamic>{}),
        PaymentCatalog.load().then((c) => <String, dynamic>{'c': c}),
      ]);
      if (!mounted) return;
      setState(() {
        _methods = listOf(results[0]['methods']);
        _limits = results[1];
        _catalog = results[2]['c'] as Map<String, CatalogEntry>;
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
      appBar: AppBar(title: const Text('Withdraw')),
      body: AppBackground(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: ErrorRetry(message: _error!, onRetry: _load))
                : _method == null
                    ? _pickMethod()
                    : _WithdrawForm(
                        key: ValueKey(_method!['id']),
                        method: _method!,
                        entry: _catalog[strOf(_method!['slug'])],
                        remaining: _limits['dailyCashRemaining'] is num ? numOf(_limits['dailyCashRemaining']) : null,
                        onBack: () => setState(() => _method = null),
                      ),
      ),
    );
  }

  Widget _pickMethod() {
    if (_methods.isEmpty) {
      return const EmptyState(icon: Icons.account_balance_outlined, title: 'No withdraw methods right now', subtitle: 'Please check back soon.');
    }
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
      children: [
        ListenableBuilder(
          listenable: AppState.instance,
          builder: (_, __) => Panel(
            gradient: AppColors.heroGradient,
            child: Row(children: [
              Text('Available', style: AppTheme.body(13, color: AppColors.muted)),
              const Spacer(),
              Text(money(AppState.instance.currentWallet), style: AppTheme.display(22, color: AppColors.goldLight)),
            ]),
          ),
        ),
        if (_limits['dailyCashRemaining'] is num) ...[
          const SizedBox(height: 8),
          Text('You can withdraw up to ${money(numOf(_limits['dailyCashRemaining']))} more today.',
              style: AppTheme.body(12, color: AppColors.muted)),
        ],
        const SizedBox(height: 16),
        for (final m in _methods) ...[
          Panel(
            onTap: () => setState(() => _method = m),
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Container(
                width: 46,
                height: 46,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                child: _catalog[strOf(m['slug'])] == null
                    ? const Icon(Icons.account_balance_outlined, color: Colors.black54)
                    : NetImage(_catalog[strOf(m['slug'])]!.image, fit: BoxFit.contain, cacheWidth: 120),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(strOf(m['label']), style: AppTheme.body(15, weight: FontWeight.w800)),
                  if (numOf(m['min_amount']) > 0)
                    Text('Minimum ${money(numOf(m['min_amount']))}', style: AppTheme.body(12, color: AppColors.muted)),
                ]),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
            ]),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _WithdrawForm extends StatefulWidget {
  const _WithdrawForm({super.key, required this.method, required this.entry, required this.remaining, required this.onBack});
  final Map<String, dynamic> method;
  final CatalogEntry? entry;
  final double? remaining;
  final VoidCallback onBack;
  @override
  State<_WithdrawForm> createState() => _WithdrawFormState();
}

class _WithdrawFormState extends State<_WithdrawForm> {
  final _amount = TextEditingController();
  final _tip = TextEditingController();
  final Map<String, TextEditingController> _fields = {};
  XFile? _qr;
  bool _busy = false;

  List<PayField> get _payout => widget.entry?.payoutFields ?? const <PayField>[];

  @override
  void initState() {
    super.initState();
    for (final f in _payout) {
      _fields[f.key] = TextEditingController();
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _tip.dispose();
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    final amount = double.tryParse(_amount.text) ?? 0;
    final tip = double.tryParse(_tip.text) ?? 0;
    final min = numOf(widget.method['min_amount']);
    if (amount <= 0) {
      toast(context, 'Enter the amount you want to withdraw.', error: true);
      return;
    }
    if (min > 0 && amount < min) {
      toast(context, 'The minimum for this method is ${money(min)}.', error: true);
      return;
    }
    if (tip >= amount) {
      toast(context, 'Tip must be less than the withdraw amount.', error: true);
      return;
    }
    for (final f in _payout) {
      if (f.required && (_fields[f.key]?.text.trim() ?? '').isEmpty) {
        toast(context, 'Enter ${f.label}.', error: true);
        return;
      }
    }
    if ((widget.entry?.supportsQr ?? false) && _qr == null) {
      toast(context, 'Upload your QR so admin can pay you.', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await ApiClient.instance.multipart(
        '/api/withdraws',
        {
          'methodId': strOf(widget.method['id']),
          'amount': amount.toStringAsFixed(2),
          'tip': tip.toStringAsFixed(2),
          'details': jsonEncode({for (final e in _fields.entries) e.key: e.value.text.trim()}),
        },
        [if (_qr != null) UploadFile('qr', _qr!.path, filename: _qr!.name)],
      );
      await AppState.instance.refreshWallet().catchError((_) {});
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.check_circle_rounded, color: AppColors.mint, size: 48),
          title: Text('Withdraw requested', style: AppTheme.display(20)),
          content: Text('We will send ${money(amount - tip)} to your account once it is approved.', style: AppTheme.body(14, color: AppColors.muted)),
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
    final instructions = strOf(widget.method['instructions']);
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 40),
      children: [
        TextButton.icon(
          onPressed: widget.onBack,
          icon: const Icon(Icons.arrow_back_rounded, size: 18),
          label: Text('Withdraw with ${strOf(widget.method['label'])}'),
          style: TextButton.styleFrom(alignment: Alignment.centerLeft, foregroundColor: AppColors.muted),
        ),
        if (instructions.isNotEmpty) ...[
          Panel(child: Text(instructions, style: AppTheme.body(13, color: AppColors.muted))),
          const SizedBox(height: 12),
        ],
        AmountField(controller: _amount, label: 'Amount'),
        if (widget.remaining != null) ...[
          const SizedBox(height: 6),
          Text('Today you can still withdraw ${money(widget.remaining!)}.', style: AppTheme.body(12, color: AppColors.muted)),
        ],
        const SizedBox(height: 12),
        AmountField(controller: _tip, label: 'Tip for the team (optional)'),
        for (final f in _payout) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _fields[f.key],
            keyboardType: f.type == 'email' ? TextInputType.emailAddress : TextInputType.text,
            decoration: InputDecoration(labelText: f.required ? '${f.label} *' : f.label, hintText: f.placeholder),
          ),
        ],
        if (widget.entry?.supportsQr ?? false) ...[
          const SizedBox(height: 16),
          PhotoField(
            label: 'Your payment QR',
            required: true,
            file: _qr,
            onPick: () async {
              final f = await pickPhoto(context);
              if (f != null) setState(() => _qr = f);
            },
          ),
        ],
        const SizedBox(height: 22),
        PrimaryButton(label: 'Request withdraw', loading: _busy, onPressed: _submit),
      ],
    );
  }
}
