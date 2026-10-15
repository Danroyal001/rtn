import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../dartvel_client/dartvel_client.dart';
import '../../services/guard.dart';

/// The console needs an operator session.
FutureOr<String?> guard(BuildContext context, GoRouterState state) async {
  if (await currentRole() == 'operator') return null;
  return DVNavigation.locationOf(DVRoutes.operator);
}
