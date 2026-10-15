// POST /api/me/history: The line's transactions, newest first.
import 'package:dartvel_core/dartvel.dart';

import '../../../server/selfcare.dart';
import '../../../server/signed_in.dart';
import '../../../services/wire.dart';

@DVBackendFunction(policy: 'SubscriberLine.view')
Future<Reply<LedgerPage>> _history(DVContext ctx, int limit) => SelfCare.shared.history(me(ctx), limit);
