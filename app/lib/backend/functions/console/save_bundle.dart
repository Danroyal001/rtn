// POST /api/console/save_bundle: add a data bundle or change one.
import 'package:dartvel_core/dartvel.dart';

import '../../core.dart';

@DVBackendFunction()
Future<Map<String, Object?>> _consoleSaveBundle(
  String session,
  String id,
  String name,
  int dataMb,
  String priceNaira,
  int validityDays,
) =>
    asConsole(session, () async {
      final int? price = nairaToUnits(priceNaira);
      if (price == null) {
        return failure('invalid_amount', 'Enter the price in naira, like 500.');
      }
      return callCore('PUT', '/v1/admin/bundles/${Uri.encodeComponent(id.trim())}',
          asOperator: true,
          body: <String, Object?>{
            'id': id.trim(),
            'name': name.trim(),
            'data_bytes': dataMb * 1048576,
            'price': price,
            'validity_days': validityDays,
          });
    });
