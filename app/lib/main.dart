import 'package:flutter/material.dart';

import 'dartvel_client/dartvel_client.dart';
import 'services/session.dart';
import 'styles/theme.dart';

void main(List<String> arguments) async {
  await negotiateDartvelLaunch(arguments);
  DV.global<SubscriberSession>(const SubscriberSession());
  DV.global<ConsoleSession>(const ConsoleSession());
  runApp(createDartvelApp(arguments: arguments));
}

Widget createDartvelApp({List<String> arguments = const <String>[]}) {
  return MaterialApp.router(
    title: 'RTN',
    theme: rtnTheme(.light),
    darkTheme: rtnTheme(.dark),
    themeMode: .system,
    routerConfig: createDartvelRouter(arguments: arguments),
  );
}
