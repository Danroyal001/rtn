// POST /api/console/care_thread: One conversation with RTN care.
import 'package:dartvel_core/dartvel.dart';

import '../../../server/console.dart';
import '../../../services/wire.dart';

@DVBackendFunction(policy: 'OperatorConsole.view')
Future<Reply<CareChat>> _consoleCareThread(DVContext ctx, String msisdn) =>
    Console.shared.careThread(msisdn);
