import 'package:flutter/material.dart';

import '../dartvel_client/dartvel_client.dart';
import '../styles/theme.dart';

/// The application: Dartvel's router in RTN's theme, light or dark as the
/// reader chose. [router] is made once, in main: this rebuilds whenever the
/// theme changes, and a router made here would start again at `/` each time.
@DVFunctionalWidget()
Widget _rtnApp(BuildContext context, RouterConfig<Object> router) {
  final ThemeChoice choice = context.global<ThemeChoice>();
  return MaterialApp.router(
    title: 'MyRTN',
    debugShowCheckedModeBanner: false,
    theme: rtnTheme(Brightness.light),
    darkTheme: rtnTheme(Brightness.dark),
    themeMode: choice.mode,
    routerConfig: router,
  );
}
