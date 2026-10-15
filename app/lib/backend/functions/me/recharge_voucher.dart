// POST /api/me/recharge_voucher: Recharges from a voucher PIN.
import 'package:dartvel_core/dartvel.dart';

import '../../../server/selfcare.dart';
import '../../../server/signed_in.dart';
import '../../../services/wire.dart';

@DVBackendFunction(policy: 'SubscriberLine.update')
Future<Reply<Outcome>> _rechargeVoucher(DVContext ctx, String pin, String forNumber, String attempt) =>
    SelfCare.shared.rechargeVoucher(me(ctx), pin, forNumber, attempt);
