import 'package:rtn_app/services/focus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('focus taken by a non-traversal node after passing the root goes back to the control', (
    WidgetTester tester,
  ) async {
    FocusKeeper.install();
    final FocusNode field = FocusNode(debugLabel: 'field');
    final FocusNode shell = FocusNode(debugLabel: 'shell', skipTraversal: true);
    addTearDown(field.dispose);
    addTearDown(shell.dispose);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Focus(
          focusNode: shell,
          child: Focus(focusNode: field, child: const SizedBox()),
        ),
      ),
    );

    field.requestFocus();
    await tester.pump();
    expect(field.hasPrimaryFocus, isTrue);

    // What the web engine does: the control lets go, the root has focus, the shell takes it.
    field.unfocus(disposition: UnfocusDisposition.scope);
    await tester.pump();
    shell.requestFocus();
    await tester.pump();
    await tester.pump();
    expect(field.hasPrimaryFocus, isTrue);
  });

  testWidgets('a click from a control straight to the page is left alone', (WidgetTester tester) async {
    FocusKeeper.install();
    final FocusNode field = FocusNode(debugLabel: 'field');
    final FocusNode page = FocusNode(debugLabel: 'page', skipTraversal: true);
    addTearDown(field.dispose);
    addTearDown(page.dispose);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Focus(
          focusNode: page,
          child: Focus(focusNode: field, child: const SizedBox()),
        ),
      ),
    );

    field.requestFocus();
    await tester.pump();
    page.requestFocus();
    await tester.pump();
    await tester.pump();
    expect(page.hasPrimaryFocus, isTrue);
  });
}
