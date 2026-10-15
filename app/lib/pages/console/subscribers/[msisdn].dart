import 'package:flutter/widgets.dart';

import '../../../dartvel_client/dartvel_client.dart';

@DVPage(title: 'Subscriber', description: 'One RTN subscriber: balances, plan, bar, top-up and ledger.')
@pragma('vm:entry-point')
Widget _consoleSubscriberPage(BuildContext context) => SubscriberFileScreen(context.dvParams['msisdn'] ?? '');
