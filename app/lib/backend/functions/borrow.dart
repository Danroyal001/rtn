// POST /api/borrow: an airtime loan, repaid from the next top-up.
import 'package:dartvel_core/dartvel.dart';

import '../core.dart';

@DVBackendFunction()
Future<Map<String, Object?>> _borrowAirtime(
  String token,
  int amount,
  String requestId,
) =>
    callCore('POST', '/v1/me/borrow', bearer: token, body: <String, Object?>{
      'amount': amount,
      'request_id': requestIdOr(requestId),
    });
