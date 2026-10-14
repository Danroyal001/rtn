// POST /api/console/top_up
import 'package:dartvel_core/dartvel.dart';

import '../../core.dart';

@DVBackendFunction()
Future<Map<String, Object?>> _consoleTopUp(
  String session,
  String msisdn,
  String naira,
  String requestId,
) =>
    asConsole(session, () async {
      final int? amount = nairaToUnits(naira);
      if (amount == null) {
        return failure('invalid_amount', 'Enter an amount in naira, like 500.');
      }
      return callCore(
          'POST', '/v1/admin/subscribers/${Uri.encodeComponent(msisdn)}/topup',
          asOperator: true,
          body: <String, Object?>{'amount': amount, 'request_id': requestIdOr(requestId)});
    });
