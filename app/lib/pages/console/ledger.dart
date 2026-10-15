import 'package:flutter/widgets.dart';

import '../../dartvel_client/dartvel_client.dart';

@DVPage(title: 'Ledger', description: 'Every balance change on the RTN network.')
@pragma('vm:entry-point')
Widget _consoleLedgerPage(BuildContext context) => const LedgerScreen();
