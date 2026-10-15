import 'package:flutter/widgets.dart';

import '../dartvel_client/dartvel_client.dart';

@DVPage(title: 'Sign in', description: 'Sign in to MyRTN with your RTN number and a code sent by SMS.')
@pragma('vm:entry-point')
Widget _signinPage(BuildContext context) => const SignInScreen();
