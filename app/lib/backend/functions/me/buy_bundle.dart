// POST /api/me/buy_bundle: Buys a data bundle, for the line or as a gift.
import 'package:dartvel_core/dartvel.dart';

import '../../../server/selfcare.dart';
import '../../../server/signed_in.dart';
import '../../../services/wire.dart';

@DVBackendFunction(policy: 'SubscriberLine.update')
Future<Reply<Outcome>> _buyBundle(DVContext ctx, String bundleId, String forNumber, String attempt) =>
    SelfCare.shared.buyBundle(me(ctx), bundleId, forNumber, attempt);
