// POST /api/console/reset_pin: Sets a new PIN for a subscriber who forgot theirs.
import 'package:dartvel_core/dartvel.dart';

import '../../../server/console.dart';
import '../../../services/wire.dart';

@DVBackendFunction(policy: 'OperatorConsole.update')
Future<Reply<Done>> _consoleResetPin(DVContext ctx, String msisdn, String pin) =>
    Console.shared.resetPin(msisdn, pin);
