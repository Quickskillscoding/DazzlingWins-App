import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';

import '../../core/api.dart';
import '../../core/theme.dart';
import '../../widgets/image_pick.dart';
import '../../widgets/ui.dart';
import 'chat_bubble.dart';
import 'chat_models.dart';
import 'emoji_panel.dart';

/// Live Chat: the player's conversation with DazzlingWins admins and agents. It is the website's
/// "Agents Chat" thread (/api/chat/messages, section "help"), so a message sent here is stored on
/// the server at once and shows up in the back office chat desk, and replies come back here.
///
/// Text, emoji, photos (camera or gallery) and voice notes; swipe a message right to reply;
/// long-press it for Reply / Copy / Delete.
class LiveChatScreen extends StatefulWidget {
  const LiveChatScreen({super.key});
  @override
  State<LiveChatScreen> createState() => _LiveChatScreenState();
}

class _SignedUrl {
  const _SignedUrl(this.url, this.at);
  final String url;
  final DateTime at;
}

class _LiveChatScreenState extends State<LiveChatScreen> with WidgetsBindingObserver {
  /// How often the thread is refreshed while the chat is open.
  static const _pollEvery = Duration(seconds: 3);

  /// Attachment links live 60 minutes on the server; ask for new ones well before that.
  static const _urlMaxAge = Duration(minutes: 40);

  /// Largest file the chat server accepts.
  static const _maxFileBytes = 10 * 1024 * 1024;

  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  final _playback = VoicePlayback();

  List<ChatMessage> _messages = const [];
  final List<ChatMessage> _pending = [];
  final Map<String, _SignedUrl> _urls = {};
  String _signature = '';
  bool _needSignedUrls = true;
  bool _loading = true;
  bool _loadInFlight = false;
  bool _foreground = true;
  String? _error;
  Timer? _poll;
  int _localSeq = 0;

  ChatMessage? _replyTo;
  bool _showEmoji = false;

  AudioRecorder? _recorder;
  bool _recording = false;
  bool _recorderBusy = false;
  DateTime _recStart = DateTime.now();
  Duration _recElapsed = Duration.zero;
  String _recPath = '';
  Timer? _recTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _focus.addListener(_onFocus);
    _load();
    _poll = Timer.periodic(_pollEvery, (_) {
      if (_foreground) _load(quiet: true);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _recTimer?.cancel();
    final recorder = _recorder;
    _recorder = null;
    if (recorder != null) {
      unawaited(() async {
        try {
          if (_recording) await recorder.cancel();
          await recorder.dispose();
        } catch (_) {}
      }());
    }
    _playback.dispose();
    _focus
      ..removeListener(_onFocus)
      ..dispose();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      _load(quiet: true);
    } else if (state == AppLifecycleState.paused) {
      unawaited(_playback.stop());
      if (_recording) unawaited(_finishRecording(send: false));
    }
  }

  void _onFocus() {
    // The keyboard and the emoji panel never show together.
    if (_focus.hasFocus && _showEmoji && mounted) setState(() => _showEmoji = false);
  }

  // ── Loading ────────────────────────────────────────────────────────────────

  Future<void> _load({bool quiet = false}) async {
    if (_loadInFlight) return;
    _loadInFlight = true;
    final signed = _needSignedUrls;
    try {
      final data = await ApiClient.instance.get(
        '/api/chat/messages',
        // Fresh attachment links only when one is missing or about to expire: the usual refresh is light.
        query: {'section': kLiveChatSection, if (!signed) 'signUrls': '0'},
      );
      if (!mounted) return;
      _apply(listOf(data['messages']).map(ChatMessage.fromJson).where((m) => m.id.isNotEmpty).toList(), signed);
    } on ApiException catch (e) {
      if (mounted && !quiet && _messages.isEmpty) setState(() => _error = e.message);
    } catch (_) {
      if (mounted && !quiet && _messages.isEmpty) setState(() => _error = 'Could not load the chat. Please try again.');
    } finally {
      _loadInFlight = false;
      if (mounted && _loading) setState(() => _loading = false);
    }
    // A new attachment arrived in a light refresh: fetch its link right away.
    if (mounted && !signed && _needSignedUrls) unawaited(_load(quiet: true));
  }

  void _apply(List<ChatMessage> fetched, bool signed) {
    final now = DateTime.now();
    if (signed) {
      for (final m in fetched) {
        if (m.attachmentPath.isNotEmpty && m.attachmentUrl.isNotEmpty) _urls[m.attachmentPath] = _SignedUrl(m.attachmentUrl, now);
      }
    }
    var need = false;
    final list = <ChatMessage>[];
    for (final m in fetched) {
      if (m.attachmentPath.isEmpty) {
        list.add(m);
        continue;
      }
      final known = _urls[m.attachmentPath];
      if (known == null || now.difference(known.at) > _urlMaxAge) need = true;
      list.add(known == null ? m : m.withUrl(known.url));
    }
    _needSignedUrls = need;

    final signature = list.map((m) => '${m.id}:${m.attachmentUrl.isEmpty ? 0 : 1}').join(',');
    if (!signed && signature == _signature && _error == null) return;
    _signature = signature;
    final reply = _replyTo;
    setState(() {
      _messages = list;
      _error = null;
      // The message being answered was deleted meanwhile.
      if (reply != null && !list.any((m) => m.id == reply.id)) _replyTo = null;
    });
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      // The list is reversed: offset 0 is the newest message.
      _scroll.animateTo(0, duration: const Duration(milliseconds: 260), curve: Curves.easeOut);
    });
  }

  // ── Sending ────────────────────────────────────────────────────────────────

  Future<void> _sendText({String? quick}) async {
    final text = (quick ?? _input.text).trim();
    if (text.isEmpty) return;
    if (text.length > kMaxChatTextLength) {
      toast(context, 'Messages can be up to $kMaxChatTextLength characters.', error: true);
      return;
    }
    if (quick == null) _input.clear();
    final ok = await _deliver(text: text);
    // Failed: give the text back so nothing the player typed is lost.
    if (!ok && quick == null && mounted && _input.text.isEmpty) {
      _input.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
    }
  }

  /// Sends one message (text and/or a file). Shows it immediately as "Sending…".
  Future<bool> _deliver({String text = '', String filePath = '', String fileName = '', String fileType = ''}) async {
    final reply = _replyTo;
    final local = ChatMessage(
      id: 'local-${++_localSeq}',
      senderRole: 'user',
      body: text,
      createdAt: DateTime.now(),
      attachmentName: fileName,
      attachmentType: fileType,
      replyTo: reply?.id ?? '',
      pending: true,
      localFile: filePath,
    );
    setState(() {
      _pending.add(local);
      _replyTo = null;
    });
    _toBottom();
    try {
      final fields = <String, String>{'section': kLiveChatSection, 'body': text, if (reply != null) 'replyTo': reply.id};
      final data = filePath.isEmpty
          ? await ApiClient.instance.post('/api/chat/messages', fields)
          : await ApiClient.instance.multipart('/api/chat/messages', fields, [UploadFile('file', filePath, filename: fileName)]);
      if (!mounted) return true;
      final sent = ChatMessage.fromJson(mapOf(data['message']));
      setState(() {
        _pending.remove(local);
        if (sent.id.isNotEmpty && !_messages.any((m) => m.id == sent.id)) {
          if (sent.attachmentPath.isNotEmpty && sent.attachmentUrl.isNotEmpty) {
            _urls[sent.attachmentPath] = _SignedUrl(sent.attachmentUrl, DateTime.now());
          }
          _messages = [..._messages, sent];
        }
      });
      unawaited(_load(quiet: true));
      return true;
    } on ApiException catch (e) {
      _sendFailed(local, reply, e.message);
      return false;
    } catch (_) {
      _sendFailed(local, reply, 'Could not send your message. Please try again.');
      return false;
    }
  }

  void _sendFailed(ChatMessage local, ChatMessage? reply, String message) {
    if (!mounted) return;
    setState(() {
      _pending.remove(local);
      _replyTo ??= reply;
    });
    toast(context, message, error: true);
  }

  Future<void> _sendPhoto(ImageSource source) async {
    if (_recording) return;
    _hideEmoji();
    final file = await pickPhoto(context, source: source);
    if (file == null || !mounted) return;
    final lower = file.name.toLowerCase();
    final type = lower.endsWith('.png')
        ? 'image/png'
        : lower.endsWith('.webp')
            ? 'image/webp'
            : lower.endsWith('.gif')
                ? 'image/gif'
                : 'image/jpeg';
    await _deliver(filePath: file.path, fileName: file.name.isEmpty ? 'photo.jpg' : file.name, fileType: type);
  }

  // ── Voice notes ────────────────────────────────────────────────────────────

  Future<void> _startRecording() async {
    if (_recording || _recorderBusy) return;
    _recorderBusy = true;
    _hideEmoji();
    _focus.unfocus();
    try {
      final recorder = _recorder ??= AudioRecorder();
      if (!await recorder.hasPermission()) {
        if (mounted) toast(context, 'Allow microphone access to record a voice message.', error: true);
        return;
      }
      await _playback.stop();
      final path = '${Directory.systemTemp.path}/dw-voice-${DateTime.now().millisecondsSinceEpoch}.m4a';
      // AAC in an MP4 container: the format the website's chat accepts and every browser plays.
      await recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000, sampleRate: 44100, numChannels: 1), path: path);
      if (!mounted) {
        await recorder.cancel();
        return;
      }
      HapticFeedback.mediumImpact();
      _recPath = path;
      _recStart = DateTime.now();
      setState(() {
        _recording = true;
        _recElapsed = Duration.zero;
      });
      _recTimer?.cancel();
      _recTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (!mounted || !_recording) return;
        final elapsed = DateTime.now().difference(_recStart);
        if (elapsed >= kMaxVoiceNote) {
          unawaited(_finishRecording(send: true));
        } else if (elapsed.inSeconds != _recElapsed.inSeconds) {
          setState(() => _recElapsed = elapsed);
        }
      });
    } catch (_) {
      if (mounted) toast(context, 'Could not start recording. Check the microphone permission.', error: true);
    } finally {
      _recorderBusy = false;
    }
  }

  /// Stops the recording and sends it, or throws it away.
  Future<void> _finishRecording({required bool send}) async {
    if (!_recording || _recorderBusy) return;
    _recorderBusy = true;
    _recTimer?.cancel();
    final elapsed = DateTime.now().difference(_recStart);
    var path = _recPath;
    try {
      if (send) {
        final stopped = await _recorder?.stop();
        if (stopped != null && stopped.isNotEmpty) path = stopped;
      } else {
        await _recorder?.cancel();
      }
    } catch (_) {
      // Fall through: the file check below decides.
    } finally {
      _recorderBusy = false;
    }
    _recording = false;
    if (mounted) setState(() {});
    final file = File(path);
    try {
      if (!send) return;
      if (!mounted) return;
      if (elapsed < const Duration(seconds: 1)) {
        toast(context, 'That recording was too short.', error: true);
        return;
      }
      final size = await file.exists() ? await file.length() : 0;
      if (!mounted) return;
      if (size <= 0) {
        toast(context, 'Nothing was recorded. Please try again.', error: true);
        return;
      }
      if (size > _maxFileBytes) {
        toast(context, 'That voice message is too long to send.', error: true);
        return;
      }
      await _deliver(filePath: path, fileName: kVoiceNoteName, fileType: 'audio/mp4');
    } finally {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
  }

  // ── Reply, copy, delete ────────────────────────────────────────────────────

  void _reply(ChatMessage m) {
    if (_recording) return;
    HapticFeedback.selectionClick();
    setState(() {
      _replyTo = m;
      _showEmoji = false;
    });
    _focus.requestFocus();
  }

  Future<void> _openMenu(ChatMessage m, Offset at) async {
    HapticFeedback.mediumImpact();
    final size = MediaQuery.of(context).size;
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(at.dx, at.dy, size.width - at.dx, size.height - at.dy),
      color: AppColors.surface2,
      elevation: 12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: AppColors.stroke)),
      items: [
        _menuItem('reply', Icons.reply_rounded, 'Reply'),
        if (m.body.isNotEmpty) _menuItem('copy', Icons.copy_rounded, 'Copy'),
        // The server only lets a player delete their own messages.
        if (m.mine) _menuItem('delete', Icons.delete_outline_rounded, 'Delete', color: AppColors.danger),
      ],
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'reply':
        _reply(m);
      case 'copy':
        await Clipboard.setData(ClipboardData(text: m.body));
        if (mounted) toast(context, 'Message copied');
      case 'delete':
        await _delete(m);
    }
  }

  PopupMenuItem<String> _menuItem(String value, IconData icon, String label, {Color color = AppColors.text}) {
    return PopupMenuItem<String>(
      value: value,
      height: 46,
      child: Row(children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 12),
        Text(label, style: AppTheme.body(14, weight: FontWeight.w700, color: color)),
      ]),
    );
  }

  Future<void> _delete(ChatMessage m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete this message?', style: AppTheme.display(18)),
        content: Text('It is removed from the chat for you and for our team.', style: AppTheme.body(14, color: AppColors.muted)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete', style: AppTheme.body(14, weight: FontWeight.w800, color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (_playback.state.value.id == m.id) unawaited(_playback.stop());
    setState(() {
      _messages = _messages.where((x) => x.id != m.id).toList();
      if (_replyTo?.id == m.id) _replyTo = null;
    });
    try {
      await ApiClient.instance.delete('/api/chat/messages', {'section': kLiveChatSection, 'messageId': m.id});
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } catch (_) {
      if (mounted) toast(context, 'Could not delete the message.', error: true);
    }
    _signature = '';
    unawaited(_load(quiet: true));
  }

  // ── Emoji ──────────────────────────────────────────────────────────────────

  void _hideEmoji() {
    if (_showEmoji && mounted) setState(() => _showEmoji = false);
  }

  void _toggleEmoji() {
    if (_showEmoji) {
      setState(() => _showEmoji = false);
      _focus.requestFocus();
    } else {
      _focus.unfocus();
      setState(() => _showEmoji = true);
    }
  }

  void _insertEmoji(String emoji) {
    final value = _input.value;
    final sel = value.selection;
    final start = sel.isValid ? sel.start : value.text.length;
    final end = sel.isValid ? sel.end : value.text.length;
    if (value.text.length - (end - start) + emoji.length > kMaxChatTextLength) return;
    _input.value = TextEditingValue(
      text: value.text.replaceRange(start, end, emoji),
      selection: TextSelection.collapsed(offset: start + emoji.length),
    );
  }

  void _emojiBackspace() {
    final value = _input.value;
    final sel = value.selection;
    final start = sel.isValid ? sel.start : value.text.length;
    final end = sel.isValid ? sel.end : value.text.length;
    if (start != end) {
      _input.value = TextEditingValue(text: value.text.replaceRange(start, end, ''), selection: TextSelection.collapsed(offset: start));
      return;
    }
    if (start <= 0) return;
    // Remove one whole character (an emoji is several code units).
    final before = value.text.substring(0, start).characters.skipLast(1).toString();
    _input.value = TextEditingValue(text: before + value.text.substring(start), selection: TextSelection.collapsed(offset: before.length));
  }

  // ── UI ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      // Back closes the emoji panel first, then the chat.
      canPop: !_showEmoji,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _hideEmoji();
      },
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: Row(children: [
            Container(
              width: 38,
              height: 38,
              decoration: const BoxDecoration(gradient: AppColors.primaryGradient, shape: BoxShape.circle),
              child: const Icon(Icons.support_agent_rounded, color: Colors.white, size: 21),
            ),
            const SizedBox(width: 11),
            Flexible(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text('Live Chat', style: AppTheme.display(17), maxLines: 1, overflow: TextOverflow.ellipsis),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 7, height: 7, decoration: const BoxDecoration(color: AppColors.mint, shape: BoxShape.circle)),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text('DazzlingWins agents', style: AppTheme.body(11.5, color: AppColors.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ]),
              ]),
            ),
          ]),
        ),
        body: AppBackground(
          child: Column(children: [
            Expanded(child: _thread()),
            _composer(),
          ]),
        ),
      ),
    );
  }

  Widget _thread() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final all = [..._messages, ..._pending];
    if (all.isEmpty) {
      if (_error != null) return Center(child: ErrorRetry(message: _error!, onRetry: _load));
      return const Center(
        child: SingleChildScrollView(
          child: EmptyState(
            icon: Icons.support_agent_rounded,
            title: 'How can we help?',
            subtitle: 'Send a message, photo or voice note. Our agents reply here.',
          ),
        ),
      );
    }
    final byId = <String, ChatMessage>{for (final m in _messages) m.id: m};
    return ListView.builder(
      controller: _scroll,
      reverse: true,
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      itemCount: all.length,
      itemBuilder: (context, i) {
        final index = all.length - 1 - i;
        final m = all[index];
        final older = index > 0 ? all[index - 1] : null;
        final newDay = m.createdAt != null && (older == null || !sameChatDay(older.createdAt, m.createdAt));
        final bubble = ChatBubble(
          message: m,
          quoted: m.replyTo.isEmpty ? null : byId[m.replyTo],
          playback: _playback,
          onReply: () => _reply(m),
          onMenu: (at) => _openMenu(m, at),
          onOpenImage: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatImageViewer(message: m))),
          onPlayError: (message) {
            if (!mounted) return;
            toast(context, message, error: true);
            // The link may have expired: get fresh ones.
            _needSignedUrls = true;
            unawaited(_load(quiet: true));
          },
        );
        return KeyedSubtree(
          key: ValueKey('msg-${m.id}'),
          child: newDay
              ? Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [_DayChip(label: chatDayLabel(m.createdAt!)), bubble])
              : bubble,
        );
      },
    );
  }

  Widget _composer() {
    final reply = _replyTo;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.stroke)),
      ),
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (reply != null && !_recording)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
              child: Row(children: [
                const Icon(Icons.reply_rounded, size: 18, color: AppColors.gold),
                const SizedBox(width: 8),
                Expanded(
                  child: QuoteCard(
                    name: 'Replying to ${reply.mine ? 'yourself' : reply.teamName}',
                    text: reply.preview,
                    color: AppColors.surface3,
                  ),
                ),
                IconButton(
                  tooltip: 'Cancel reply',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close_rounded, size: 20, color: AppColors.muted),
                  onPressed: () => setState(() => _replyTo = null),
                ),
              ]),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 8, 8, 8),
            child: _recording ? _recordingRow() : _inputRow(),
          ),
          if (_showEmoji && !_recording) EmojiPanel(onPick: _insertEmoji, onBackspace: _emojiBackspace),
        ]),
      ),
    );
  }

  Widget _inputRow() {
    OutlineInputBorder border(Color color) => OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide(color: color));
    return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      _ToolButton(icon: Icons.photo_camera_outlined, tooltip: 'Take a photo', onTap: () => _sendPhoto(ImageSource.camera)),
      _ToolButton(icon: Icons.attach_file_rounded, tooltip: 'Attach a photo', onTap: () => _sendPhoto(ImageSource.gallery)),
      _ToolButton(icon: Icons.mic_none_rounded, tooltip: 'Record a voice message', onTap: _startRecording),
      const SizedBox(width: 2),
      Expanded(
        child: TextField(
          controller: _input,
          focusNode: _focus,
          minLines: 1,
          maxLines: 5,
          maxLength: kMaxChatTextLength,
          textCapitalization: TextCapitalization.sentences,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
          style: AppTheme.body(14.5),
          decoration: InputDecoration(
            hintText: 'Type your message…',
            counterText: '',
            isDense: true,
            filled: true,
            fillColor: AppColors.surface2,
            contentPadding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
            border: border(AppColors.stroke),
            enabledBorder: border(AppColors.stroke),
            focusedBorder: border(AppColors.primary),
            suffixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 44),
            suffixIcon: IconButton(
              tooltip: _showEmoji ? 'Keyboard' : 'Emoji',
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              icon: Icon(_showEmoji ? Icons.keyboard_alt_outlined : Icons.emoji_emotions_outlined, color: AppColors.muted, size: 22),
              onPressed: _toggleEmoji,
            ),
          ),
        ),
      ),
      const SizedBox(width: 8),
      // Send when there is text, a quick thumbs-up when the box is empty.
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: _input,
        builder: (context, value, _) {
          final hasText = value.text.trim().isNotEmpty;
          return _SendButton(
            icon: hasText ? Icons.send_rounded : Icons.thumb_up_alt_rounded,
            tooltip: hasText ? 'Send' : 'Send a thumbs up',
            onTap: () {
              HapticFeedback.selectionClick();
              _sendText(quick: hasText ? null : '👍');
            },
          );
        },
      ),
    ]);
  }

  Widget _recordingRow() {
    return Row(children: [
      IconButton(
        tooltip: 'Discard recording',
        icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
        onPressed: () => _finishRecording(send: false),
      ),
      Expanded(
        child: Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.danger.withValues(alpha: 0.5)),
          ),
          child: Row(children: [
            const _RecordingDot(),
            const SizedBox(width: 10),
            Text(chatDuration(_recElapsed), style: AppTheme.body(15, weight: FontWeight.w800)),
            const SizedBox(width: 10),
            Expanded(
              child: Text('Recording…', style: AppTheme.body(13, color: AppColors.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ]),
        ),
      ),
      const SizedBox(width: 8),
      _SendButton(
        icon: Icons.send_rounded,
        tooltip: 'Send voice message',
        onTap: () {
          HapticFeedback.selectionClick();
          _finishRecording(send: true);
        },
      ),
    ]);
  }
}

/// Gold tool icon left of the message box (camera, attach, microphone).
class _ToolButton extends StatelessWidget {
  const _ToolButton({required this.icon, required this.tooltip, required this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 38, height: 46),
      icon: Icon(icon, color: AppColors.gold, size: 23),
      onPressed: onTap,
    );
  }
}

/// Round gold send button.
class _SendButton extends StatelessWidget {
  const _SendButton({required this.icon, required this.tooltip, required this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Container(
        width: 46,
        height: 46,
        decoration: const BoxDecoration(gradient: AppColors.goldGradient, shape: BoxShape.circle),
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 160),
              child: Icon(icon, key: ValueKey(icon.codePoint), color: Colors.black, size: 21),
            ),
          ),
        ),
      ),
    );
  }
}

/// Blinking red dot shown while recording.
class _RecordingDot extends StatefulWidget {
  const _RecordingDot();
  @override
  State<_RecordingDot> createState() => _RecordingDotState();
}

class _RecordingDotState extends State<_RecordingDot> with SingleTickerProviderStateMixin {
  late final AnimationController _blink = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))..repeat(reverse: true);

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.3, end: 1).animate(_blink),
      child: Container(width: 10, height: 10, decoration: const BoxDecoration(color: AppColors.danger, shape: BoxShape.circle)),
    );
  }
}

/// "Today" / "Yesterday" / date separator between days.
class _DayChip extends StatelessWidget {
  const _DayChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: AppColors.stroke),
          ),
          child: Text(label, style: AppTheme.body(11, weight: FontWeight.w700, color: AppColors.muted)),
        ),
      ),
    );
  }
}
