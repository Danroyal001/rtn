// The server's line to the RTN core: the Rust HTTP API, reached from the
// Dartvel backend only. Pages never call the core directly, and the browser
// never holds the operator's token.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Where the core's API listens. `demo.sh` sets it; the default is the
/// address `rtn serve` uses.
String get coreUrl =>
    Platform.environment['RTN_CORE_URL'] ?? 'http://127.0.0.1:8700';

String get _adminToken => Platform.environment['RTN_ADMIN_TOKEN'] ?? '';

/// Every backend function answers in one shape, so a page handles a refusal
/// the same way everywhere: `{ok: true, data: ...}` or
/// `{ok: false, code: ..., message: ...}`.
Map<String, Object?> success(Object? data) =>
    <String, Object?>{'ok': true, 'data': data};

Map<String, Object?> failure(String code, String message) =>
    <String, Object?>{'ok': false, 'code': code, 'message': message};

/// Calls the core. [bearer] is a subscriber's token; [asOperator] sends the
/// operator's token from the server's environment instead.
Future<Map<String, Object?>> callCore(
  String method,
  String path, {
  Object? body,
  String? bearer,
  bool asOperator = false,
}) =>
    callCoreAt('$coreUrl$path', method, body: body, bearer: asOperator ? _adminToken : bearer);

/// [callCore] against a full URL.
Future<Map<String, Object?>> callCoreAt(
  String url,
  String method, {
  Object? body,
  String? bearer,
}) async {
  final HttpClient client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 5);
  try {
    final HttpClientRequest request = await client.openUrl(method, Uri.parse(url));
    final String? token = bearer;
    if (token != null && token.isNotEmpty) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.add(utf8.encode(jsonEncode(body)));
    }
    final HttpClientResponse response =
        await request.close().timeout(const Duration(seconds: 10));
    final String text = await response.transform(utf8.decoder).join();
    final Object? decoded = text.isEmpty ? null : jsonDecode(text);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return success(decoded);
    }
    final Object? error = decoded is Map ? decoded['error'] : null;
    if (error is Map) {
      return failure('${error['code']}', '${error['message']}');
    }
    return failure('http_${response.statusCode}', 'The network refused that.');
  } on SocketException {
    return failure('core_unreachable', 'The RTN core is not reachable.');
  } on HandshakeException {
    return failure('core_unreachable', 'The RTN core is not reachable.');
  } on FormatException {
    return failure('core_garbled', 'The RTN core sent something unreadable.');
  } finally {
    client.close();
  }
}

/// Naira typed by a person ("1,500", "250.50") in minor units, or null.
int? nairaToUnits(String text) {
  final String cleaned = text.replaceAll(',', '').replaceAll('₦', '').trim();
  final RegExpMatch? match =
      RegExp(r'^(\d{1,9})(?:\.(\d{1,2}))?$').firstMatch(cleaned);
  if (match == null) return null;
  final int whole = int.parse(match.group(1)!);
  final String fraction = (match.group(2) ?? '').padRight(2, '0');
  return whole * 100 + int.parse(fraction);
}

// ----- console sessions ---------------------------------------------------
//
// The operator signs in to the console with RTN_CONSOLE_PASSWORD. What the
// browser keeps is a signed expiry, not the core's admin token: every console
// function checks the signature and then calls the core with the token the
// server holds.

const Duration consoleSessionLength = Duration(hours: 8);

String get _consoleKey =>
    Platform.environment['RTN_CONSOLE_SECRET'] ?? 'rtn-console:$_adminToken';

String _sign(String payload) =>
    Hmac(sha256, utf8.encode(_consoleKey)).convert(utf8.encode(payload)).toString();

bool _sameText(String a, String b) {
  final List<int> left = sha256.convert(utf8.encode(a)).bytes;
  final List<int> right = sha256.convert(utf8.encode(b)).bytes;
  int difference = 0;
  for (int i = 0; i < left.length; i++) {
    difference |= left[i] ^ right[i];
  }
  return difference == 0;
}

/// A console session for [password], or null when it is wrong or the server
/// has no console password set.
String? openConsoleSession(String password, {DateTime? now}) {
  final String expected = Platform.environment['RTN_CONSOLE_PASSWORD'] ?? '';
  if (expected.isEmpty || _adminToken.isEmpty) return null;
  if (!_sameText(password, expected)) return null;
  final int expires =
      (now ?? DateTime.now()).add(consoleSessionLength).millisecondsSinceEpoch;
  return '$expires.${_sign('$expires')}';
}

/// Whether [session] was signed by this server and has not expired.
bool consoleSessionValid(String session, {DateTime? now}) {
  final int dot = session.indexOf('.');
  if (dot <= 0) return false;
  final String expires = session.substring(0, dot);
  final int? at = int.tryParse(expires);
  if (at == null) return false;
  if (at <= (now ?? DateTime.now()).millisecondsSinceEpoch) return false;
  return _sameText(session.substring(dot + 1), _sign(expires));
}

/// Runs [action] for a signed-in operator, or answers that they are not.
Future<Map<String, Object?>> asConsole(
  String session,
  Future<Map<String, Object?>> Function() action,
) {
  if (!consoleSessionValid(session)) {
    return Future<Map<String, Object?>>.value(
      failure('console_signed_out', 'Sign in to the console again.'),
    );
  }
  return action();
}

/// A request id the core can use to recognise a retry: the one the page sent,
/// or a fresh one when it sent none.
String requestIdOr(String given) => given.trim().isNotEmpty
    ? given.trim()
    : 'app-${DateTime.now().microsecondsSinceEpoch}';
