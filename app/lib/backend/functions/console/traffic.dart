// POST /api/console/traffic: the live view.
import 'package:dartvel_core/dartvel.dart';

import '../../core.dart';

@DVBackendFunction()
Future<Map<String, Object?>> _consoleTraffic(String session) => asConsole(
    session, () => callCore('GET', '/v1/admin/traffic', asOperator: true));
