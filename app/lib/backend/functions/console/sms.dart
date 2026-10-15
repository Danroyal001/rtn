// POST /api/console/sms: The SMS centre's latest messages.
import 'package:dartvel_core/dartvel.dart';

import '../../../server/console.dart';
import '../../../services/wire.dart';

@DVBackendFunction(policy: 'OperatorConsole.view')
Future<Reply<Inbox>> _consoleSms(DVContext ctx, int limit) => Console.shared.smsLog(limit);
