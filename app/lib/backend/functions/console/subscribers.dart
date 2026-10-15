// POST /api/console/subscribers: Searches and pages through subscribers.
import 'package:dartvel_core/dartvel.dart';

import '../../../server/console.dart';
import '../../../services/wire.dart';

@DVBackendFunction(policy: 'OperatorConsole.view')
Future<Reply<SubscriberPage>> _consoleSubscribers(DVContext ctx, String search, int offset) =>
    Console.shared.subscribers(search, offset);
