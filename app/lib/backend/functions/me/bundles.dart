// POST /api/me/bundles: The catalogue: data bundles, plans and loyalty rewards.
import 'package:dartvel_core/dartvel.dart';

import '../../../server/selfcare.dart';
import '../../../services/wire.dart';

@DVBackendFunction(policy: 'SubscriberLine.view')
Future<Reply<Catalog>> _bundleCatalog(DVContext ctx) =>
    SelfCare.shared.catalog();
