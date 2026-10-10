import '../../core/api.dart';
import '../../core/format.dart';

/// The website chat thread this screen talks to. "help" is the site's Agents Chat
/// (help_center_* tables), the one admins and agents answer from the back office.
const String kLiveChatSection = 'help';

/// File name the website uses to recognise a voice note.
const String kVoiceNoteName = 'voice-note.m4a';

/// Longest text the server stores per message.
const int kMaxChatTextLength = 5000;

/// Longest voice note the app records.
const Duration kMaxVoiceNote = Duration(minutes: 3);

const Set<String> _imageTypes = {'image/jpeg', 'image/png', 'image/webp', 'image/gif'};

/// One message of the Live Chat thread (a row of the website's /api/chat/messages).
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.senderRole,
    required this.body,
    this.senderName = '',
    this.createdAt,
    this.attachmentPath = '',
    this.attachmentName = '',
    this.attachmentType = '',
    this.attachmentUrl = '',
    this.replyTo = '',
    this.pending = false,
    this.localFile = '',
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: strOf(json['id']),
        senderRole: strOf(json['sender_role'], 'admin'),
        senderName: strOf(json['sender_display_name']),
        body: strOf(json['body']),
        createdAt: parseTime(json['created_at']),
        attachmentPath: strOf(json['attachment_path']),
        attachmentName: strOf(json['attachment_name']),
        attachmentType: strOf(json['attachment_type']),
        attachmentUrl: strOf(json['attachment_url']),
        replyTo: strOf(json['reply_to']),
      );

  final String id;

  /// "user" = the player, anything else = the DazzlingWins team.
  final String senderRole;
  final String senderName;
  final String body;
  final DateTime? createdAt;
  final String attachmentPath;
  final String attachmentName;
  final String attachmentType;

  /// Short-lived signed link to the private attachment.
  final String attachmentUrl;

  /// Id of the message this one answers.
  final String replyTo;

  /// Still being sent from this phone (not on the server yet).
  final bool pending;

  /// Local file of a [pending] attachment, shown until the upload finishes.
  final String localFile;

  bool get mine => senderRole == 'user';
  bool get hasAttachment => attachmentPath.isNotEmpty || localFile.isNotEmpty;

  String get _mime => attachmentType.split(';').first.trim().toLowerCase();

  bool get isVoice => hasAttachment && (_mime.startsWith('audio/') || attachmentName.startsWith('voice-note.'));
  bool get isImage => hasAttachment && !isVoice && _imageTypes.contains(_mime);

  /// Name shown above a team message.
  String get teamName => senderName.trim().isEmpty ? 'Support' : senderName.trim();

  /// One-line summary used in reply previews (same wording as the website).
  String get preview {
    if (body.isNotEmpty) return body;
    if (isVoice) return 'Voice message';
    if (isImage) return 'Photo';
    return attachmentName.isEmpty ? 'Attachment' : attachmentName;
  }

  ChatMessage withUrl(String url) => ChatMessage(
        id: id,
        senderRole: senderRole,
        senderName: senderName,
        body: body,
        createdAt: createdAt,
        attachmentPath: attachmentPath,
        attachmentName: attachmentName,
        attachmentType: attachmentType,
        attachmentUrl: url,
        replyTo: replyTo,
        pending: pending,
        localFile: localFile,
      );
}

/// "3:07 PM"
String chatClock(DateTime? t) {
  if (t == null) return '';
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}';
}

const List<String> _monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "Today", "Yesterday" or "Oct 9" / "Oct 9, 2025".
String chatDayLabel(DateTime t, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final day = DateTime(t.year, t.month, t.day);
  final diff = DateTime(n.year, n.month, n.day).difference(day).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  final base = '${_monthNames[t.month - 1]} ${t.day}';
  return t.year == n.year ? base : '$base, ${t.year}';
}

bool sameChatDay(DateTime? a, DateTime? b) =>
    a != null && b != null && a.year == b.year && a.month == b.month && a.day == b.day;

/// "0:07", "2:15"
String chatDuration(Duration d) {
  final s = d.inSeconds < 0 ? 0 : d.inSeconds;
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}
