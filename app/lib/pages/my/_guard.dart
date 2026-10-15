import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../dartvel_client/dartvel_client.dart';
import '../../services/guard.dart';

/// Every MyRTN page needs a signed-in subscriber. The server refuses these
/// pages to a visitor with no session; this sends anyone else (an operator,
/// say) to sign in as a subscriber.
FutureOr<String?> guard(BuildContext context, GoRouterState state) async {
  if (await currentRole() == 'subscriber') return null;
  return DVNavigation.locationOf(DVRoutes.signin);
}
