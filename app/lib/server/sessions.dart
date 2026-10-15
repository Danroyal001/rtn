// Turning a checked sign-in into a Dartvel session.
//
// Dartvel 0.12.2 signs people in with an e-mail address and a password, and
// has no phone or one-time-code flow, so MyRTN checks the code itself (the
// RTN core sent it by SMS) and then asks Dartvel's session store for a
// session, exactly as Dartvel's own sign-in endpoint does: a cookie for a
// browser, the token in the body for a device that asked for it. Everything
// after that is Dartvel's: the session is checked on every request, policies
// read its role, and `/api/auth/sign-out` ends it.
import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';

import '../services/wire.dart';

/// Answers a sign-in: a new session for [who] when it is ok, the refusal when
/// it is not. The body is a [Reply] of [SignedIn] either way.
Future<Response> sessionResponse(Request request, Reply<SignedIn> who) async {
  if (!who.ok) return _json(200, who.toJson());
  final DVSessionAuthentication? stage = DVSessionAuthentication.installed;
  if (stage == null) {
    return _json(503, const Reply<SignedIn>.refused('no_sessions', 'Signing in is not available right now.').toJson());
  }
  final DVIssuedSession issued = await DVSessionAuthentication.sessions.create(
    who.result.userId,
    device: request.headers.get('user-agent'),
    claims: <String, Object?>{'role': who.result.role, 'name': who.result.name},
  );
  final bool asToken = DVAuthEndpoints.deliversToken(request);
  final bool plain = stage.development ||
      DVSessionCookie.plainLocal(
        request.url,
        forwardedProto: request.headers.get('x-forwarded-proto'),
        host: request.headers.get('host'),
      );
  final SignedIn signedIn = SignedIn(
    userId: who.result.userId,
    name: who.result.name,
    role: who.result.role,
    token: asToken ? issued.token : '',
  );
  return _json(
    200,
    Reply<SignedIn>.ok(signedIn).toJson(),
    cookie: asToken ? null : stage.cookie.header(issued.token, development: plain),
  );
}

Response _json(int status, Map<String, Object?> body, {String? cookie}) => Response(
      status,
      headers: Headers(<String, String>{
        'content-type': 'application/json; charset=utf-8',
        'cache-control': 'no-store',
        'set-cookie': ?cookie,
      }),
      body: Stream<List<int>>.value(utf8.encode(jsonEncode(body))),
    );
