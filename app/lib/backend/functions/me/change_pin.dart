// POST /api/me/change_pin: Changes the PIN, given the current one.
import 'package:dartvel_core/dartvel.dart';

import '../../../server/selfcare.dart';
import '../../../server/signed_in.dart';
import '../../../services/wire.dart';

@DVBackendFunction(policy: 'SubscriberLine.update')
Future<Reply<Done>> _changePin(DVContext ctx, String current, String fresh) =>
    SelfCare.shared.changePin(me(ctx), current, fresh);
