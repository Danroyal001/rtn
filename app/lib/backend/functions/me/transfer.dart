// POST /api/me/transfer: Sends airtime to another line, confirmed with the PIN.
import 'package:dartvel_core/dartvel.dart';

import '../../../server/selfcare.dart';
import '../../../server/signed_in.dart';
import '../../../services/wire.dart';

@DVBackendFunction(policy: 'SubscriberLine.update')
Future<Reply<Outcome>> _transferAirtime(DVContext ctx, String to, String amount, String pin, String attempt) =>
    SelfCare.shared.transfer(me(ctx), to, amount, pin, attempt);
