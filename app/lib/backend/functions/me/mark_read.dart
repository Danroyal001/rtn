// POST /api/me/mark_read: Marks notifications read. [ids] is a comma-separated list.
import 'package:dartvel_core/dartvel.dart';

import '../../../server/selfcare.dart';
import '../../../server/signed_in.dart';
import '../../../services/wire.dart';

@DVBackendFunction(policy: 'SubscriberLine.update')
Future<Reply<Done>> _markRead(DVContext ctx, String ids) =>
    SelfCare.shared.markRead(me(ctx), ids.split(',').where((String id) => id.isNotEmpty).toList());
