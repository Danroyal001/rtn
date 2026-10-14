import '../dartvel_client/dartvel_client.dart';
import '../services/session.dart';

/// Guards console routes: only a signed operator session may open them.
final _consoleRoutes = <String>{
  '/console', '/console/subscribers', '/console/catalog',
  '/console/traffic', '/console/ledger', '/console/subscriber',
  '/console/add_subscriber', '/console/save_bundle', '/console/save_plan',
  '/console/update_subscriber', '/console/top_up', '/console/simulator',
};

bool consoleGuard(BuildContext context, String path) {
  final ConsoleSession session = context.global<ConsoleSession>();
  if (!_consoleRoutes.any((r) => path == r || path.startsWith('$r/')))
    return true;
  return session.signedIn;
}
