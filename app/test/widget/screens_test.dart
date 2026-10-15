// Every screen builds, in light and dark, at phone and desktop widths, with
// no backend to answer it: the loading state and the refusal state both have
// to draw. A screen that throws here would ship a blank page.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rtn_app/dartvel_client/dartvel_client.dart';
import 'package:rtn_app/styles/theme.dart';

Future<void> show(WidgetTester tester, Widget screen, {Brightness brightness = Brightness.light, double width = 1280}) async {
  tester.view.physicalSize = Size(width, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.runAsync(() async {
    await tester.pumpWidget(MaterialApp(
      theme: rtnTheme(brightness),
      home: Material(child: screen),
    ));
    // Long enough for a backend call to fail and the refusal to draw.
    await Future<void>.delayed(const Duration(milliseconds: 300));
  });
  await tester.pump();
}

void main() {
  setUpAll(() => DV.global<ThemeChoice>(const ThemeChoice()));

  final Map<String, Widget> screens = <String, Widget>{
    'welcome': const WelcomeScreen(),
    'sign in': const SignInScreen(),
    'console sign in': const ConsoleSignInScreen(),
    'home': const HomeScreen(),
    'data': const DataScreen(),
    'recharge': const RechargeScreen(),
    'send': const TransferScreen(),
    'borrow': const BorrowScreen(),
    'history': const HistoryScreen(),
    'receipt': const ReceiptScreen('1'),
    'rewards': const RewardsScreen(),
    'notifications': const NotificationsScreen(),
    'support': const SupportScreen(),
    'messages': const MessagesScreen(),
    'ussd': const UssdScreen(),
    'account': const AccountScreen(),
    'live': const LiveScreen(),
    'subscribers': const SubscribersScreen(),
    'subscriber': const SubscriberFileScreen('2349990000001'),
    'catalogue': const CatalogScreen(),
    'vouchers': const VouchersScreen(),
    'care desk': const CareDeskScreen(),
    'sms centre': const SmsLogScreen(),
    'ledger': const LedgerScreen(),
  };

  for (final MapEntry<String, Widget> entry in screens.entries) {
    for (final (Brightness brightness, double width) in <(Brightness, double)>[
      (Brightness.light, 1280),
      (Brightness.dark, 360),
    ]) {
      testWidgets('${entry.key} draws (${brightness.name}, ${width.toInt()} px)', (WidgetTester tester) async {
        await show(tester, entry.value, brightness: brightness, width: width);
        expect(tester.takeException(), isNull);
        expect(find.bySemanticsLabel(RegExp('.+')), findsWidgets);
      });
    }
  }

  testWidgets('a page has one level-1 heading', (WidgetTester tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    await show(tester, const SignInScreen());
    expect(find.text('Sign in to MyRTN'), findsOneWidget);
    final SemanticsNode heading = tester.getSemantics(find.text('Sign in to MyRTN'));
    expect(heading.headingLevel, 1);
    semantics.dispose();
  });

  testWidgets('controls carry tooltips and names', (WidgetTester tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    await show(tester, const SignInScreen());
    expect(find.byTooltip('Send me a code: send a sign-in code by SMS to this number'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('^Send me a code')), findsOneWidget);
    await show(tester, const UssdScreen());
    for (final String key in <String>['1', '5', '*', '#']) {
      expect(find.byTooltip('Press $key'), findsOneWidget);
    }
    expect(find.byTooltip('Call: dial this code'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('the dial pad types what is pressed', (WidgetTester tester) async {
    await show(tester, const UssdScreen());
    for (final String key in <String>['*', '1', '2', '3', '#']) {
      await tester.tap(find.byTooltip('Press $key'));
      await tester.pump();
    }
    expect(find.text('*123#'), findsWidgets);
  });

  for (final (String path, double width) in <(String, double)>[('/signin', 1280), ('/my', 360), ('/console', 1280), ('/', 360)]) {
    testWidgets('the frame draws around $path at ${width.toInt()} px', (WidgetTester tester) async {
      tester.view.physicalSize = Size(width, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final GoRouter router = GoRouter(initialLocation: path, routes: <RouteBase>[
        GoRoute(path: '/:rest(.*)', builder: (BuildContext context, GoRouterState state) => const AppFrame(SizedBox.expand())),
        GoRoute(path: '/', builder: (BuildContext context, GoRouterState state) => const AppFrame(SizedBox.expand())),
      ]);
      await tester.runAsync(() async {
        await tester.pumpWidget(MaterialApp.router(theme: rtnTheme(Brightness.light), routerConfig: router));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byTooltip(RegExp('Switch to (dark|light) mode')), findsOneWidget);
    });
  }

  testWidgets('a backend that cannot be reached is said in words, with a retry', (WidgetTester tester) async {
    await show(tester, const HomeScreen());
    expect(find.text('Try again'), findsOneWidget);
  });
}
