// POST /api/me/redeem: Spends loyalty points on a reward.
import 'package:dartvel_core/dartvel.dart';

import '../../../server/selfcare.dart';
import '../../../server/signed_in.dart';
import '../../../services/wire.dart';

@DVBackendFunction(policy: 'SubscriberLine.update')
Future<Reply<Outcome>> _redeemPoints(DVContext ctx, String rewardId, String attempt) =>
    SelfCare.shared.redeem(me(ctx), rewardId, attempt);
