import 'package:flutter/material.dart';

import '../dartvel_client/dartvel_client.dart';
import '../components/ui.dart';
import '../components/self_service.dart';

@DVPage(
  title: 'Data bundles',
  description: 'RTN data bundles: daily, weekly and monthly, bought from airtime.',
  showAppBar: false,
)
@pragma('vm:entry-point')
Widget _bundlesPage(BuildContext context) => const PageFrame(children: <Widget>[
      PageHeading('Data bundles', subtitle: 'Bought from airtime. Data in a bundle is used before pay-as-you-go.'),
      BundleShelf(),
    ]);
