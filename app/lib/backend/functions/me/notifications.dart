// POST /api/me/notifications: What RTN has told the line, newest first.
import 'package:dartvel_core/dartvel.dart';

import '../../../server/selfcare.dart';
import '../../../server/signed_in.dart';
import '../../../services/wire.dart';

@DVBackendFunction(policy: 'SubscriberLine.view')
Future<Reply<Inbox>> _notifications(DVContext ctx) => SelfCare.shared.notifications(me(ctx));
