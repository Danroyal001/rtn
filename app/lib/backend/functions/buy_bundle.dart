// POST /api/buy_bundle
import 'package:dartvel_core/dartvel.dart';

import '../core.dart';

@DVBackendFunction()
Future<Map<String, Object?>> _buyBundle(
  String token,
  String bundleId,
  String requestId,
) =>
    callCore('POST', '/v1/me/bundles', bearer: token, body: <String, Object?>{
      'bundle_id': bundleId,
      'request_id': requestIdOr(requestId),
    });
