import 'package:dazzlingwins/core/updater.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('in-app updater', () {
    test('only downloads the APK from the official GitHub release over HTTPS', () {
      expect(isTrustedApkUrl('https://github.com/Quickskillscoding/DazzlingWins-App/releases/download/v1.0.22/DazzlingWins.apk'), isTrue);
      expect(isTrustedApkUrl('http://github.com/Quickskillscoding/DazzlingWins-App/releases/download/v1.0.22/DazzlingWins.apk'), isFalse);
      expect(isTrustedApkUrl('https://github.com.evil.example/x/DazzlingWins.apk'), isFalse);
      expect(isTrustedApkUrl('https://example.com/DazzlingWins.apk'), isFalse);
      expect(isTrustedApkUrl('https://github.com/Quickskillscoding/DazzlingWins-App/releases'), isFalse);
      expect(isTrustedApkUrl(''), isFalse);
    });

    test('reads the published checksum line', () {
      const hash = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
      expect(parseSha256Line('$hash  dist/DazzlingWins.apk\n'), hash);
      expect(parseSha256Line(hash.toUpperCase()), hash);
      expect(parseSha256Line('Not Found'), isNull);
      expect(parseSha256Line(''), isNull);
      expect(parseSha256Line('<html>'), isNull);
    });
  });
}
