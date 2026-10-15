// POST /api/console/save_bundle: Adds or changes a data bundle.
import 'package:dartvel_core/dartvel.dart';

import '../../../server/console.dart';
import '../../../services/wire.dart';

@DVBackendFunction(policy: 'OperatorConsole.update')
Future<Reply<Done>> _consoleSaveBundle(
  DVContext ctx,
  String id,
  String name,
  String megabytes,
  String price,
  String validityDays,
  String offer,
) =>
    Console.shared.saveBundle(id, name, megabytes, price, validityDays, offer);
