import 'package:flutter/widgets.dart';

import '../../dartvel_client/dartvel_client.dart';

@DVPage(title: 'Account', description: 'Your RTN line: name, plan, PIN, SIM and phone.')
@pragma('vm:entry-point')
Widget _accountPage(BuildContext context) => const AccountScreen();
