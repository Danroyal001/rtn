// POST /api/history: the subscriber's ledger, newest first.
import 'package:dartvel_core/dartvel.dart';

import '../core.dart';

@DVBackendFunction()
Future<Map<String, Object?>> _myHistory(String token) =>
    callCore('GET', '/v1/me/history?limit=100', bearer: token);
