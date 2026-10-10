import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/theme.dart';
import 'chat_models.dart';

/// What the single voice-note player is doing right now.
class VoiceState {
  const VoiceState({this.id = '', this.playing = false, this.loading = false, this.position = Duration.zero, this.duration = Duration.zero});

  /// Id of the message that is loaded in the player ('' = none).
  final String id;
  final bool playing;
  final bool loading;
  final Duration position;
  final Duration duration;

  VoiceState copyWith({bool? playing, bool? loading, Duration? position, Duration? duration}) => VoiceState(
        id: id,
        playing: playing ?? this.playing,
        loading: loading ?? this.loading,
        position: position ?? this.position,
        duration: duration ?? this.duration,
      );
}

/// One audio player shared by every voice note in the chat: starting one stops the other.
class VoicePlayback {
  final ValueNotifier<VoiceState> state = ValueNotifier<VoiceState>(const VoiceState());
  final List<StreamSubscription<dynamic>> _subs = [];
  AudioPlayer? _player;
  int _request = 0;
  bool _disposed = false;

  AudioPlayer _ensure() {
    final existing = _player;
    if (existing != null) return existing;
    final player = AudioPlayer();
    _subs
      ..add(player.positionStream.listen((p) {
        final s = state.value;
        if (s.id.isNotEmpty && !s.loading) state.value = s.copyWith(position: p);
      }))
      ..add(player.durationStream.listen((d) {
        final s = state.value;
        if (d != null && s.id.isNotEmpty) state.value = s.copyWith(duration: d);
      }))
      ..add(player.playerStateStream.listen((ps) {
        final s = state.value;
        if (s.id.isEmpty || s.loading) return;
        if (ps.processingState == ProcessingState.completed) {
          // Finished: rewind so the next tap plays it again from the start.
          state.value = s.copyWith(playing: false, position: Duration.zero);
          unawaited(player.pause().then((_) => player.seek(Duration.zero)).catchError((_) {}));
        } else {
          state.value = s.copyWith(playing: ps.playing);
        }
      }));
    _player = player;
    return player;
  }

  /// Play / pause the voice note of message [id]. Returns an error text, or null when fine.
  Future<String?> toggle(String id, String url) async {
    if (_disposed) return null;
    if (url.isEmpty) return 'This voice message is still loading. Try again in a moment.';
    final player = _ensure();
    final current = state.value;
    if (current.id == id && !current.loading) {
      try {
        if (current.playing) {
          await player.pause();
        } else {
          unawaited(player.play().catchError((_) {}));
        }
        return null;
      } catch (_) {
        return 'Could not play this voice message.';
      }
    }
    final request = ++_request;
    state.value = VoiceState(id: id, loading: true);
    try {
      await player.stop();
      final duration = await player.setUrl(url);
      if (_disposed || request != _request) return null;
      state.value = VoiceState(id: id, duration: duration ?? Duration.zero);
      unawaited(player.play().catchError((_) {}));
      return null;
    } catch (_) {
      if (!_disposed && request == _request) state.value = const VoiceState();
      return 'Could not play this voice message.';
    }
  }

  /// Stop whatever is playing (leaving the chat, starting a recording, deleting the message).
  Future<void> stop() async {
    _request++;
    if (_disposed) return;
    state.value = const VoiceState();
    try {
      await _player?.stop();
    } catch (_) {}
  }

  void dispose() {
    _disposed = true;
    _request++;
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    final player = _player;
    _player = null;
    if (player != null) unawaited(player.dispose().catchError((_) {}));
    state.dispose();
  }
}

/// A chat message: swipe it right to reply, long-press it for Reply / Copy / Delete.
class ChatBubble extends StatelessWidget {
  const ChatBubble({
    super.key,
    required this.message,
    required this.playback,
    required this.onReply,
    required this.onMenu,
    required this.onOpenImage,
    required this.onPlayError,
    this.quoted,
  });

  final ChatMessage message;

  /// The message this one answers (null when it is not a reply, or the original is gone).
  final ChatMessage? quoted;
  final VoicePlayback playback;
  final VoidCallback onReply;

  /// Long press, with the finger's position on screen.
  final ValueChanged<Offset> onMenu;
  final VoidCallback onOpenImage;
  final ValueChanged<String> onPlayError;

  @override
  Widget build(BuildContext context) {
    final m = message;
    final mine = m.mine;
    final maxWidth = MediaQuery.of(context).size.width * 0.78;
    final timeColor = Colors.white.withValues(alpha: mine ? 0.72 : 0.5);

    final bubble = Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 8),
      decoration: BoxDecoration(
        gradient: mine ? AppColors.primaryGradient : null,
        color: mine ? null : AppColors.surface2,
        border: mine ? null : Border.all(color: AppColors.stroke),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(mine ? 18 : 5),
          bottomRight: Radius.circular(mine ? 5 : 18),
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        if (!mine)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Text(m.teamName, style: AppTheme.body(11, weight: FontWeight.w800, color: AppColors.gold), maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        if (m.replyTo.isNotEmpty) _Quote(quoted: quoted, mine: mine),
        if (m.isImage)
          Padding(
            padding: EdgeInsets.only(bottom: m.body.isEmpty ? 2 : 7),
            child: GestureDetector(onTap: m.pending ? null : onOpenImage, child: ChatImage(message: m, size: 210)),
          )
        else if (m.isVoice)
          _VoiceNote(message: m, playback: playback, onError: onPlayError)
        else if (m.hasAttachment)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.insert_drive_file_outlined, size: 18, color: Colors.white.withValues(alpha: 0.8)),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  m.attachmentName.isEmpty ? 'Attachment' : m.attachmentName,
                  style: AppTheme.body(13, color: Colors.white.withValues(alpha: 0.9)),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ]),
          ),
        if (m.body.isNotEmpty) Text(m.body, style: AppTheme.body(14.5, color: Colors.white, height: 1.35)),
        const SizedBox(height: 4),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Text(m.pending ? 'Sending…' : chatClock(m.createdAt), style: AppTheme.body(10, color: timeColor)),
          if (m.pending) ...[
            const SizedBox(width: 4),
            Icon(Icons.schedule_rounded, size: 11, color: timeColor),
          ],
        ]),
      ]),
    );

    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Opacity(opacity: m.pending ? 0.7 : 1, child: bubble),
      ),
    );

    // Not on the server yet: nothing to reply to or delete.
    if (m.pending) return row;

    return SwipeToReply(
      onReply: onReply,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onLongPressStart: (d) => onMenu(d.globalPosition),
        child: row,
      ),
    );
  }
}

/// The quoted message shown at the top of a reply.
class _Quote extends StatelessWidget {
  const _Quote({required this.quoted, required this.mine});
  final ChatMessage? quoted;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final q = quoted;
    final name = q == null ? 'Message' : (q.mine ? 'You' : q.teamName);
    final text = q == null ? 'Original message is no longer available' : q.preview;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: QuoteCard(name: name, text: text, color: Colors.black.withValues(alpha: mine ? 0.2 : 0.28)),
    );
  }
}

/// Gold-edged card naming a message and summarising it (inside a reply, and above the message box).
class QuoteCard extends StatelessWidget {
  const QuoteCard({super.key, required this.name, required this.text, required this.color});
  final String name;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: ColoredBox(
        color: color,
        child: IntrinsicHeight(
          child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const SizedBox(width: 3, child: ColoredBox(color: AppColors.gold)),
            Flexible(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 10, 6),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(name, style: AppTheme.body(11, weight: FontWeight.w800, color: AppColors.gold), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 1),
                  Text(text, style: AppTheme.body(12, color: Colors.white.withValues(alpha: 0.75), height: 1.3), maxLines: 2, overflow: TextOverflow.ellipsis),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// A chat photo. The signed link changes on every load, so the picture is cached under its
/// storage path instead: it downloads once.
class ChatImage extends StatelessWidget {
  const ChatImage({super.key, required this.message, this.size, this.fit = BoxFit.cover});
  final ChatMessage message;

  /// Square edge of the thumbnail; null = as large as the parent allows (full-screen viewer).
  final double? size;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final m = message;
    final placeholder = SizedBox(
      width: size,
      height: size,
      child: const ColoredBox(color: AppColors.surface3, child: Center(child: Icon(Icons.image_outlined, color: AppColors.faint))),
    );
    final Widget image;
    if (m.localFile.isNotEmpty) {
      image = Image.file(File(m.localFile), width: size, height: size, fit: fit, cacheWidth: size == null ? null : 600, errorBuilder: (_, __, ___) => placeholder);
    } else if (m.attachmentUrl.isEmpty) {
      image = placeholder;
    } else {
      image = CachedNetworkImage(
        imageUrl: m.attachmentUrl,
        cacheKey: m.attachmentPath.isEmpty ? m.attachmentUrl : 'chat:${m.attachmentPath}',
        width: size,
        height: size,
        fit: fit,
        memCacheWidth: size == null ? null : 600,
        fadeInDuration: const Duration(milliseconds: 140),
        placeholder: (_, __) => placeholder,
        errorWidget: (_, __, ___) => SizedBox(
          width: size,
          height: size,
          child: const ColoredBox(color: AppColors.surface3, child: Center(child: Icon(Icons.broken_image_outlined, color: AppColors.faint))),
        ),
      );
    }
    return size == null ? image : ClipRRect(borderRadius: BorderRadius.circular(12), child: image);
  }
}

/// Play / pause button, progress line and time of a voice note.
class _VoiceNote extends StatelessWidget {
  const _VoiceNote({required this.message, required this.playback, required this.onError});
  final ChatMessage message;
  final VoicePlayback playback;
  final ValueChanged<String> onError;

  @override
  Widget build(BuildContext context) {
    final m = message;
    return ValueListenableBuilder<VoiceState>(
      valueListenable: playback.state,
      builder: (context, state, _) {
        final active = !m.pending && state.id == m.id;
        final playing = active && state.playing;
        final loading = active && state.loading;
        final total = active ? state.duration : Duration.zero;
        final position = active ? state.position : Duration.zero;
        final progress = total.inMilliseconds <= 0 ? 0.0 : (position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
        final label = !active
            ? 'Voice message'
            : total > Duration.zero
                ? '${chatDuration(position)} / ${chatDuration(total)}'
                : chatDuration(position);
        return Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: SizedBox(
            width: 200,
            child: Row(children: [
              Material(
                color: Colors.white.withValues(alpha: 0.16),
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: m.pending
                      ? null
                      : () async {
                          HapticFeedback.selectionClick();
                          final error = await playback.toggle(m.id, m.attachmentUrl);
                          if (error != null) onError(error);
                        },
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: loading
                        ? const Padding(padding: EdgeInsets.all(11), child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                        : Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white, size: 24),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 4,
                      backgroundColor: Colors.white.withValues(alpha: 0.2),
                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(children: [
                    Icon(Icons.mic_rounded, size: 12, color: Colors.white.withValues(alpha: 0.7)),
                    const SizedBox(width: 3),
                    Flexible(
                      child: Text(label, style: AppTheme.body(11, color: Colors.white.withValues(alpha: 0.8)), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ]),
                ]),
              ),
            ]),
          ),
        );
      },
    );
  }
}

/// Drag a message to the right to reply to it (it springs back when released).
class SwipeToReply extends StatefulWidget {
  const SwipeToReply({super.key, required this.child, required this.onReply});
  final Widget child;
  final VoidCallback onReply;

  @override
  State<SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<SwipeToReply> with SingleTickerProviderStateMixin {
  static const _max = 84.0; // furthest the message travels
  static const _trigger = 56.0; // distance that counts as "reply"

  late final AnimationController _spring = AnimationController(vsync: this, duration: const Duration(milliseconds: 180))..addListener(_onSpring);
  double _dx = 0;
  double _from = 0;
  bool _armed = false;

  void _onSpring() {
    if (!mounted) return;
    setState(() => _dx = _from * (1 - Curves.easeOut.transform(_spring.value)));
  }

  void _update(DragUpdateDetails d) {
    if (_spring.isAnimating) _spring.stop();
    final next = (_dx + d.delta.dx).clamp(0.0, _max).toDouble();
    if (next == _dx) return;
    final armed = next >= _trigger;
    if (armed && !_armed) HapticFeedback.selectionClick();
    setState(() {
      _dx = next;
      _armed = armed;
    });
  }

  void _release({bool fire = true}) {
    final reply = fire && _armed;
    _armed = false;
    _from = _dx;
    if (_dx > 0) _spring.forward(from: 0);
    if (reply) widget.onReply();
  }

  @override
  void dispose() {
    _spring.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reveal = (_dx / _trigger).clamp(0.0, 1.0).toDouble();
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragUpdate: _update,
      onHorizontalDragEnd: (_) => _release(),
      onHorizontalDragCancel: () => _release(fire: false),
      child: Stack(children: [
        if (_dx > 0)
          Positioned.fill(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Opacity(
                opacity: reveal,
                child: Transform.scale(
                  scale: 0.6 + 0.4 * reveal,
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: _armed ? AppColors.gold : AppColors.surface3,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.reply_rounded, size: 19, color: _armed ? Colors.black : AppColors.muted),
                  ),
                ),
              ),
            ),
          ),
        Transform.translate(offset: Offset(_dx, 0), child: widget.child),
      ]),
    );
  }
}

/// Full-screen photo with pinch to zoom.
class ChatImageViewer extends StatelessWidget {
  const ChatImageViewer({super.key, required this.message});
  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, elevation: 0, title: Text(message.mine ? 'You' : message.teamName)),
      body: SafeArea(
        child: Center(
          child: InteractiveViewer(minScale: 1, maxScale: 5, child: ChatImage(message: message, fit: BoxFit.contain)),
        ),
      ),
    );
  }
}
