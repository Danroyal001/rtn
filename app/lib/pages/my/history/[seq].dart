import 'package:flutter/widgets.dart';

import '../../../dartvel_client/dartvel_client.dart';

@DVPage(title: 'Receipt', description: 'The receipt for one transaction on your RTN line.')
@pragma('vm:entry-point')
Widget _receiptPage(BuildContext context) => ReceiptScreen(context.dvParams['seq'] ?? '');
