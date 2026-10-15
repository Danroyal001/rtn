// POST /api/me/home: The home screen: the line, its balances, offers and recent activity.
import 'package:dartvel_core/dartvel.dart';

import '../../../server/selfcare.dart';
import '../../../server/signed_in.dart';
import '../../../services/wire.dart';

@DVBackendFunction(policy: 'SubscriberLine.view')
Future<Reply<Dashboard>> _home(DVContext ctx) =>
    SelfCare.shared.dashboard(me(ctx));
