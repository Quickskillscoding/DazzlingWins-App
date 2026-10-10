import 'package:dazzlingwins/core/api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('upload file type (never application/octet-stream)', () {
    test('decided from the first bytes', () {
      expect(sniffUploadType([0xFF, 0xD8, 0xFF, 0xE0], 'x.bin'), 'image/jpeg');
      expect(sniffUploadType([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A], 'x'), 'image/png');
      expect(sniffUploadType([0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x45, 0x42, 0x50], 'x'), 'image/webp');
      expect(sniffUploadType([0x47, 0x49, 0x46, 0x38, 0x39, 0x61], 'x'), 'image/gif');
      expect(sniffUploadType([0x1A, 0x45, 0xDF, 0xA3], 'x'), 'audio/webm');
      // An M4A voice note: 4 size bytes, then "ftyp".
      expect(sniffUploadType([0, 0, 0, 0x18, 0x66, 0x74, 0x79, 0x70, 0x6D, 0x70, 0x34, 0x32], 'voice-note.m4a'), 'audio/mp4');
    });

    test('falls back to the extension, then to unknown', () {
      expect(sniffUploadType(const [], '/tmp/photo.JPG'), 'image/jpeg');
      expect(sniffUploadType(const [], '/tmp/dw-voice-1.m4a'), 'audio/mp4');
      expect(sniffUploadType(const [1, 2, 3], '/tmp/file.xyz'), isNull);
      expect(sniffUploadType(const [], 'noextension'), isNull);
    });
  });
}
