import 'package:flutter/widgets.dart';

import '../../dartvel_client/dartvel_client.dart';

@DVPage(title: 'Console', description: 'RTN operator console: live traffic across the network.')
@pragma('vm:entry-point')
Widget _consolePage(BuildContext context) => const LiveScreen();
