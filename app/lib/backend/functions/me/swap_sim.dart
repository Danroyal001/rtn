// POST /api/me/swap_sim: Moves the number to a new SIM.
import 'package:dartvel_core/dartvel.dart';

import '../../../server/selfcare.dart';
import '../../../server/signed_in.dart';
import '../../../services/wire.dart';

@DVBackendFunction(policy: 'SubscriberLine.update')
Future<Reply<Line>> _swapSim(DVContext ctx, String pin) =>
    SelfCare.shared.swapSim(me(ctx), pin);
