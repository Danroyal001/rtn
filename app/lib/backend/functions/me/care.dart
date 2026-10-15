// POST /api/me/care: The line's conversation with RTN care.
import 'package:dartvel_core/dartvel.dart';

import '../../../server/selfcare.dart';
import '../../../server/signed_in.dart';
import '../../../services/wire.dart';

@DVBackendFunction(policy: 'SubscriberLine.view')
Future<Reply<CareChat>> _careChat(DVContext ctx) =>
    SelfCare.shared.care(me(ctx));
