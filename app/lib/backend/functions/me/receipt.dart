// POST /api/me/receipt: One transaction on the line, for its receipt.
import 'package:dartvel_core/dartvel.dart';

import '../../../server/selfcare.dart';
import '../../../server/signed_in.dart';
import '../../../services/wire.dart';

@DVBackendFunction(policy: 'SubscriberLine.view')
Future<Reply<LedgerEntry>> _receipt(DVContext ctx, int seq) => SelfCare.shared.receipt(me(ctx), seq);
