import 'package:flutter/material.dart';

import '../dartvel_client/dartvel_client.dart';
import '../components/ui.dart';
import '../components/self_service.dart';

@DVPage(
  title: 'Messages',
  description: 'Send and read SMS on your RTN line.',
  showAppBar: false,
)
@pragma('vm:entry-point')
Widget _messagesPage(BuildContext context) => const PageFrame(children: <Widget>[
      PageHeading('Messages', subtitle: 'Messages wait in the network until the phone is on, then you get a delivery report.'),
      MessagesPanel(),
    ]);
