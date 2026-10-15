import 'package:flutter/widgets.dart';

import '../dartvel_client/dartvel_client.dart';

@DVPage(
  title: 'MyRTN',
  description: 'MyRTN: your RTN line in one place. Balance, data, recharge, transfers, loans, rewards and support.',
)
@pragma('vm:entry-point')
Widget _indexPage(BuildContext context) => const WelcomeScreen();
