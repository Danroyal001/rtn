import 'package:flutter/widgets.dart';

import 'dartvel_client/dartvel_client.dart';
import 'styles/theme.dart';

// TODO(dartvel): this file is meant to be `void main() => DV.run();`. Dartvel
// 0.12.2 has no DV.run(), so this is the smallest main it can run: settle the
// launch, register the one app-wide value, and start the app.
void main(List<String> arguments) async {
  await negotiateDartvelLaunch(arguments);
  DV.global<ThemeChoice>(const ThemeChoice());
  runApp(RtnApp(arguments));
}
