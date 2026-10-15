import 'package:flutter/material.dart';

import '../dartvel_client/dartvel_client.dart';
import '../styles/theme.dart';

/// The application: Dartvel's router in RTN's theme, light or dark as the
/// reader chose.
@DVFunctionalWidget()
Widget _rtnApp(BuildContext context, List<String> arguments) {
  final ThemeChoice choice = context.global<ThemeChoice>();
  return MaterialApp.router(
    title: 'MyRTN',
    debugShowCheckedModeBanner: false,
    theme: rtnTheme(Brightness.light),
    darkTheme: rtnTheme(Brightness.dark),
    themeMode: choice.mode,
    routerConfig: createDartvelRouter(arguments: arguments),
  );
}
