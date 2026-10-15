// POST /api/console/add_subscriber: Adds a subscriber.
import 'package:dartvel_core/dartvel.dart';

import '../../../server/console.dart';
import '../../../services/wire.dart';

@DVBackendFunction(policy: 'OperatorConsole.update')
Future<Reply<Subscriber>> _consoleAddSubscriber(DVContext ctx, String msisdn, String name, String pin, String planId) =>
    Console.shared.addSubscriber(msisdn, name, pin, planId);
