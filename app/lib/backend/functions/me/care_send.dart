// POST /api/me/care_send: Writes to RTN care.
import 'package:dartvel_core/dartvel.dart';

import '../../../server/selfcare.dart';
import '../../../server/signed_in.dart';
import '../../../services/wire.dart';

@DVBackendFunction(policy: 'SubscriberLine.update')
Future<Reply<CareChat>> _careSend(DVContext ctx, String text) => SelfCare.shared.careSend(me(ctx), text);
