// POST /api/console/catalog: rating plans and bundles.
import 'package:dartvel_core/dartvel.dart';

import '../../core.dart';

@DVBackendFunction()
Future<Map<String, Object?>> _consoleCatalog(String session) => asConsole(
    session, () => callCore('GET', '/v1/admin/catalog', asOperator: true));
