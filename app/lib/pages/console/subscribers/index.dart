import 'package:flutter/material.dart';

import '../../../dartvel_client/dartvel_client.dart';
import '../../../components/console.dart';
import '../../../components/ui.dart';

@DVPage(
  title: 'Console: subscribers',
  description: 'RTN operator console: the subscriber registry.',
  showAppBar: false,
)
@pragma('vm:entry-point')
Widget _consoleSubscribersPage(BuildContext context) => PageFrame(children: <Widget>[
      const PageHeading('Subscribers', subtitle: 'The registry: every line, its SIM, plan and balances.'),
      const ConsoleTabs(),
      ConsoleSignedIn(builder: (BuildContext context) => const SubscriberDirectory()),
    ]);
