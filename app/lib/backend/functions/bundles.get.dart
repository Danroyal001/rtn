// GET /api/bundles: the bundle catalogue, which anyone may read.
import 'package:dartvel_core/dartvel.dart';

import '../core.dart';

@DVBackendFunction()
Future<Map<String, Object?>> _bundleCatalog() => callCore('GET', '/v1/bundles');
