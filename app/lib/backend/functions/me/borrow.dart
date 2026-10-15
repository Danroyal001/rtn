// POST /api/me/borrow: Borrows airtime, repaid from the next recharge.
import 'package:dartvel_core/dartvel.dart';

import '../../../server/selfcare.dart';
import '../../../server/signed_in.dart';
import '../../../services/wire.dart';

@DVBackendFunction(policy: 'SubscriberLine.update')
Future<Reply<Outcome>> _borrowAirtime(DVContext ctx, String amount, String attempt) =>
    SelfCare.shared.borrow(me(ctx), amount, attempt);
