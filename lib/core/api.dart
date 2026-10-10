import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'config.dart';
import 'session.dart';

/// A failed API call, with the website's own (player-friendly) error message.
class ApiException implements Exception {
  ApiException(this.message, {this.status = 0, this.data = const {}});
  final String message;
  final int status;
  final Map<String, dynamic> data;

  bool get unauthorized => status == 401;
  bool get kycRequired => data['kycRequired'] == true;
  bool get captchaRequired => data['captchaRequired'] == true;

  @override
  String toString() => message;
}

/// MIME type of an upload, decided from the file's first bytes (the same check the server makes),
/// falling back to its extension. Null when unknown: the part is then sent untyped.
String? sniffUploadType(List<int> head, String path) {
  bool at(int offset, List<int> sig) {
    if (head.length < offset + sig.length) return false;
    for (var i = 0; i < sig.length; i++) {
      if (head[offset + i] != sig[i]) return false;
    }
    return true;
  }

  if (at(0, const [0xFF, 0xD8, 0xFF])) return 'image/jpeg';
  if (at(0, const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) return 'image/png';
  if (at(0, const [0x52, 0x49, 0x46, 0x46]) && at(8, const [0x57, 0x45, 0x42, 0x50])) return 'image/webp';
  if (at(0, const [0x47, 0x49, 0x46, 0x38])) return 'image/gif';
  if (at(0, const [0x1A, 0x45, 0xDF, 0xA3])) return 'audio/webm';
  if (at(4, const [0x66, 0x74, 0x79, 0x70])) return 'audio/mp4'; // "ftyp": M4A voice note
  final dot = path.lastIndexOf('.');
  switch (dot < 0 ? '' : path.substring(dot + 1).toLowerCase()) {
    case 'jpg' || 'jpeg':
      return 'image/jpeg';
    case 'png':
      return 'image/png';
    case 'webp':
      return 'image/webp';
    case 'gif':
      return 'image/gif';
    case 'webm':
      return 'audio/webm';
    case 'm4a' || 'mp4':
      return 'audio/mp4';
  }
  return null;
}

/// [sniffUploadType] for a file on disk.
Future<MediaType?> uploadMediaType(String path) async {
  var head = const <int>[];
  try {
    head = await File(path).openRead(0, 16).fold<List<int>>(<int>[], (all, chunk) => all..addAll(chunk));
  } catch (_) {
    // Unreadable: decide by extension.
  }
  final type = sniffUploadType(head, path);
  return type == null ? null : MediaType.parse(type);
}

/// One file in a multipart upload.
class UploadFile {
  UploadFile(this.field, this.path, {this.filename});
  final String field;
  final String path;
  final String? filename;
}

/// Thin client for the website API. Adds the Bearer token, refreshes it once on expiry,
/// times out cleanly and turns every failure into an [ApiException] with a readable message.
class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  final http.Client _http = http.Client();
  Future<bool>? _refreshing;

  /// Called when the session is gone for good (refresh refused): the app returns to sign-in.
  void Function()? onSignedOut;

  Map<String, String> _headers({bool json = true}) {
    final token = Session.instance.accessToken;
    return {
      'Accept': 'application/json',
      'X-Client': 'dazzlingwins-android',
      if (json) 'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<Map<String, dynamic>> get(String path, {Map<String, String>? query, bool auth = true}) =>
      _send(() => _http.get(AppConfig.uri(path, query), headers: _headers(json: false)), auth: auth);

  Future<Map<String, dynamic>> post(String path, Object? body, {bool auth = true}) =>
      _send(() => _http.post(AppConfig.uri(path), headers: _headers(), body: jsonEncode(body ?? const {})), auth: auth);

  Future<Map<String, dynamic>> patch(String path, Object? body) =>
      _send(() => _http.patch(AppConfig.uri(path), headers: _headers(), body: jsonEncode(body ?? const {})));

  Future<Map<String, dynamic>> delete(String path, Object? body) =>
      _send(() => _http.delete(AppConfig.uri(path), headers: _headers(), body: jsonEncode(body ?? const {})));

  /// multipart/form-data (payment proof, KYC photos, withdraw QR).
  Future<Map<String, dynamic>> multipart(String path, Map<String, String> fields, List<UploadFile> files) {
    return _send(() async {
      final request = http.MultipartRequest('POST', AppConfig.uri(path));
      request.headers.addAll(_headers(json: false));
      request.fields.addAll(fields);
      for (final f in files) {
        // Label the file with its real type. Without this every upload goes out as
        // application/octet-stream, which the website's storage refuses.
        request.files.add(await http.MultipartFile.fromPath(f.field, f.path, filename: f.filename, contentType: await uploadMediaType(f.path)));
      }
      final streamed = await _http.send(request).timeout(AppConfig.uploadTimeout);
      return http.Response.fromStream(streamed);
    }, timeout: AppConfig.uploadTimeout);
  }

  Future<Map<String, dynamic>> _send(
    Future<http.Response> Function() call, {
    bool auth = true,
    Duration timeout = AppConfig.requestTimeout,
    bool retried = false,
  }) async {
    if (auth && Session.instance.isSignedIn && Session.instance.needsRefresh) {
      await _refresh();
    }
    http.Response res;
    try {
      res = await call().timeout(timeout);
    } on TimeoutException {
      throw ApiException('The connection is slow. Please try again.');
    } on SocketException {
      throw ApiException('No internet connection. Check your network and try again.');
    } on HandshakeException {
      throw ApiException('Secure connection failed. Check your network and try again.');
    } on http.ClientException {
      throw ApiException('Could not reach DazzlingWins. Please try again.');
    }

    if (res.statusCode == 401 && auth && !retried && Session.instance.refreshToken != null) {
      final ok = await _refresh();
      if (ok) return _send(call, auth: auth, timeout: timeout, retried: true);
    }

    final data = _decode(res.body);
    if (res.statusCode >= 200 && res.statusCode < 300) return data;

    final message = (data['error'] is String && (data['error'] as String).trim().isNotEmpty)
        ? data['error'] as String
        : res.statusCode == 429
            ? 'Too many tries. Please wait a moment.'
            : res.statusCode >= 500
                ? 'Something went wrong on our side. Please try again.'
                : 'Request failed (${res.statusCode}).';
    if (res.statusCode == 401 && auth) {
      await Session.instance.clear();
      onSignedOut?.call();
    }
    throw ApiException(message, status: res.statusCode, data: data);
  }

  Map<String, dynamic> _decode(String body) {
    if (body.isEmpty) return {};
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : {'data': decoded};
    } catch (_) {
      return {};
    }
  }

  /// One refresh at a time, shared by every request that needs it.
  Future<bool> _refresh() {
    return _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);
  }

  Future<bool> _doRefresh() async {
    final refresh = Session.instance.refreshToken;
    if (refresh == null) return false;
    try {
      final res = await _http
          .post(
            AppConfig.uri('/api/auth/token/refresh'),
            headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
            body: jsonEncode({'refreshToken': refresh}),
          )
          .timeout(AppConfig.requestTimeout);
      final data = _decode(res.body);
      if (res.statusCode == 200 && data['session'] is Map<String, dynamic>) {
        await Session.instance.saveFromJson(data['session'] as Map<String, dynamic>,
            user: data['user'] as Map<String, dynamic>?);
        return true;
      }
      if (res.statusCode == 401 || res.statusCode == 403) {
        await Session.instance.clear();
        onSignedOut?.call();
      }
      return false;
    } catch (_) {
      return false; // network trouble: keep the session, the request reports the error
    }
  }
}

/// Safe number from JSON (num, numeric string, null).
double numOf(Object? v, [double fallback = 0]) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? fallback;
  return fallback;
}

String strOf(Object? v, [String fallback = '']) => v == null ? fallback : v.toString();

List<Map<String, dynamic>> listOf(Object? v) =>
    v is List ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : <Map<String, dynamic>>[];

Map<String, dynamic> mapOf(Object? v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
