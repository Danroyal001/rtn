// POST /api/me/ussd: One step of a USSD session, as the handset would send it.
import 'package:dartvel_core/dartvel.dart';

import '../../../server/selfcare.dart';
import '../../../server/signed_in.dart';
import '../../../services/wire.dart';

@DVBackendFunction(policy: 'SubscriberLine.update')
Future<Reply<UssdReply>> _dialUssd(DVContext ctx, String session, String input) =>
    SelfCare.shared.ussd(me(ctx), session, input);
