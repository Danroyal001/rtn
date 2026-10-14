/// Who is signed in to the self-service app on this device: the core's token
/// for their line. Replaced, never mutated, so `context.global` redraws.
class const SubscriberSession({
  final String token = '',
  final String msisdn = '',
  final String name = '',
}) {
  bool get signedIn => token.isNotEmpty;
}

/// The operator's console session, signed by the app's server.
class const ConsoleSession({final String session = ''}) {
  bool get signedIn => session.isNotEmpty;
}
