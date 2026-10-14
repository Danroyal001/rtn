// POST /api/console/subscriber: one line, its balances and recent history.
import 'package:dartvel_core/dartvel.dart';

import '../../core.dart';

@DVBackendFunction()
Future<Map<String, Object?>> _consoleSubscriber(String session, String msisdn) =>
    asConsole(
      session,
      () => callCore('GET', '/v1/admin/subscribers/${Uri.encodeComponent(msisdn)}',
          asOperator: true),
    );
