// POST /api/console/set_status: Bars a line or lifts the bar.
import 'package:dartvel_core/dartvel.dart';

import '../../../server/console.dart';
import '../../../services/wire.dart';

@DVBackendFunction(policy: 'OperatorConsole.update')
Future<Reply<Done>> _consoleSetStatus(DVContext ctx, String msisdn, String status) =>
    Console.shared.setStatus(msisdn, status);
