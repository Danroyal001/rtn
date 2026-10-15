import 'package:flutter/widgets.dart';

import '../../dartvel_client/dartvel_client.dart';

@DVPage(title: 'Home', description: 'Your RTN airtime, data meter, offers and recent activity.')
@pragma('vm:entry-point')
Widget _myHomePage(BuildContext context) => const HomeScreen();
