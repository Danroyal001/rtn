// POST /api/console/save_plan: Adds or changes a rating plan.
import 'package:dartvel_core/dartvel.dart';

import '../../../server/console.dart';
import '../../../services/wire.dart';

@DVBackendFunction(policy: 'OperatorConsole.update')
Future<Reply<Done>> _consoleSavePlan(
  DVContext ctx,
  String id,
  String name,
  String voicePerSecond,
  String smsPerSegment,
  String dataPerMb,
) =>
    Console.shared.savePlan(id, name, voicePerSecond, smsPerSegment, dataPerMb);
