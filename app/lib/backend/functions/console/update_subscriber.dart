// POST /api/console/update_subscriber: bar, unbar, or move to another plan.
import 'package:dartvel_core/dartvel.dart';

import '../../core.dart';

@DVBackendFunction()
Future<Map<String, Object?>> _consoleUpdateSubscriber(
  String session,
  String msisdn,
  String status,
  String planId,
) =>
    asConsole(
      session,
      () => callCore('PATCH', '/v1/admin/subscribers/${Uri.encodeComponent(msisdn)}',
          asOperator: true,
          body: <String, Object?>{
            if (status.isNotEmpty) 'status': status,
            if (planId.isNotEmpty) 'plan_id': planId,
          }),
    );
