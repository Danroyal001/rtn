import 'package:dartvel_core/dartvel.dart';

/// The number of the line the request's session belongs to. Every function
/// that calls this is behind the SubscriberLine policy, so there is one.
String me(DVContext ctx) => ctx.session?.userId ?? '';
