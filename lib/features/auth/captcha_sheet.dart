import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/config.dart';
import '../../core/theme.dart';

/// Runs the website's Cloudflare Turnstile check (/app-captcha) and returns its single-use token.
/// Only the DazzlingWins origin may load in this view; the token comes back through a JS channel.
Future<String?> runCaptcha(BuildContext context) {
  return showAppPopup<String>(
    context,
    builder: (_) => const _CaptchaView(),
  );
}

class _CaptchaView extends StatefulWidget {
  const _CaptchaView();
  @override
  State<_CaptchaView> createState() => _CaptchaViewState();
}

class _CaptchaViewState extends State<_CaptchaView> {
  late final WebViewController _controller;
  bool _loading = true;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    final origin = Uri.parse(AppConfig.baseUrl).host;
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(AppColors.bg)
      ..addJavaScriptChannel('DazzlingCaptcha', onMessageReceived: (msg) {
        if (_done || !mounted) return;
        _done = true;
        Navigator.of(context).pop(msg.message);
      })
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          if (mounted) setState(() => _loading = false);
        },
        onNavigationRequest: (req) {
          final host = Uri.tryParse(req.url)?.host ?? '';
          // Our site and Cloudflare's challenge frames only.
          final allowed = host == origin || host.endsWith('.$origin') || host == 'challenges.cloudflare.com';
          return allowed ? NavigationDecision.navigate : NavigationDecision.prevent;
        },
      ))
      ..loadRequest(AppConfig.uri('/app-captcha'));
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.55,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Row(children: [
            const Icon(Icons.verified_user_outlined, color: AppColors.mint, size: 20),
            const SizedBox(width: 8),
            Text('Security check', style: AppTheme.display(16)),
          ]),
        ),
        Expanded(
          child: Stack(children: [
            WebViewWidget(controller: _controller),
            if (_loading) const Center(child: CircularProgressIndicator()),
          ]),
        ),
      ]),
    );
  }
}
