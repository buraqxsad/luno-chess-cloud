import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/screens/shop_screen.dart';
import 'package:luno_chess/theme/luno_assets.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:luno_chess/widgets/luno_surface.dart';
import 'package:luno_chess/widgets/resource_amount.dart';

void main() {
  for (final size in [const Size(320, 568), const Size(568, 320)]) {
    testWidgets('reward close is safe at $size with large text', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          theme: LunoTheme.dark,
          builder:
              (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(2)),
                child: child!,
              ),
          home: const Scaffold(body: Text('root')),
        ),
      );
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('shop underneath')),
        ),
      );
      await tester.pumpAndSettle();
      showDialog<void>(
        context: tester.element(find.text('shop underneath')),
        builder:
            (_) => ShopRewardDialog(
              title: 'GÜNLÜK ÖDÜL',
              art: LunoAssets.shopDaily,
              message:
                  'Günlük ödülün hesabına eklendi. Koleksiyonunu kontrol edebilirsin.',
              reward: ResourceAmount.coin(
                123456789,
                iconSize: 40,
                fontSize: 20,
              ),
            ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('123456789'), findsOneWidget);
      final button = find.widgetWithText(LunoButton, 'TAMAM');
      await tester.ensureVisible(button);
      final close = tester.widget<LunoButton>(button).onPressed!;
      close();
      close();
      await tester.pumpAndSettle();
      expect(find.text('shop underneath'), findsOneWidget);
      close();
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('shop underneath'), findsOneWidget);
    });
  }
}
