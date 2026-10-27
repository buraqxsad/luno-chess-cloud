import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:luno_chess/widgets/promotion_sheet.dart';

void main() {
  testWidgets('Promotion callbacks cannot dismiss a covering route', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    late BuildContext host;
    await tester.pumpWidget(
      MaterialApp(
        theme: LunoTheme.dark,
        navigatorKey: navigator,
        home: Builder(
          builder: (context) {
            host = context;
            return const Scaffold();
          },
        ),
      ),
    );
    final result = showPromotionSheet(
      host,
      color: PieceColor.white,
      pieceSet: 'luno',
    );
    await tester.pumpAndSettle();
    final callback =
        tester.widgetList<InkWell>(find.byType(InkWell)).first.onTap!;
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Cover')),
      ),
    );
    await tester.pumpAndSettle();
    callback();
    await tester.pumpAndSettle();
    expect(find.text('Cover'), findsOneWidget);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    callback();
    callback();
    await tester.pumpAndSettle();
    expect(await result, PieceType.queen);
    callback();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
  testWidgets('All four promotion options fit and return exact pieces', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    late BuildContext host;
    await tester.pumpWidget(
      MaterialApp(
        theme: LunoTheme.dark,
        builder:
            (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
        home: Builder(
          builder: (context) {
            host = context;
            return const Scaffold();
          },
        ),
      ),
    );
    for (final choice in [
      (PieceType.queen, 'Vezir'),
      (PieceType.rook, 'Kale'),
      (PieceType.bishop, 'Fil'),
      (PieceType.knight, 'At'),
    ]) {
      final result = showPromotionSheet(
        host,
        color: PieceColor.white,
        pieceSet: 'luno',
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text(choice.$2));
      await tester.tap(find.text(choice.$2));
      await tester.pumpAndSettle();
      expect(await result, choice.$1);
    }
    final cancelled = showPromotionSheet(
      host,
      color: PieceColor.black,
      pieceSet: 'ottoman',
    );
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.text('PİYON TERFİSİ'))).pop();
    await tester.pumpAndSettle();
    expect(await cancelled, isNull);
  });
}
