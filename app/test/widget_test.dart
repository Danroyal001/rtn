import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rtn_app/components/dial_pad.dart';
import 'package:rtn_app/components/self_service.dart';
import 'package:rtn_app/dartvel_client/dartvel_client.dart';
import 'package:rtn_app/main.dart';
import 'package:rtn_app/services/session.dart';
import 'package:rtn_app/styles/theme.dart';

Widget _host(Widget child) => MaterialApp(theme: rtnTheme(.light), home: Scaffold(body: SingleChildScrollView(child: child)));

void main() {
  setUp(() {
    DV.global<SubscriberSession>(const SubscriberSession());
    DV.global<ConsoleSession>(const ConsoleSession());
  });

  testWidgets('the app starts', (WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(createDartvelApp());
      await tester.pump();
    });
    expect(find.byType(WidgetsApp), findsOneWidget);
  });

  testWidgets('a signed-out visitor is asked to sign in, with the demo lines named', (WidgetTester tester) async {
    await tester.pumpWidget(_host(const LineOverview()));
    expect(find.text('Sign in to your line'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Phone number'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'PIN'), findsOneWidget);
    expect(find.textContaining('PIN 1234'), findsOneWidget);
  });

  testWidgets('the dial pad takes keys and names every control', (WidgetTester tester) async {
    DV.global<SubscriberSession>(const SubscriberSession(token: 't', msisdn: '2349990000001', name: 'Ada'));
    await tester.pumpWidget(_host(const DialPad()));
    await tester.pump();
    expect(find.text('Calling as 0999 000 0001'), findsOneWidget);
    for (final String key in <String>['1', '2', '3', '*', '#']) {
      await tester.ensureVisible(find.widgetWithText(OutlinedButton, key));
      await tester.tap(find.widgetWithText(OutlinedButton, key));
    }
    await tester.pump();
    expect(find.text('123*#'), findsOneWidget);
    for (final String tip in <String>['Dial', 'Delete the last digit', 'Clear']) {
      expect(find.byTooltip(tip), findsOneWidget, reason: 'every icon control has a name');
    }
    await tester.ensureVisible(find.byTooltip('Delete the last digit'));
    await tester.tap(find.byTooltip('Delete the last digit'));
    await tester.pump();
    expect(find.text('123*'), findsOneWidget);
    await tester.tap(find.byTooltip('Clear'));
    await tester.pump();
    expect(find.text('Dial a code'), findsOneWidget);
  });
}
