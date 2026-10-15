import 'package:flutter/widgets.dart';

import '../dartvel_client/dartvel_client.dart';

@DVPage(title: 'Console sign-in', description: 'Sign in to the RTN operator console.')
@pragma('vm:entry-point')
Widget _operatorPage(BuildContext context) => const ConsoleSignInScreen();
