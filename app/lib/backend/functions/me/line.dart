// POST /api/me/line: The signed-in line with its plan and balances.
import 'package:dartvel_core/dartvel.dart';

import '../../../server/selfcare.dart';
import '../../../server/signed_in.dart';
import '../../../services/wire.dart';

@DVBackendFunction(policy: 'SubscriberLine.view')
Future<Reply<Line>> _myLine(DVContext ctx) => SelfCare.shared.line(me(ctx));
