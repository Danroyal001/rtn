// POST /api/console/care_desk: Every conversation with RTN care.
import 'package:dartvel_core/dartvel.dart';

import '../../../server/console.dart';
import '../../../services/wire.dart';

@DVBackendFunction(policy: 'OperatorConsole.view')
Future<Reply<CareDesk>> _consoleCareDesk(DVContext ctx) =>
    Console.shared.careDesk();
