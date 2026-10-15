// POST /api/console/ledger: The network's latest ledger entries.
import 'package:dartvel_core/dartvel.dart';

import '../../../server/console.dart';
import '../../../services/wire.dart';

@DVBackendFunction(policy: 'OperatorConsole.view')
Future<Reply<LedgerPage>> _consoleLedger(DVContext ctx, int limit) =>
    Console.shared.ledger(limit);
