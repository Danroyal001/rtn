// POST /api/me: the signed-in subscriber's line, plan and balances — typed.
import 'package:dartvel_core/dartvel.dart';

import '../core.dart';
import '../models/subscriber.dart';

@DVBackendFunction()
Future<SubscriberLine> _mySummary(String token) async {
  final Map<String, Object?> result = await callCore('GET', '/v1/me', bearer: token);
  if (result['ok'] == true && result['data'] != null) {
    return SubscriberLine.fromCore(result['data']);
  }
  return const SubscriberLine(
    msisdn: '', imsi: '', status: 'unknown', planName: '', balanceUnits: 0, loanUnits: 0, bundles: <DataBundle>[],
  );
}
