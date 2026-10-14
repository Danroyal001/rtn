// POST /api/messages: the subscriber's SMS inbox and outbox.
import 'package:dartvel_core/dartvel.dart';

import '../core.dart';

@DVBackendFunction()
Future<Map<String, Object?>> _myMessages(String token) =>
    callCore('GET', '/v1/me/sms', bearer: token);
