import 'package:flutter/widgets.dart';

import '../../dartvel_client/dartvel_client.dart';

@DVPage(title: 'Buy data', description: 'Daily, weekly and monthly RTN data bundles, for you or as a gift.')
@pragma('vm:entry-point')
Widget _dataPage(BuildContext context) => const DataScreen();
