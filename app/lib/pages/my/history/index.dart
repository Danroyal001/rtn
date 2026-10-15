import 'package:flutter/widgets.dart';

import '../../../dartvel_client/dartvel_client.dart';

@DVPage(title: 'History', description: 'Every transaction on your RTN line, with receipts.')
@pragma('vm:entry-point')
Widget _historyPage(BuildContext context) => const HistoryScreen();
