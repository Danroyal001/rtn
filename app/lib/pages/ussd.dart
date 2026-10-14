import 'package:flutter/material.dart';

import '../dartvel_client/dartvel_client.dart';
import '../components/ui.dart';
import '../components/dial_pad.dart';

@DVPage(
  title: 'USSD',
  description: 'Dial RTN USSD codes like *123# from the browser.',
  showAppBar: false,
)
@pragma('vm:entry-point')
Widget _ussdPage(BuildContext context) => const PageFrame(children: <Widget>[
      PageHeading('USSD', subtitle: 'Dial a code the way you would on a phone. The network answers each step.'),
      DialPad(),
    ]);
