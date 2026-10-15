import 'package:flutter/widgets.dart';

import '../../dartvel_client/dartvel_client.dart';

@DVPage(title: 'Borrow airtime', description: 'Borrow RTN airtime now and repay it from your next recharge.')
@pragma('vm:entry-point')
Widget _borrowPage(BuildContext context) => const BorrowScreen();
