import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/screens/online_hub_screen.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:luno_chess/widgets/luno_surface.dart';

void main() {
  for (final code in ['account-deleted', 'account-deletion-in-progress']) {
    for (final phase in ['enqueue', 'poll', 'cancel']) {
      testWidgets('$code during $phase stops matchmaking requests', (
        tester,
      ) async {
        var calls = 0;
        final failure = LunoApiException(
          code,
          code == 'account-deleted' ? 403 : 409,
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: LunoTheme.dark,
            home: OnlineHubScreen(
              onlineOverride: true,
              requestOverride: (path, body) async {
                calls++;
                if (path == '/enqueueRanked' && phase != 'enqueue') {
                  return {'ok': true, 'status': 'queued'};
                }
                throw failure;
              },
            ),
          ),
        );
        void press(String label) =>
            tester
                .widget<LunoButton>(
                  find.byWidgetPredicate(
                    (widget) => widget is LunoButton && widget.label == label,
                  ),
                )
                .onPressed!();
        press('EŞLEŞMEYİ BAŞLAT');
        await tester.pump();
        if (phase == 'poll') {
          await tester.pump(const Duration(seconds: 2));
          await tester.pump();
        } else if (phase == 'cancel') {
          press('ARAMAYI İPTAL ET');
          await tester.pump();
        }
        expect(find.text(failure.accountAccessMessage!), findsOneWidget);
        expect(
          find.byWidgetPredicate(
            (w) => w is LunoButton && w.label == 'GERİ DÖN',
          ),
          findsOneWidget,
        );
        expect(find.byType(LinearProgressIndicator), findsNothing);
        final stoppedAt = calls;
        final dynamic state = tester.state(find.byType(OnlineHubScreen));
        state.didChangeAppLifecycleState(AppLifecycleState.resumed);
        await tester.pump(const Duration(seconds: 20));
        expect(calls, stoppedAt);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        expect(
          calls,
          stoppedAt,
          reason: 'disposing blocked screen must not cancel remotely',
        );
        expect(tester.takeException(), isNull);
      });
    }
  }
}
