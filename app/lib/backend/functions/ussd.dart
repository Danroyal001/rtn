// POST /api/ussd: one step of a USSD session, as the subscriber's handset.
import 'package:dartvel_core/dartvel.dart';

import '../core.dart';

@DVBackendFunction()
Future<Map<String, Object?>> _dialUssd(
  String token,
  String msisdn,
  String sessionId,
  String input,
) =>
    callCore('POST', '/v1/ussd', bearer: token, body: <String, Object?>{
      'session_id': sessionId,
      'msisdn': msisdn,
      'input': input,
    });
