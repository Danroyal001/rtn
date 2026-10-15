// Loading backend data into signals, without a StatefulWidget.
//
// A page keeps what it shows in a signal of `Reply<T>?`: null while loading,
// then the reply. [loadInto] starts the load once per signal, the first time
// the page builds, and (with [every]) keeps it fresh while the page is on
// screen. When the page goes away its element unmounts and the refresh stops.
import 'dart:async';

import '../dartvel_client/dartvel_client.dart';
import 'wire.dart';

final Expando<bool> _started = Expando<bool>('rtn loads');

/// Runs [call], turning a transport failure into a refusal a page can show.
Future<Reply<T>> ask<T>(Future<Reply<T>> Function() call) async {
  try {
    return await call();
  } on Object {
    return Reply.offline<T>();
  }
}

/// Fills [target] from [fetch] once, and again every [every] while the page
/// that owns [target] is on screen.
void loadInto<T>(DVSignal<Reply<T>?> target, Future<Reply<T>> Function() fetch, {Duration? every}) {
  if (_started[target.provider] == true) return;
  _started[target.provider] = true;
  bool busy = false;
  Future<void> run() async {
    if (busy) return;
    busy = true;
    final Reply<T> reply = await ask(fetch);
    busy = false;
    if (target.element.mounted) target.value = reply;
  }

  scheduleMicrotask(run);
  if (every != null) {
    Timer.periodic(every, (Timer timer) {
      if (!target.element.mounted) {
        timer.cancel();
        return;
      }
      unawaited(run());
    });
  }
}

/// Loads [target] again now, keeping what it shows until the answer arrives.
Future<void> reload<T>(DVSignal<Reply<T>?> target, Future<Reply<T>> Function() fetch) async {
  final Reply<T> reply = await ask(fetch);
  if (target.element.mounted) target.value = reply;
}

int _attempts = 0;

/// A fresh id for one attempt at an action. The backend records the charge
/// under it, so pressing again after a dropped connection is never a second
/// charge; a new attempt gets a new id.
String newAttempt() => '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-${(_attempts++).toRadixString(36)}';
