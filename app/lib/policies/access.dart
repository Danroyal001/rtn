// Who may call which backend functions. Dartvel asks these on every call to a
// function that names them (`@DVBackendFunction(policy: 'SubscriberLine.view')`);
// a request with no session is answered 401 before the function runs, and a
// session of the wrong kind 403.
//
// The role is a claim on the Dartvel session, set when it was issued: by the
// sign-in code for a subscriber, by the console password for the operator.
import 'package:dartvel_core/dartvel.dart';

/// A subscriber's own line. The line itself is the session's user id.
class SubscriberLine {
  const SubscriberLine();
}

@DVPolicy(SubscriberLine)
class SubscriberLinePolicy {
  const SubscriberLinePolicy();

  Future<bool> view(DVSessionPrincipal caller, SubscriberLine? line) async => caller.claims['role'] == 'subscriber';

  Future<bool> update(DVSessionPrincipal caller, SubscriberLine? line) async => caller.claims['role'] == 'subscriber';
}

/// The operator console.
class OperatorConsole {
  const OperatorConsole();
}

@DVPolicy(OperatorConsole)
class OperatorConsolePolicy {
  const OperatorConsolePolicy();

  Future<bool> view(DVSessionPrincipal caller, OperatorConsole? console) async => caller.claims['role'] == 'operator';

  Future<bool> update(DVSessionPrincipal caller, OperatorConsole? console) async => caller.claims['role'] == 'operator';
}
