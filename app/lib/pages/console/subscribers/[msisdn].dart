import 'package:flutter/material.dart';

import '../../../dartvel_client/dartvel_client.dart';
import '../../../components/console.dart';
import '../../../components/ui.dart';

@DVPage(
  title: 'Console: subscriber',
  description: 'RTN operator console: one subscriber line.',
  showAppBar: false,
)
@pragma('vm:entry-point')
Widget _consoleSubscriberPage(BuildContext context) {
  final String msisdn = context.dvParams['msisdn'] ?? '';
  return PageFrame(children: <Widget>[
    const ConsoleTabs(),
    ConsoleSignedIn(builder: (BuildContext context) => SubscriberDetail(msisdn: msisdn)),
  ]);
}
