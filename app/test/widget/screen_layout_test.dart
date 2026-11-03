// Since Dartvel 0.13.2 every page's scrollbar stays on screen. A screen's
// scrolling area has to reach the edge of the window, with the side margins
// inside it, or the scrollbar is drawn over the content's right edge.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rtn_app/dartvel_client/dartvel_client.dart';
import 'package:rtn_app/styles/theme.dart';

void main() {
  for (final double width in <double>[390, 1024, 1366]) {
    testWidgets('a screen scrolls edge to edge and keeps its margins inside, at $width px', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      const Key card = Key('card');
      await tester.pumpWidget(
        MaterialApp(
          theme: rtnTheme(Brightness.light),
          home: const Material(child: Screen(<Widget>[SizedBox(key: card, height: 120)])),
        ),
      );
      final Rect scrolling = tester.getRect(find.byType(Scrollable).first);
      expect(scrolling.left, 0);
      expect(scrolling.right, width);
      final Rect content = tester.getRect(find.byKey(card));
      expect(content.left, greaterThanOrEqualTo(16));
      expect(width - content.right, greaterThanOrEqualTo(16), reason: 'room on the right for the scrollbar');
    });
  }
}
