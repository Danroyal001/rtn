// Signing in and out on this device.
//
// The backend checks the sign-in and issues a Dartvel session (see
// lib/server/sessions.dart); this side adopts it, so `DV.Session` knows who is
// signed in and every later call carries the session.
import 'package:flutter/foundation.dart' show kIsWeb;

import '../dartvel_client/dartvel_client.dart';
import 'remote.dart';
import 'wire.dart';

/// A device (not a browser) asks for the session token in the body, since it
/// has no cookie jar the server can write to.
const Map<String, String> _delivery = <String, String>{'x-dartvel-session-delivery': 'token'};

Future<Reply<SignedIn>> _adopt(Reply<SignedIn> who) async {
  if (!who.ok) return who;
  final DVSessionClient? sessions = DVSessionClient.installed;
  if (!kIsWeb && who.result.token.isNotEmpty) {
    await dvSessionTokenStoreFor('rtn_app')?.write(who.result.token);
    DartvelClient.setAuthToken(who.result.token);
    await sessions?.restore();
  } else {
    await sessions?.refresh();
  }
  return who;
}

// The two sign-in functions take the request itself, to set the session
// cookie, so Dartvel 0.12.2 generates no typed call for them: these are the
// only calls in the app that name their fields.

/// Checks a subscriber's sign-in code and starts their session here.
Future<Reply<SignedIn>> signInWithCode(String msisdn, String code) => ask(() async => _adopt(
      await postSignInVerifyCodeAs<Reply<SignedIn>>(
        Reply.of(SignedIn.fromJson),
        body: <String, Object?>{'msisdn': msisdn, 'code': code},
        headers: kIsWeb ? null : _delivery,
      ),
    ));

/// Checks the console password and starts an operator session here.
Future<Reply<SignedIn>> signInToConsole(String password) => ask(() async => _adopt(
      await postSignInConsoleAs<Reply<SignedIn>>(
        Reply.of(SignedIn.fromJson),
        body: <String, Object?>{'password': password},
        headers: kIsWeb ? null : _delivery,
      ),
    ));

/// Ends the session on the server and forgets it here.
Future<void> signOut() async {
  try {
    await DVSessionClient.installed?.signOut();
  } on Object {
    // Signed out here either way; a session the server still holds expires.
  }
}

/// The role of whoever is signed in here: 'subscriber', 'operator' or ''.
String roleOf(DVSession? session) => '${session?.claims['role'] ?? ''}';
