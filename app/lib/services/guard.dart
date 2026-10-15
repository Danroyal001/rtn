// What the page guards ask: who is signed in on this device.
import '../dartvel_client/dartvel_client.dart';
import 'account.dart';

/// The role of this device's session, asking the server when the app has just
/// started and does not know yet.
Future<String> currentRole() async {
  final DVSessionClient? sessions = DVSessionClient.installed;
  DVSession? session = sessions?.current;
  if (session == null && sessions != null) {
    try {
      session = await sessions.refresh();
    } on Object {
      session = null;
    }
  }
  return roleOf(session);
}
