// POST /api/console/simulator: switch the traffic simulator on or off.
import 'package:dartvel_core/dartvel.dart';

import '../../core.dart';

@DVBackendFunction()
Future<Map<String, Object?>> _consoleSimulator(String session, bool running) =>
    asConsole(
      session,
      () => callCore('PATCH', '/v1/admin/simulator',
          asOperator: true, body: <String, Object?>{'running': running}),
    );
