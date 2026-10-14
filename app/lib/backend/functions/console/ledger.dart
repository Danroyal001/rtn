// POST /api/console/ledger: the latest ledger entries across the network.
import 'package:dartvel_core/dartvel.dart';

import '../../core.dart';

@DVBackendFunction()
Future<Map<String, Object?>> _consoleLedger(String session) => asConsole(
    session, () => callCore('GET', '/v1/admin/ledger?limit=30', asOperator: true));
