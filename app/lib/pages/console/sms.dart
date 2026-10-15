import 'package:flutter/widgets.dart';

import '../../dartvel_client/dartvel_client.dart';

@DVPage(title: 'SMS centre', description: 'The RTN SMS centre: queued, delivered and expired messages.')
@pragma('vm:entry-point')
Widget _consoleSmsPage(BuildContext context) => const SmsLogScreen();
