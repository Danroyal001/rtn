// POST /api/console/sign_in: the operator signs in to the console.
import 'package:dartvel_core/dartvel.dart';

import '../../core.dart';

@DVBackendFunction()
Future<Map<String, Object?>> _consoleSignIn(String password) async {
  final String? session = openConsoleSession(password);
  if (session == null) {
    return failure('wrong_password', 'That is not the console password.');
  }
  return success(<String, Object?>{'session': session});
}
