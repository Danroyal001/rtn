import 'package:flutter/material.dart';

import '../../dartvel_client/dartvel_client.dart';
import '../../components/console.dart';
import '../../components/ui.dart';

@DVPage(
  title: 'Console: live traffic',
  description: 'RTN operator console: live traffic across the network.',
  showAppBar: false,
)
@pragma('vm:entry-point')
Widget _consolePage(BuildContext context) => PageFrame(children: <Widget>[
      const PageHeading('Network console', subtitle: 'Live traffic, refreshed every two seconds.'),
      const ConsoleTabs(),
      ConsoleSignedIn(builder: (BuildContext context) => const TrafficBoard()),
    ]);
