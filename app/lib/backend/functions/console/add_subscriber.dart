// POST /api/console/add_subscriber
import 'package:dartvel_core/dartvel.dart';

import '../../core.dart';

@DVBackendFunction()
Future<Map<String, Object?>> _consoleAddSubscriber(
  String session,
  String msisdn,
  String name,
  String pin,
  String planId,
) =>
    asConsole(
      session,
      () => callCore('POST', '/v1/admin/subscribers', asOperator: true, body: <String, Object?>{
        'msisdn': msisdn,
        'name': name,
        'pin': pin,
        if (planId.isNotEmpty) 'plan_id': planId,
      }),
    );
