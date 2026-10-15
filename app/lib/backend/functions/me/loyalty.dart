// POST /api/me/loyalty: Loyalty points and what they buy.
import 'package:dartvel_core/dartvel.dart';

import '../../../server/selfcare.dart';
import '../../../server/signed_in.dart';
import '../../../services/wire.dart';

@DVBackendFunction(policy: 'SubscriberLine.view')
Future<Reply<Loyalty>> _loyalty(DVContext ctx) =>
    SelfCare.shared.loyalty(me(ctx));
