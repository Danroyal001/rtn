// POST /api/console/set_plan: Moves a line to another plan.
import 'package:dartvel_core/dartvel.dart';

import '../../../server/console.dart';
import '../../../services/wire.dart';

@DVBackendFunction(policy: 'OperatorConsole.update')
Future<Reply<Done>> _consoleSetPlan(DVContext ctx, String msisdn, String planId) =>
    Console.shared.setPlan(msisdn, planId);
