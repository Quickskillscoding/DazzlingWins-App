import 'package:dazzlingwins/features/chat/chat_models.dart';
import 'package:dazzlingwins/features/chat/emoji_panel.dart';
import 'package:flutter_test/flutter_test.dart';

ChatMessage _m(Map<String, dynamic> extra) => ChatMessage.fromJson({'id': 'm1', 'sender_role': 'user', 'body': '', ...extra});

void main() {
  group('live chat messages', () {
    test('talks to the website Agents Chat thread', () {
      expect(kLiveChatSection, 'help');
      expect(kVoiceNoteName.startsWith('voice-note.'), isTrue);
    });

    test('text message', () {
      final m = _m({'body': 'hello', 'created_at': '2026-10-10T10:00:00.000Z'});
      expect(m.mine, isTrue);
      expect(m.hasAttachment, isFalse);
      expect(m.isImage, isFalse);
      expect(m.isVoice, isFalse);
      expect(m.preview, 'hello');
      expect(m.createdAt, isNotNull);
    });

    test('photo and voice note are told apart like on the website', () {
      final photo = _m({'attachment_path': 'u/1.jpg', 'attachment_name': 'pic.jpg', 'attachment_type': 'image/jpeg'});
      expect(photo.isImage, isTrue);
      expect(photo.isVoice, isFalse);
      expect(photo.preview, 'Photo');

      final appVoice = _m({'attachment_path': 'u/2.m4a', 'attachment_name': 'voice-note.m4a', 'attachment_type': 'audio/mp4'});
      final webVoice = _m({'attachment_path': 'u/3.webm', 'attachment_name': 'voice-note.webm', 'attachment_type': 'audio/webm;codecs=opus'});
      for (final v in [appVoice, webVoice]) {
        expect(v.isVoice, isTrue);
        expect(v.isImage, isFalse);
        expect(v.preview, 'Voice message');
      }
    });

    test('team message name falls back to Support', () {
      expect(_m({'sender_role': 'admin'}).teamName, 'Support');
      expect(_m({'sender_role': 'admin', 'sender_display_name': 'Dazzlingwins Agent'}).teamName, 'Dazzlingwins Agent');
      expect(_m({'sender_role': 'admin'}).mine, isFalse);
    });

    test('withUrl keeps everything else', () {
      final m = _m({'body': 'x', 'attachment_path': 'u/1.jpg', 'attachment_type': 'image/png', 'reply_to': 'm0'}).withUrl('https://x/y');
      expect(m.attachmentUrl, 'https://x/y');
      expect(m.replyTo, 'm0');
      expect(m.body, 'x');
      expect(m.isImage, isTrue);
    });
  });

  group('chat formatting', () {
    test('clock, duration and day labels', () {
      expect(chatClock(DateTime(2026, 10, 10, 15, 7)), '3:07 PM');
      expect(chatClock(DateTime(2026, 10, 10, 0, 5)), '12:05 AM');
      expect(chatDuration(const Duration(seconds: 7)), '0:07');
      expect(chatDuration(const Duration(seconds: 135)), '2:15');
      final now = DateTime(2026, 10, 10, 9);
      expect(chatDayLabel(DateTime(2026, 10, 10, 1), now: now), 'Today');
      expect(chatDayLabel(DateTime(2026, 10, 9, 23), now: now), 'Yesterday');
      expect(chatDayLabel(DateTime(2026, 10, 3), now: now), 'Oct 3');
      expect(chatDayLabel(DateTime(2025, 12, 31), now: now), 'Dec 31, 2025');
      expect(sameChatDay(DateTime(2026, 10, 10, 1), DateTime(2026, 10, 10, 23)), isTrue);
      expect(sameChatDay(DateTime(2026, 10, 10), null), isFalse);
    });

    test('emoji list has no duplicates', () {
      expect(kChatEmoji.toSet().length, kChatEmoji.length);
      expect(kChatEmoji, contains('👍'));
    });
  });
}
