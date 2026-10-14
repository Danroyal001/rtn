// POST /api/console/subscribers: search and page through subscribers.
import 'package:dartvel_core/dartvel.dart';

import '../../core.dart';

@DVBackendFunction()
Future<Map<String, Object?>> _consoleSubscribers(
  String session,
  String search,
  int offset,
) =>
    asConsole(session, () {
      final String query = Uri(queryParameters: <String, String>{
        'q': search,
        'offset': '$offset',
        'limit': '25',
      }).query;
      return callCore('GET', '/v1/admin/subscribers?$query', asOperator: true);
    });
