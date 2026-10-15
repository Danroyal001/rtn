// POST /api/sign_in/console: Checks the console password and starts an operator session.
import 'package:dartvel_core/dartvel.dart';

import '../../../server/console.dart';
import '../../../server/sessions.dart';
import '../../../services/wire.dart';

@DVBackendFunction()
Future<Response> _consoleSignIn(Request request, String password) =>
    sessionResponse(
      request,
      Console.shared.passwordMatches(password)
          ? const Reply<SignedIn>.ok(SignedIn(userId: 'operator', name: 'RTN operator', role: 'operator'))
          : const Reply<SignedIn>.refused('wrong_password', 'That is not the console password.'),
    );
