// POST /api/me/suspend: Suspends a lost or stolen line.
import 'package:dartvel_core/dartvel.dart';

import '../../../server/selfcare.dart';
import '../../../server/signed_in.dart';
import '../../../services/wire.dart';

@DVBackendFunction(policy: 'SubscriberLine.update')
Future<Reply<Done>> _suspendLine(DVContext ctx, String pin) =>
    SelfCare.shared.suspend(me(ctx), pin);
