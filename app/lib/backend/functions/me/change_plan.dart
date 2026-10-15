// POST /api/me/change_plan: Moves the line to another tariff plan.
import 'package:dartvel_core/dartvel.dart';

import '../../../server/selfcare.dart';
import '../../../server/signed_in.dart';
import '../../../services/wire.dart';

@DVBackendFunction(policy: 'SubscriberLine.update')
Future<Reply<Done>> _changePlan(DVContext ctx, String planId) =>
    SelfCare.shared.setPlan(me(ctx), planId);
