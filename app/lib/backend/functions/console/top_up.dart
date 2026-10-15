// POST /api/console/top_up: Tops a line up.
import 'package:dartvel_core/dartvel.dart';

import '../../../server/console.dart';
import '../../../services/wire.dart';

@DVBackendFunction(policy: 'OperatorConsole.update')
Future<Reply<Outcome>> _consoleTopUp(DVContext ctx, String msisdn, String amount, String attempt) =>
    Console.shared.topUp(msisdn, amount, attempt);
