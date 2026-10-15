// POST /api/console/traffic: Live traffic and money totals.
import 'package:dartvel_core/dartvel.dart';

import '../../../server/console.dart';
import '../../../services/wire.dart';

@DVBackendFunction(policy: 'OperatorConsole.view')
Future<Reply<Traffic>> _consoleTraffic(DVContext ctx) => Console.shared.traffic();
