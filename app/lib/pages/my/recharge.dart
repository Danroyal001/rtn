import 'package:flutter/widgets.dart';

import '../../dartvel_client/dartvel_client.dart';

@DVPage(title: 'Recharge', description: 'Recharge an RTN line with a voucher PIN or a card.')
@pragma('vm:entry-point')
Widget _rechargePage(BuildContext context) => const RechargeScreen();
