// POST /api/console/care_reply: An agent answers a subscriber.
import 'package:dartvel_core/dartvel.dart';

import '../../../server/console.dart';
import '../../../services/wire.dart';

@DVBackendFunction(policy: 'OperatorConsole.update')
Future<Reply<CareChat>> _consoleCareReply(DVContext ctx, String msisdn, String text) =>
    Console.shared.careReply(msisdn, text);
