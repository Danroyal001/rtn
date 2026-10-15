// GET /api/status: whether the network is up, and how many lines it has.
// Public, so a load balancer or demo.sh can ask it. It also wakes the
// in-process core, which otherwise starts on the first call that needs it.
import 'package:dartvel_core/dartvel.dart';

import '../../server/selfcare.dart';
import '../../services/wire.dart';

@DVBackendFunction()
Future<Reply<Done>> _networkStatus() => SelfCare.shared.status();
