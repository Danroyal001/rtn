import 'package:flutter/material.dart';

import '../dartvel_client/dartvel_client.dart';
import '../components/ui.dart';
import '../components/self_service.dart';

@DVPage(
  title: 'My line',
  description: 'Your RTN airtime, data and loan balances at a glance.',
  showAppBar: false,
)
@pragma('vm:entry-point')
Widget _indexPage(BuildContext context) => const PageFrame(children: <Widget>[
      PageHeading('My line', subtitle: 'Airtime, data and loans, refreshed every few seconds.'),
      LineOverview(),
    ]);
