import 'package:flutter/material.dart';

import '../dartvel_client/dartvel_client.dart';
import '../components/ui.dart';
import '../components/self_service.dart';

@DVPage(
  title: 'Transfer airtime',
  description: 'Send airtime to another RTN line.',
  showAppBar: false,
)
@pragma('vm:entry-point')
Widget _transferPage(BuildContext context) => const PageFrame(children: <Widget>[
      PageHeading('Transfer airtime', subtitle: 'Send airtime to another RTN line, confirmed with your PIN.'),
      TransferForm(),
    ]);
