// POST /api/sign_in: a subscriber signs in with their number and PIN.
import 'package:dartvel_core/dartvel.dart';

import '../core.dart';

@DVBackendFunction()
Future<Map<String, Object?>> _subscriberSignIn(String msisdn, String pin) =>
    callCore('POST', '/v1/auth/login',
        body: <String, Object?>{'msisdn': msisdn, 'pin': pin});
