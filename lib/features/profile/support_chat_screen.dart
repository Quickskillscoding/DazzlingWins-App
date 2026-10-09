import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';

/// Live support chat with the DazzlingWins team — the website's help-center thread
/// (/api/chat/messages?section=help). Polls every 5 s while open.
class SupportChatScreen extends StatefulWidget {
  const SupportChatScreen({super.key});
  @override
  State<SupportChatScreen> createState() => _SupportChatScreenState();
}

class _SupportChatScreenState extends State<SupportChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;
  bool _sending = false;
  String? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _load(quiet: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool quiet = false}) async {
    try {
      final d = await ApiClient.instance.get('/api/chat/messages', query: {'section': 'help'});
      final list = listOf(d['messages']);
      if (!mounted) return;
      final grew = list.length != _messages.length;
      setState(() {
        _messages = list;
        _error = null;
      });
      if (grew) _toBottom();
    } on ApiException catch (e) {
      if (mounted && !quiet) setState(() => _error = e.message);
    } finally {
      if (mounted && _loading) setState(() => _loading = false);
    }
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await ApiClient.instance.post('/api/chat/messages', {'section': 'help', 'body': text});
      _input.clear();
      await _load(quiet: true);
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Support')),
      body: AppBackground(
        child: Column(children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: ErrorRetry(message: _error!, onRetry: _load))
                    : _messages.isEmpty
                        ? const EmptyState(icon: Icons.support_agent_rounded, title: 'How can we help?', subtitle: 'Send a message — our team replies here.')
                        : ListView.builder(
                            controller: _scroll,
                            physics: const BouncingScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
                            itemCount: _messages.length,
                            itemBuilder: (_, i) => _Bubble(message: _messages[i]),
                          ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    minLines: 1,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(hintText: 'Type a message'),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  style: IconButton.styleFrom(backgroundColor: AppColors.primary, minimumSize: const Size(52, 52)),
                  onPressed: _sending ? null : _send,
                  icon: _sending
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.send_rounded, color: Colors.white),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});
  final Map<String, dynamic> message;
  @override
  Widget build(BuildContext context) {
    final mine = strOf(message['sender_role']) == 'user';
    final body = strOf(message['body']);
    final hasFile = strOf(message['attachment_name']).isNotEmpty;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: mine ? AppColors.primaryGradient : null,
          color: mine ? null : AppColors.surface2,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(mine ? 18 : 4),
            bottomRight: Radius.circular(mine ? 4 : 18),
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (!mine && strOf(message['sender_display_name']).isNotEmpty)
            Text(strOf(message['sender_display_name']), style: AppTheme.body(11, weight: FontWeight.w800, color: AppColors.gold)),
          if (body.isNotEmpty) Text(body, style: AppTheme.body(14, color: Colors.white, height: 1.35)),
          if (hasFile)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.attach_file_rounded, size: 14, color: AppColors.muted),
                const SizedBox(width: 4),
                Flexible(child: Text(strOf(message['attachment_name']), style: AppTheme.body(12, color: AppColors.muted))),
              ]),
            ),
          const SizedBox(height: 4),
          Text(relativeTime(message['created_at']), style: AppTheme.body(10, color: Colors.white.withValues(alpha: 0.6))),
        ]),
      ),
    );
  }
}
