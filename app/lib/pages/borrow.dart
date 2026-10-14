import 'package:flutter/material.dart';

import '../dartvel_client/dartvel_client.dart';
import '../components/ui.dart';
import '../components/self_service.dart';

@DVPage(
  title: 'Borrow airtime',
  description: 'Borrow airtime now and repay from your next top-up.',
  showAppBar: false,
)
@pragma('vm:entry-point')
Widget _borrowPage(BuildContext context) => const PageFrame(children: <Widget>[
      PageHeading('Borrow airtime', subtitle: 'Repaid automatically from your next top-up.'),
      BorrowPanel(),
    ]);
