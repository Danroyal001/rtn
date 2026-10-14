// POST /api/me: the signed-in subscriber's line, plan and balances.
import 'package:dartvel_core/dartvel.dart';

import '../core.dart';

@DVBackendFunction()
Future<Map<String, Object?>> _mySummary(String token) =>
    callCore('GET', '/v1/me', bearer: token);
