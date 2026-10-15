// POST /api/console/catalog: Plans, bundles and rewards.
import 'package:dartvel_core/dartvel.dart';

import '../../../server/console.dart';
import '../../../services/wire.dart';

@DVBackendFunction(policy: 'OperatorConsole.view')
Future<Reply<Catalog>> _consoleCatalog(DVContext ctx) => Console.shared.catalog();
