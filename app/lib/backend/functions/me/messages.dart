// POST /api/me/messages: The line's SMS: received and sent.
import 'package:dartvel_core/dartvel.dart';

import '../../../server/selfcare.dart';
import '../../../server/signed_in.dart';
import '../../../services/wire.dart';

@DVBackendFunction(policy: 'SubscriberLine.view')
Future<Reply<Messages>> _messages(DVContext ctx) => SelfCare.shared.messages(me(ctx));
