import 'package:flutter/widgets.dart';

import '../../dartvel_client/dartvel_client.dart';

@DVPage(title: 'Send airtime or data', description: 'Send airtime or share data with another RTN line.')
@pragma('vm:entry-point')
Widget _transferPage(BuildContext context) => const TransferScreen();
