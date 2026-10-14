// POST /api/sign_out
import 'package:dartvel_core/dartvel.dart';

import '../core.dart';

@DVBackendFunction()
Future<Map<String, Object?>> _subscriberSignOut(String token) =>
    callCore('POST', '/v1/auth/logout', bearer: token);
