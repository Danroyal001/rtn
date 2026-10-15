// POST /api/console/simulator: Switches the traffic simulator on or off.
import 'package:dartvel_core/dartvel.dart';

import '../../../server/console.dart';
import '../../../services/wire.dart';

@DVBackendFunction(policy: 'OperatorConsole.update')
Future<Reply<Done>> _consoleSimulator(DVContext ctx, bool running) => Console.shared.setSimulator(running);
