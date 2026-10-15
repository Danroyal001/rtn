// POST /api/me/send_sms: Sends an SMS, charged per part.
import 'package:dartvel_core/dartvel.dart';

import '../../../server/selfcare.dart';
import '../../../server/signed_in.dart';
import '../../../services/wire.dart';

@DVBackendFunction(policy: 'SubscriberLine.update')
Future<Reply<Outcome>> _sendSms(DVContext ctx, String to, String text, String attempt) =>
    SelfCare.shared.sendSms(me(ctx), to, text, attempt);
