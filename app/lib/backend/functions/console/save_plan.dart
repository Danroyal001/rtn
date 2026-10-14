// POST /api/console/save_plan: add a rating plan or change one.
import 'package:dartvel_core/dartvel.dart';

import '../../core.dart';

@DVBackendFunction()
Future<Map<String, Object?>> _consoleSavePlan(
  String session,
  String id,
  String name,
  String voiceKoboPerSecond,
  String smsNaira,
  String dataNairaPerMb,
) =>
    asConsole(session, () async {
      final int? voice = int.tryParse(voiceKoboPerSecond.trim());
      final int? sms = nairaToUnits(smsNaira);
      final int? data = nairaToUnits(dataNairaPerMb);
      if (voice == null || sms == null || data == null) {
        return failure('invalid_amount', 'Every rate needs a number.');
      }
      return callCore('PUT', '/v1/admin/plans/${Uri.encodeComponent(id.trim())}',
          asOperator: true,
          body: <String, Object?>{
            'id': id.trim(),
            'name': name.trim(),
            'voice_per_second': voice,
            'sms_per_segment': sms,
            'data_per_mb': data,
          });
    });
