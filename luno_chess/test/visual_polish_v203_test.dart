import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/art.dart';
import 'package:luno_chess/battle_ui/effect_timing.dart';
import 'package:luno_chess/battle_ui/effects.dart';
import 'package:luno_chess/battle_ui/feedback.dart';
import 'package:luno_chess/battle_ui/spell_vfx.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/i18n/luno_localizations.dart';
import 'package:luno_chess/screens/shop_screen.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:luno_chess/theme/luno_visual_assets.dart';
import 'package:luno_chess/widgets/luno_polish.dart';
import 'package:luno_chess/widgets/luno_surface.dart';
import 'battle_ui/fixtures.dart';

Widget shell(
  Widget child, {
  bool reduced = false,
  bool ticker = true,
  String language = 'tr',
  double scale = 1,
}) => MaterialApp(
  locale: Locale(language),
  supportedLocales: LunoLocalizations.supportedLocales,
  localizationsDelegates: const [
    LunoLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  theme: LunoTheme.darkFor(language),
  builder:
      (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: reduced,
          textScaler: TextScaler.linear(scale),
          padding: const EdgeInsets.all(24),
        ),
        child: TickerMode(enabled: ticker, child: child!),
      ),
  home: Scaffold(body: child),
);

PlayerView view({RuleDraft? draft, PieceColor side = PieceColor.white}) {
  final base = battleFixture();
  return PlayerView(
    draft?.freeze() ?? base.rules,
    side,
    base.hidden.hands[side]!,
    base.hidden.knowledge[side]!,
  );
}

RuleDraft boardEffect(
  BoardEffectType type, {
  String id = 'cast-1',
  List<int> squares = const [12],
  PieceColor owner = PieceColor.white,
}) => RuleDraft(battleFixture().rules)
  ..boardEffects.add(
    BoardEffectInstance(
      id: id,
      type: type,
      owner: owner,
      squares: squares,
      responseSide: PieceColor.black,
      duration: EffectDuration.move,
    ),
  );

Finder pulses() => find.byWidgetPredicate(
  (w) =>
      w.key is ValueKey<String> &&
      (w.key as ValueKey<String>).value.startsWith('accepted-pulse-'),
);

Widget feedback(PlayerView v) => Center(
  child: SizedBox.square(
    dimension: 332,
    child: BattleAcceptedFeedback(view: v),
  ),
);

void main() {
  setUp(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final channel in [
      'xyz.luan/audioplayers.global/events',
      'xyz.luan/audioplayers.global',
      'xyz.luan/audioplayers',
      for (final id in ['luno_music', 'luno_sfx_0', 'luno_sfx_1', 'luno_sfx_2'])
        'xyz.luan/audioplayers/events/$id',
    ]) {
      messenger.setMockMethodCallHandler(
        MethodChannel(channel),
        (_) async => null,
      );
    }
  });
  testWidgets('V203 decoded button faces paint in compact reward controls', (
    tester,
  ) async {
    for (final size in [const Size(48, 36), const Size(40, 32)]) {
      await tester.pumpWidget(
        shell(
          Center(
            child: SizedBox.fromSize(
              size: size,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  image: lunoFace(LunoVisualAssets.primary, button: true),
                ),
              ),
            ),
          ),
          reduced: true,
        ),
      );
      await tester.runAsync(() async {
        await precacheImage(
          const AssetImage(LunoVisualAssets.primary),
          tester.element(find.byType(DecoratedBox).last),
        );
      });
      await tester.pump();
      expect(tester.takeException(), isNull, reason: '$size');
    }
  });
  testWidgets('V203 native compact reward button paints its decoded face', (
    tester,
  ) async {
    await tester.pumpWidget(
      shell(
        Center(
          child: FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size(48, 36),
              padding: const EdgeInsets.all(4),
            ),
            onPressed: () {},
            child: const Text('1'),
          ),
        ),
        reduced: true,
      ),
    );
    await tester.runAsync(
      () => precacheImage(
        const AssetImage(LunoVisualAssets.primary),
        tester.element(find.byType(FilledButton)),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
  for (final size in [
    const Size(320, 568),
    const Size(844, 390),
    const Size(800, 1100),
  ]) {
    for (final language in ['tr', 'en']) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('V203 surfaces fit $size $language x$scale', (
          tester,
        ) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          var taps = 0;
          await tester.pumpWidget(
            shell(
              SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: LunoSurface(
                    surfaceArt: LunoVisualAssets.collection,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        LunoButton(label: 'DEVAM ET', onPressed: () => taps++),
                        LunoButton(
                          label: 'TEKRAR DENE',
                          kind: LunoButtonKind.secondary,
                          onPressed: null,
                        ),
                        LunoButton(
                          label: 'HAZIRLANIYOR...',
                          onPressed: () => taps++,
                          loading: true,
                        ),
                        FilledButton(
                          onPressed: () => taps++,
                          child: const Text('Native'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              reduced: true,
              language: language,
              scale: scale,
            ),
          );
          await tester.pump(const Duration(milliseconds: 300));
          expect(tester.takeException(), isNull);
          expect(
            tester.getSize(find.byType(LunoButton).first).height,
            greaterThanOrEqualTo(48),
          );
          await tester.tap(find.byType(LunoButton).first);
          expect(taps, 1);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
  testWidgets('V203 labels are localized once and retain native action', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var taps = 0;
    await tester.pumpWidget(
      shell(
        LunoButton(label: 'DEVAM ET', onPressed: () => taps++),
        language: 'en',
      ),
    );
    await tester.pump();
    final label = LunoLocalizations.of(
      tester.element(find.byType(LunoButton)),
    ).translate('DEVAM ET');
    expect(find.bySemanticsLabel(label), findsOneWidget);
    await tester.tap(find.byType(LunoButton));
    expect(taps, 1);
    semantics.dispose();
  });
  testWidgets('V203 reduced motion cancels press displacement', (tester) async {
    await tester.pumpWidget(
      shell(LunoButton(label: 'DEVAM ET', onPressed: () {}), reduced: true),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(LunoButton)),
    );
    await tester.pump(const Duration(milliseconds: 120));
    final container = tester.widget<AnimatedContainer>(
      find.descendant(
        of: find.byType(LunoButton),
        matching: find.byType(AnimatedContainer),
      ),
    );
    expect(container.transform, isNull);
    final scale = tester.widget<AnimatedScale>(
      find.descendant(
        of: find.byType(LunoButton),
        matching: find.byType(AnimatedScale),
      ),
    );
    expect(scale.scale, 1);
    expect(scale.duration, Duration.zero);
    await gesture.cancel();
  });
  testWidgets('V203 press feedback returns and never triggers child twice', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      shell(
        LunoPressFeedback(
          child: TextButton(onPressed: () => taps++, child: const Text('Tap')),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Tap')),
    );
    await tester.pump(const Duration(milliseconds: 150));
    expect(
      tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale,
      .985,
    );
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 150));
    expect(taps, 1);
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
  });
  for (final type in BoardEffectType.values) {
    testWidgets('V203 accepted $type is a single bounded pulse', (
      tester,
    ) async {
      await tester.pumpWidget(shell(feedback(view())));
      expect(pulses(), findsNothing);
      final state = boardEffect(type), snapshot = state.freeze().toJson();
      await tester.pumpWidget(shell(feedback(view(draft: state))));
      expect(pulses(), findsOneWidget);
      final card = boardEffectCard(type);
      final duration = battleEffectDuration(card).inMilliseconds;
      final spell = find.byKey(ValueKey('spell-${card.wire}-0'));
      await tester.pump();
      await tester.pump(Duration(milliseconds: duration ~/ 4));
      expect(pulses(), findsOneWidget);
      expect(
        (tester.widget<CustomPaint>(spell).painter! as BattleSpellPainter)
            .progress,
        closeTo(.25, .002),
      );
      expect(
        tester
            .widget<Opacity>(
              find
                  .descendant(of: pulses(), matching: find.byType(Opacity))
                  .first,
            )
            .opacity,
        0,
        reason: 'The projectile owns the early phase, not the impact pulse',
      );
      await tester.pump(Duration(milliseconds: duration ~/ 2));
      expect(pulses(), findsOneWidget);
      expect(
        (tester.widget<CustomPaint>(spell).painter! as BattleSpellPainter)
            .progress,
        closeTo(.75, .002),
      );
      expect(
        tester
            .widget<Opacity>(
              find
                  .descendant(of: pulses(), matching: find.byType(Opacity))
                  .first,
            )
            .opacity,
        closeTo(.8, .001),
        reason: 'The accepted target is visibly marked during impact',
      );
      await tester.pump(Duration(milliseconds: duration ~/ 4 - 1));
      expect(pulses(), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1));
      expect(pulses(), findsNothing);
      expect(spell, findsNothing);
      await tester.pumpWidget(shell(feedback(view(draft: state))));
      expect(pulses(), findsNothing);
      expect(state.freeze().toJson(), snapshot);
    });
  }
  testWidgets(
    'V203 initial effects do not flash and enemy Mines animate publicly',
    (tester) async {
      await tester.pumpWidget(
        shell(feedback(view(draft: boardEffect(BoardEffectType.fog)))),
      );
      expect(pulses(), findsNothing);
      await tester.pumpWidget(
        shell(
          feedback(
            view(
              draft: boardEffect(
                BoardEffectType.mine,
                id: 'cast-2',
                owner: PieceColor.black,
              ),
            ),
          ),
        ),
      );
      expect(
        pulses(),
        findsOneWidget,
      ); // The new public Mine takes precedence over cleared Fog on the same square.
      expect(
        tester
            .widgetList<Image>(
              find.descendant(of: pulses(), matching: find.byType(Image)),
            )
            .map((image) => image.image),
        contains(ResizeImage(AssetImage(BattleArt.path('mine')), width: 128)),
      );
      await tester.pump(const Duration(milliseconds: 2800));
      await tester.pumpWidget(shell(feedback(view())));
      expect(pulses(), findsOneWidget);
      await tester.pumpWidget(
        shell(
          feedback(
            view(
              draft: boardEffect(BoardEffectType.mine, owner: PieceColor.black),
            ),
          ),
        ),
      );
      expect(pulses(), findsOneWidget);
    },
  );
  testWidgets('V203 pulse cap and orientation use the board inner grid', (
    tester,
  ) async {
    await tester.pumpWidget(shell(feedback(view(side: PieceColor.black))));
    await tester.pumpWidget(
      shell(
        feedback(
          view(
            side: PieceColor.black,
            draft: boardEffect(
              BoardEffectType.fog,
              squares: [12, 13, 20, 21, 28],
              owner: PieceColor.black,
            ),
          ),
        ),
      ),
    );
    expect(pulses(), findsNWidgets(4));
    final position = tester.widget<Positioned>(
      find.byKey(const ValueKey('accepted-pulse-12')),
    );
    expect(position.left, 120);
    expect(position.top, 40);
  });
  testWidgets('V203 reduced motion and viewer handoff drop pulse', (
    tester,
  ) async {
    await tester.pumpWidget(shell(feedback(view())));
    final state = boardEffect(BoardEffectType.lockedSquare);
    await tester.pumpWidget(shell(feedback(view(draft: state))));
    expect(pulses(), findsOneWidget);
    await tester.pumpWidget(shell(feedback(view(draft: state)), reduced: true));
    expect(pulses(), findsNothing);
    await tester.pumpWidget(
      shell(feedback(view(draft: state, side: PieceColor.black))),
    );
    expect(pulses(), findsNothing);
  });
  testWidgets('V203 covered and backgrounded feedback is not replayed', (
    tester,
  ) async {
    await tester.pumpWidget(shell(feedback(view()), ticker: false));
    final state = boardEffect(BoardEffectType.lockedSquare);
    await tester.pumpWidget(shell(feedback(view(draft: state)), ticker: false));
    await tester.pumpWidget(shell(feedback(view(draft: state))));
    expect(pulses(), findsNothing);
    await tester.pumpWidget(shell(feedback(view())));
    await tester.pumpWidget(shell(feedback(view(draft: state))));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(pulses(), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(pulses(), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'V203 chest settles without bounce and accepts reduced-motion change',
    (tester) async {
      await tester.pumpWidget(
        shell(const ChestRevealDialog(chestId: 'rare', rewards: [])),
      );
      await tester.pump(const Duration(milliseconds: 120));
      final scales =
          tester
              .widgetList<Transform>(find.byType(Transform))
              .where((w) => w.transform.storage[0] < 1)
              .toList();
      expect(scales, isNotEmpty);
      await tester.pumpWidget(
        shell(
          const ChestRevealDialog(chestId: 'rare', rewards: []),
          reduced: true,
        ),
      );
      await tester.pump();
      expect(find.text('SANDIK AÇILDI'), findsOneWidget);
      expect(find.text('HARİKA'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
