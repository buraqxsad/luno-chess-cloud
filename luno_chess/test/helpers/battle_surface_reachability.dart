import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/board.dart';

/// The live portrait surface keeps the board fixed while the information and
/// hand below it scroll. Check actual revealed geometry inside that viewport.
Future<Rect> revealBattleSurfaceWidget(
  WidgetTester tester,
  Finder target, {
  required Rect safe,
  required Rect fixedBoard,
  bool wholeBounds = true,
  bool interactive = true,
}) async {
  expect(target, findsOneWidget);
  await Scrollable.ensureVisible(tester.element(target), alignment: .5);
  await tester.pumpAndSettle();
  if (interactive) expect(target.hitTestable(), findsOneWidget);

  final mainScroll = find.ancestor(
    of: target,
    matching: find.byKey(const ValueKey('battle-scroll')),
  );
  final viewport =
      mainScroll.evaluate().isEmpty
          ? safe
          : safe.intersect(tester.getRect(mainScroll));
  expect(viewport.width, greaterThan(0));
  expect(viewport.height, greaterThan(0));
  final rect = tester.getRect(target);
  if (wholeBounds) {
    expect(rect.left, greaterThanOrEqualTo(viewport.left));
    expect(rect.top, greaterThanOrEqualTo(viewport.top));
    expect(rect.right, lessThanOrEqualTo(viewport.right));
    expect(rect.bottom, lessThanOrEqualTo(viewport.bottom));
  } else {
    // A deliberately tall card can be browsed vertically, but its real tap
    // point must be inside the unobscured scroll viewport.
    expect(viewport.contains(rect.center), isTrue);
  }
  expect(
    tester.getRect(find.byType(BattleBoard)),
    fixedBoard,
    reason: 'Browsing match information must not move the readable board',
  );
  return rect;
}

Future<void> revealBattleCard(
  WidgetTester tester,
  Finder card, {
  required Rect safe,
  required Rect fixedBoard,
}) async {
  await revealBattleSurfaceWidget(
    tester,
    card,
    safe: safe,
    fixedBoard: fixedBoard,
    wholeBounds: false,
  );
  final labels = find.descendant(of: card, matching: find.byType(Text));
  final widgets = labels.evaluate().map((element) => element.widget).toList();
  expect(widgets.length, greaterThanOrEqualTo(2));
  for (final label in widgets) {
    await revealBattleSurfaceWidget(
      tester,
      find.byWidget(label),
      safe: safe,
      fixedBoard: fixedBoard,
      // Cost/name overlays intentionally ignore pointers so card gestures work.
      // Their full painted bounds, rather than tap handling, must be visible.
      interactive: false,
    );
  }
}
