// POST /api/console/subscriber: One subscriber's file.
import 'package:dartvel_core/dartvel.dart';

import '../../../server/console.dart';
import '../../../services/wire.dart';

@DVBackendFunction(policy: 'OperatorConsole.view')
Future<Reply<SubscriberFile>> _consoleSubscriber(DVContext ctx, String msisdn) =>
    Console.shared.subscriber(msisdn);
