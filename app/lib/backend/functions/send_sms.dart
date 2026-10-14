// POST /api/send_sms
import 'package:dartvel_core/dartvel.dart';

import '../core.dart';

@DVBackendFunction()
Future<Map<String, Object?>> _sendMessage(
  String token,
  String to,
  String text,
  String requestId,
) =>
    callCore('POST', '/v1/me/sms', bearer: token, body: <String, Object?>{
      'to': to,
      'text': text,
      'request_id': requestIdOr(requestId),
    });
