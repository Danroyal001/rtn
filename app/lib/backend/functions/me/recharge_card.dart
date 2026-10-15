// POST /api/me/recharge_card: Recharges by card through the payment provider.
import 'package:dartvel_core/dartvel.dart';

import '../../../server/payments.dart';
import '../../../server/selfcare.dart';
import '../../../server/signed_in.dart';
import '../../../services/wire.dart';

@DVBackendFunction(policy: 'SubscriberLine.update')
Future<Reply<Outcome>> _rechargeCard(
  DVContext ctx,
  String forNumber,
  String amount,
  String cardNumber,
  String expiry,
  String cvv,
  String attempt,
) => SelfCare.shared.rechargeCard(
  me(ctx),
  forNumber,
  amount,
  CardDetails(number: cardNumber, expiry: expiry, cvv: cvv),
  attempt,
);
