import 'package:flutter/widgets.dart';

import '../../../dartvel_client/dartvel_client.dart';

@DVPage(title: 'Subscribers', description: 'Find, add and manage RTN subscribers.')
@pragma('vm:entry-point')
Widget _consoleSubscribersPage(BuildContext context) => const SubscribersScreen();
