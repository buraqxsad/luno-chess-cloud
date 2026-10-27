import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/board.dart';
import 'package:luno_chess/battle_v1/local_session.dart';
import 'package:luno_chess/battle_v1/practice.dart';
import 'package:luno_chess/i18n/luno_localizations.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/screens/battle_v1_screen.dart';
import 'package:luno_chess/screens/legacy_parity_screens.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:luno_chess/widgets/luno_surface.dart';

import 'battle_practice_v208_test.dart' show setupPracticeTestAssets;

Widget _app(Widget child) => MaterialApp(
  theme: LunoTheme.dark,
  locale: const Locale('en'),
  supportedLocales: LunoLocalizations.supportedLocales,
  localizationsDelegates: const [
    LunoLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  builder:
      (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
  home: child,
);

void _prepare(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 950);
  tester.view.devicePixelRatio = 1;
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 4));
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

BattleBoard _board(WidgetTester tester) =>
    tester.widget<BattleBoard>(find.byType(BattleBoard));

void main() {
  setupPracticeTestAssets();

  for (final boundary in ['inactive', 'covered']) {
    testWidgets(
      'completed lesson restores its continue gate after $boundary frame',
      (tester) async {
        _prepare(tester);
        final store =
            GameStore.createForTesting()
              ..loaded = true
              ..tutorialStep = 1;
        addTearDown(store.dispose);
        await tester.pumpWidget(
          _app(TutorialScreen(onboarding: true, playerStore: store)),
        );
        await tester.pump();
        final continueButton = find.byType(LunoButton);
        expect(tester.widget<LunoButton>(continueButton).onPressed, isNull);

        _board(tester).onTap(12);
        await tester.pump();
        expect(_board(tester).targets, contains(28));
        // Interrupt after the accepted move, before its post-frame report.
        _board(tester).onTap(28);
        final navigator = Navigator.of(
          tester.element(find.byType(TutorialScreen)),
        );
        if (boundary == 'inactive') {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
          await tester.pump();
          expect(_board(tester).view.rules.ply, 1);
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
        } else {
          unawaited(
            navigator.push(
              MaterialPageRoute<void>(
                builder: (_) => const Scaffold(body: Text('lesson-cover')),
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          expect(find.text('lesson-cover'), findsOneWidget);
          navigator.pop();
        }
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump();

        expect(_board(tester).view.rules.ply, 1);
        expect(_board(tester).enabled, isFalse);
        expect(
          tester.widget<LunoButton>(continueButton).onPressed,
          isNotNull,
          reason: 'A completed lesson must not require resetting after return.',
        );
        expect(store.tutorialStep, 1);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'accepted academy move is counted once across $boundary await boundary',
      (tester) async {
        _prepare(tester);
        await tester.pumpWidget(_app(const BattleV1Screen(practiceStage: 0)));
        await tester.pump();
        await tester.pump();
        final dynamic state = tester.state(find.byType(BattleV1Screen));
        final session = state.localSession as BattleV1LocalSession;
        final progress = state.practice as BattlePracticeProgress;
        final ownerRevision = GameStore.instance.accountBindingRevision;
        expect(progress.moves, 0);
        expect(session.version, 0);

        _board(tester).onTap(12);
        await tester.pump();
        expect(_board(tester).targets, contains(28));
        final oldTap = _board(tester).onTap;
        oldTap(28);
        expect(
          session.version,
          1,
          reason: 'The authority already accepted e2e4.',
        );
        final navigator = Navigator.of(
          tester.element(find.byType(BattleV1Screen)),
        );
        if (boundary == 'inactive') {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
        } else {
          unawaited(
            navigator.push(
              MaterialPageRoute<void>(
                builder: (_) => const Scaffold(body: Text('practice-cover')),
              ),
            ),
          );
        }
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        oldTap(28);
        await tester.pump();
        expect(
          session.version,
          1,
          reason: 'Hidden input must remain rejected.',
        );
        expect(GameStore.instance.accountBindingRevision, ownerRevision);
        expect(
          progress.moves,
          1,
          reason:
              'Accepted authority progress must survive a visibility change.',
        );

        if (boundary == 'inactive') {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
        } else {
          navigator.pop();
        }
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(
          progress.moves,
          1,
          reason: 'Returning must not double-count it.',
        );
        expect(tester.takeException(), isNull);
        // Dispose first so draining the delay cannot start another bot action.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 1));
        expect(tester.takeException(), isNull);
      },
    );
  }
}
