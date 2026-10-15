import 'package:flutter/widgets.dart';

import '../../dartvel_client/dartvel_client.dart';

@DVPage(title: 'USSD', description: 'A dial pad for RTN USSD codes such as *123#.')
@pragma('vm:entry-point')
Widget _ussdPage(BuildContext context) => const UssdScreen();
