// POST /api/me/rename: Changes the name on the line.
import 'package:dartvel_core/dartvel.dart';

import '../../../server/selfcare.dart';
import '../../../server/signed_in.dart';
import '../../../services/wire.dart';

@DVBackendFunction(policy: 'SubscriberLine.update')
Future<Reply<Done>> _renameLine(DVContext ctx, String name) =>
    SelfCare.shared.rename(me(ctx), name);
