import 'package:flutter/material.dart';

import '../../dartvel_client/dartvel_client.dart';
import '../../components/console.dart';
import '../../components/ui.dart';

@DVPage(
  title: 'Console: plans and bundles',
  description: 'RTN operator console: rating plans and data bundles.',
  showAppBar: false,
)
@pragma('vm:entry-point')
Widget _consoleCatalogPage(BuildContext context) => PageFrame(children: <Widget>[
      const PageHeading('Plans and bundles', subtitle: 'What a second, a message and a megabyte cost.'),
      const ConsoleTabs(),
      ConsoleSignedIn(builder: (BuildContext context) => const CatalogEditor()),
    ]);
