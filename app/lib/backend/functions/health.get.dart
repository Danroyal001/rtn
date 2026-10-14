// GET /api/health
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction()
Map<String, Object?> _health() => <String, Object?>{
      'status': 'ok',
      'timestamp': DateTime.now().toIso8601String(),
    };
