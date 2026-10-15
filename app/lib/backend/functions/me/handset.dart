// POST /api/me/handset: Switches the simulated handset on or off.
import 'package:dartvel_core/dartvel.dart';

import '../../../server/selfcare.dart';
import '../../../server/signed_in.dart';
import '../../../services/wire.dart';

@DVBackendFunction(policy: 'SubscriberLine.update')
Future<Reply<Done>> _setHandset(DVContext ctx, bool on) => SelfCare.shared.setHandset(me(ctx), on);
