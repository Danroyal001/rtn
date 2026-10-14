// POST /api/transfer: send airtime, confirmed with the sender's PIN.
import 'package:dartvel_core/dartvel.dart';

import '../core.dart';

@DVBackendFunction()
Future<Map<String, Object?>> _sendAirtime(
  String token,
  String to,
  String naira,
  String pin,
  String requestId,
) async {
  final int? amount = nairaToUnits(naira);
  if (amount == null) {
    return failure('invalid_amount', 'Enter an amount in naira, like 500.');
  }
  return callCore('POST', '/v1/me/transfer', bearer: token, body: <String, Object?>{
    'to': to,
    'amount': amount,
    'pin': pin,
    'request_id': requestIdOr(requestId),
  });
}
