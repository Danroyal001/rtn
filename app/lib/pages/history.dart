import 'package:flutter/material.dart';

import '../dartvel_client/dartvel_client.dart';
import '../components/ui.dart';
import '../components/self_service.dart';

@DVPage(
  title: 'History',
  description: 'Every change to your RTN balances, newest first.',
  showAppBar: false,
)
@pragma('vm:entry-point')
Widget _historyPage(BuildContext context) => const PageFrame(children: <Widget>[
      PageHeading('History', subtitle: 'Every change to your balances, from the network ledger.'),
      HistoryList(),
    ]);
