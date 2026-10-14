// The server side: money parsing, console sessions, and how a core answer
// becomes the one shape every backend function returns.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rtn_app/backend/core.dart';

void main() {
  group('nairaToUnits', () {
    test('reads what people type', () {
      expect(nairaToUnits('500'), 50000);
      expect(nairaToUnits('1,500'), 150000);
      expect(nairaToUnits('₦250.5'), 25050);
      expect(nairaToUnits(' 0.05 '), 5);
    });

    test('refuses what is not an amount', () {
      expect(nairaToUnits(''), isNull);
      expect(nairaToUnits('abc'), isNull);
      expect(nairaToUnits('1.234'), isNull);
      expect(nairaToUnits('-5'), isNull);
    });
  });

  group('console sessions', () {
    // Platform.environment is read-only, so these run against whatever the
    // test process has; without RTN_CONSOLE_PASSWORD no session can open.
    test('a forged or expired session is refused', () {
      expect(consoleSessionValid(''), isFalse);
      expect(consoleSessionValid('not-a-session'), isFalse);
      expect(consoleSessionValid('99999999999999.deadbeef'), isFalse);
      expect(consoleSessionValid('1.abc'), isFalse);
    });

    test('opens only with the configured password', () {
      final String? configured = Platform.environment['RTN_CONSOLE_PASSWORD'];
      expect(openConsoleSession('wrong-password-${DateTime.now()}'), isNull);
      if (configured == null || configured.isEmpty) {
        expect(openConsoleSession(''), isNull);
        return;
      }
      final String session = openConsoleSession(configured)!;
      expect(consoleSessionValid(session), isTrue);
      expect(consoleSessionValid(session, now: DateTime.now().add(const Duration(hours: 9))), isFalse);
      final String tampered = '${int.parse(session.split('.').first) + 1}.${session.split('.').last}';
      expect(consoleSessionValid(tampered), isFalse);
    });
  });

  group('callCore', () {
    late HttpServer server;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((HttpRequest request) async {
        final String body = await utf8.decoder.bind(request).join();
        request.response.headers.contentType = ContentType.json;
        switch (request.uri.path) {
          case '/ok':
            request.response.write(jsonEncode(<String, Object?>{
              'method': request.method,
              'auth': request.headers.value('authorization'),
              'body': body.isEmpty ? null : jsonDecode(body),
            }));
          case '/refused':
            request.response.statusCode = 402;
            request.response.write(jsonEncode(<String, Object?>{
              'error': <String, Object?>{'code': 'insufficient_funds', 'message': 'not enough airtime'},
            }));
          default:
            request.response.statusCode = 500;
            request.response.write('<html>');
        }
        await request.response.close();
      });
    });

    tearDown(() => server.close(force: true));

    String at(String path) => 'http://127.0.0.1:${server.port}$path';

    test('wraps a success with the bearer and body it sent', () async {
      final Map<String, Object?> answer =
          await callCoreAt(at('/ok'), 'POST', body: <String, Object?>{'x': 1}, bearer: 'tok');
      expect(answer['ok'], isTrue);
      final Map<Object?, Object?> data = answer['data']! as Map<Object?, Object?>;
      expect(data['method'], 'POST');
      expect(data['auth'], 'Bearer tok');
      expect(data['body'], <String, Object?>{'x': 1});
    });

    test("passes the core's refusal through with its code", () async {
      final Map<String, Object?> answer = await callCoreAt(at('/refused'), 'GET');
      expect(answer, <String, Object?>{
        'ok': false,
        'code': 'insufficient_funds',
        'message': 'not enough airtime',
      });
    });

    test('names a garbled answer and an unreachable core', () async {
      expect((await callCoreAt(at('/broken'), 'GET'))['code'], 'core_garbled');
      final int port = server.port;
      await server.close(force: true);
      expect((await callCoreAt('http://127.0.0.1:$port/ok', 'GET'))['code'], 'core_unreachable');
    });
  });
}
