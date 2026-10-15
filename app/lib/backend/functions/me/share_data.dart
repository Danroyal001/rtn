// POST /api/me/share_data: Shares bundle data with another line, confirmed with the PIN.
import 'package:dartvel_core/dartvel.dart';

import '../../../server/selfcare.dart';
import '../../../server/signed_in.dart';
import '../../../services/wire.dart';

@DVBackendFunction(policy: 'SubscriberLine.update')
Future<Reply<Outcome>> _shareData(DVContext ctx, String to, String megabytes, String pin, String attempt) =>
    SelfCare.shared.shareData(me(ctx), to, megabytes, pin, attempt);
