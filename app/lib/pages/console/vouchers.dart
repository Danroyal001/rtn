import 'package:flutter/widgets.dart';

import '../../dartvel_client/dartvel_client.dart';

@DVPage(title: 'Vouchers', description: 'Print and track RTN recharge vouchers.')
@pragma('vm:entry-point')
Widget _consoleVouchersPage(BuildContext context) => const VouchersScreen();
