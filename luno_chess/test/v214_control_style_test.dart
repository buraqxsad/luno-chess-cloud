import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/art.dart';
import 'package:luno_chess/battle_ui/primitives.dart';
import 'package:luno_chess/battle_ui/tokens.dart';
import 'package:luno_chess/i18n/luno_localizations.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:luno_chess/theme/luno_visual_assets.dart';
import 'package:luno_chess/widgets/luno_surface.dart';

const _capture = bool.fromEnvironment('V214_CAPTURE');
bool _fontsLoaded = false;

Widget _shell(
  Widget child, {
  String language = 'en',
  double scale = 1,
  bool reduced = false,
}) => MaterialApp(
  locale: Locale(language),
  supportedLocales: LunoLocalizations.supportedLocales,
  localizationsDelegates: const [
    LunoLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  theme: LunoTheme.dark,
  home: Builder(
    builder:
        (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: reduced,
          ),
          child: Scaffold(body: child),
        ),
  ),
);

BoxDecoration _lunoDecoration(WidgetTester tester, Finder control) =>
    tester
            .widget<AnimatedContainer>(
              find.descendant(
                of: control,
                matching: find.byType(AnimatedContainer),
              ),
            )
            .decoration!
        as BoxDecoration;

BoxDecoration _battleDecoration(WidgetTester tester, Finder control) =>
    tester
            .widget<AnimatedContainer>(
              find.descendant(
                of: control,
                matching: find.byKey(const ValueKey('battle-command-face')),
              ),
            )
            .decoration!
        as BoxDecoration;

Future<void> _fonts(WidgetTester tester) async {
  if (!_capture || _fontsLoaded) return;
  await tester.runAsync(() async {
    for (final entry
        in {
          'Cinzel': 'assets/fonts/cinzel-latin.ttf',
          'CinzelTurkish': 'assets/fonts/cinzel-turkish.ttf',
          'Nunito': 'assets/fonts/nunito/nunito-variable.ttf',
          'Spectral': 'assets/fonts/spectral/spectral-regular-latin.ttf',
          'SpectralTurkish':
              'assets/fonts/spectral/spectral-regular-turkish.ttf',
          'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
        }.entries) {
      await (FontLoader(entry.key)
        ..addFont(rootBundle.load(entry.value))).load();
    }
  });
  _fontsLoaded = true;
}

Widget _atlas(String language, GlobalKey boundary) {
  final tr = language == 'tr';
  final labels = [
    tr ? 'Tekrar Oyna' : 'Play Again',
    tr ? 'Desteyi D\u00fczenle' : 'Edit Deck',
    tr ? 'Engelle' : 'Block Player',
    tr ? '\u0130ptal' : 'Cancel',
    tr ? 'Koleksiyon' : 'Collection',
    tr ? 'Kart\u0131 Kullan' : 'Play Card',
  ];
  return SingleChildScrollView(
    child: RepaintBoundary(
      key: boundary,
      child: ColoredBox(
        color: LunoColors.bgDeep,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < LunoButtonKind.values.length; i++) ...[
                LunoButton(
                  key: ValueKey('luno-$i'),
                  label: labels[i],
                  kind: LunoButtonKind.values[i],
                  icon:
                      i == 2 ? Icons.person_off_outlined : Icons.chevron_right,
                  onPressed: () {},
                ),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 8),
              BattleCommand(
                key: const ValueKey('battle-primary'),
                label: tr ? 'Kart\u0131 Kullan' : 'Play Card',
                icon: Icons.auto_fix_high,
                primary: true,
                onPressed: () {},
              ),
              const SizedBox(height: 8),
              BattleCommand(
                label: tr ? 'Rakibin Kartlar\u0131' : 'Opponent Cards',
                icon: Icons.style_outlined,
                onPressed: () {},
              ),
              const SizedBox(height: 8),
              BattleCommand(
                label: tr ? 'Teslim Ol' : 'Resign',
                icon: Icons.flag_outlined,
                danger: true,
                onPressed: () {},
              ),
              const SizedBox(height: 8),
              BattleCommand(
                label: tr ? '\u0130ptal' : 'Cancel',
                icon: Icons.close,
                quiet: true,
                onPressed: () {},
              ),
              const SizedBox(height: 8),
              BattleCommand(
                label: tr ? 'Onayla' : 'Confirm',
                icon: Icons.check,
                primary: true,
                loading: true,
                onPressed: () {},
              ),
              const SizedBox(height: 8),
              LunoButton(
                key: const ValueKey('last-control'),
                label: tr ? 'Al\u0131nd\u0131' : 'Claimed',
                onPressed: null,
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final style in LunoIconContext.values)
                    LunoIconControl(
                      icon:
                          style == LunoIconContext.sheet
                              ? Icons.close
                              : Icons.arrow_back,
                      label:
                          style == LunoIconContext.sheet
                              ? (tr ? 'Kapat' : 'Close')
                              : (tr ? 'Geri' : 'Back'),
                      contextStyle: style,
                      onPressed: () {},
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    for (final channel in [
      'xyz.luan/audioplayers',
      'xyz.luan/audioplayers/events',
      'xyz.luan/audioplayers.global',
      'xyz.luan/audioplayers.global/events',
      for (final id in ['luno_music', 'luno_sfx_0', 'luno_sfx_1', 'luno_sfx_2'])
        'xyz.luan/audioplayers/events/$id',
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(channel), (_) async => null);
    }
  });

  testWidgets('shared semantic roles have distinct, intentional treatments', (
    tester,
  ) async {
    await tester.pumpWidget(_shell(_atlas('en', GlobalKey())));
    BoxDecoration role(int i) =>
        _lunoDecoration(tester, find.byKey(ValueKey('luno-$i')));
    expect(role(0).image!.image, const AssetImage(LunoVisualAssets.primary));
    expect(role(1).image!.image, const AssetImage(LunoVisualAssets.secondary));
    expect(role(2).image!.image, const AssetImage(LunoVisualAssets.danger));
    expect(role(3).image, isNull);
    expect(role(3).color, Colors.transparent);
    expect(
      (role(4).border! as Border).top.color,
      LunoColors.teal.withValues(alpha: .55),
    );
    expect(role(5).image, isNull);
    expect(
      (role(5).border! as Border).top.color,
      LunoColors.cyan.withValues(alpha: .55),
    );
    expect(
      role(0).boxShadow!.first.blurRadius,
      greaterThan(role(1).boxShadow!.first.blurRadius),
    );
  });

  testWidgets('battle secondary and tertiary do not reuse the primary art', (
    tester,
  ) async {
    await tester.pumpWidget(_shell(_atlas('en', GlobalKey())));
    final commands = find.byType(BattleCommand);
    expect(
      _battleDecoration(tester, commands.at(0)).image!.image,
      AssetImage(BattleArt.path('action-face')),
    );
    expect(_battleDecoration(tester, commands.at(1)).image, isNull);
    expect(
      _battleDecoration(tester, commands.at(2)).image!.image,
      const AssetImage(LunoVisualAssets.danger),
    );
    expect(_battleDecoration(tester, commands.at(3)).image, isNull);
    expect(_battleDecoration(tester, commands.at(3)).color, Colors.transparent);
  });

  testWidgets(
    'pending and disabled guards expose their actual semantic state',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        var taps = 0;
        await tester.pumpWidget(
          _shell(
            Column(
              children: [
                LunoButton(
                  key: const ValueKey('pending'),
                  label: 'Confirm',
                  loading: true,
                  onPressed: () => taps++,
                ),
                const LunoButton(
                  key: ValueKey('disabled'),
                  label: 'Claimed',
                  onPressed: null,
                ),
                BattleCommand(
                  key: const ValueKey('battle-pending'),
                  label: 'Confirm Move',
                  icon: Icons.check,
                  primary: true,
                  loading: true,
                  onPressed: () => taps++,
                ),
              ],
            ),
          ),
        );
        for (final key in ['pending', 'disabled', 'battle-pending']) {
          final label = switch (key) {
            'pending' => 'Confirm',
            'disabled' => 'Claimed',
            _ => 'Confirm Move',
          };
          final node = tester.getSemantics(find.bySemanticsLabel(label));
          expect(node.flagsCollection.isButton, true);
          expect(node.flagsCollection.isEnabled, ui.Tristate.isFalse);
          expect(
            node.getSemanticsData().hasAction(ui.SemanticsAction.tap),
            false,
          );
          await tester.tap(find.byKey(ValueKey(key)));
        }
        expect(taps, 0);
        expect(
          tester.getSemantics(find.bySemanticsLabel('Confirm')).value,
          isNotEmpty,
        );
        expect(
          _lunoDecoration(
            tester,
            find.byKey(const ValueKey('pending')),
          ).image!.image,
          const AssetImage(LunoVisualAssets.primary),
        );
        expect(
          _lunoDecoration(
            tester,
            find.byKey(const ValueKey('disabled')),
          ).image!.image,
          const AssetImage(LunoVisualAssets.disabled),
        );
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('contextual icon variants retain 48px targets and one label', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      var taps = 0;
      await tester.pumpWidget(
        _shell(
          Column(
            children: [
              for (final style in LunoIconContext.values)
                LunoIconControl(
                  key: ValueKey(style),
                  label: 'Back ${style.name}',
                  icon: Icons.arrow_back,
                  contextStyle: style,
                  onPressed: () => taps++,
                ),
              BattleIconControl(
                icon: Icons.close,
                label: 'Close',
                onPressed: () {},
              ),
            ],
          ),
        ),
      );
      final fills = <Color>{};
      for (final style in LunoIconContext.values) {
        final finder = find.byKey(ValueKey(style));
        expect(tester.getSize(finder), const Size(48, 48));
        expect(find.bySemanticsLabel('Back ${style.name}'), findsOneWidget);
        final native = tester.widget<IconButton>(
          find.descendant(of: finder, matching: find.byType(IconButton)),
        );
        fills.add(native.style!.backgroundColor!.resolve({})!);
        final node = tester.getSemantics(
          find.bySemanticsLabel('Back ${style.name}'),
        );
        expect(node.getSemanticsData().hasAction(ui.SemanticsAction.tap), true);
        tester.semantics.tap(find.semantics.byLabel('Back ${style.name}'));
        await tester.pump();
      }
      expect(fills, hasLength(4));
      expect(taps, 4);
      final close = tester.widget<LunoIconControl>(
        find.descendant(
          of: find.byType(BattleIconControl),
          matching: find.byType(LunoIconControl),
        ),
      );
      expect(close.contextStyle, LunoIconContext.sheet);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('battle press is acknowledged without duplicate activation', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      var taps = 0;
      final control = find.byType(BattleCommand);
      await tester.pumpWidget(
        _shell(
          Center(
            child: BattleCommand(
              label: 'Play Card',
              icon: Icons.auto_fix_high,
              primary: true,
              onPressed: () => taps++,
            ),
          ),
        ),
      );
      final before =
          (_battleDecoration(tester, control).border! as Border).top.color;
      final gesture = await tester.startGesture(tester.getCenter(control));
      await tester.pump(const Duration(milliseconds: 80));
      final pressed =
          (_battleDecoration(tester, control).border! as Border).top.color;
      expect(pressed, isNot(before));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 200));
      expect(taps, 1);
      final node = tester.getSemantics(control);
      expect(find.bySemanticsLabel('Play Card'), findsOneWidget);
      expect(node.getSemanticsData().hasAction(ui.SemanticsAction.tap), true);
      tester.semantics.tap(find.semantics.byLabel('Play Card'));
      await tester.pump();
      expect(taps, 2);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('drag, disable and disposal cancel visual press state', (
    tester,
  ) async {
    var taps = 0;
    var enabled = true;
    late StateSetter update;
    await tester.pumpWidget(
      _shell(
        StatefulBuilder(
          builder: (_, setter) {
            update = setter;
            return Center(
              child: LunoButton(
                label: 'Confirm',
                onPressed: enabled ? () => taps++ : null,
              ),
            );
          },
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(LunoButton)),
    );
    await tester.pump(const Duration(milliseconds: 80));
    expect(
      tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale,
      lessThan(1),
    );
    await gesture.moveBy(const Offset(90, 0));
    await tester.pump(const Duration(milliseconds: 150));
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
    update(() => enabled = false);
    await tester.pump();
    await gesture.up();
    expect(taps, 0);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion retains status without scale or busy ticker', (
    tester,
  ) async {
    await tester.pumpWidget(
      _shell(
        Column(
          children: [
            LunoButton(label: 'Confirm', onPressed: () {}, loading: true),
            BattleCommand(
              label: 'Play Card',
              icon: Icons.check,
              primary: true,
              onPressed: () {},
            ),
            LunoIconControl(
              label: 'Back',
              icon: Icons.arrow_back,
              onPressed: () {},
            ),
          ],
        ),
        reduced: true,
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(BattleCommand)),
    );
    await tester.pump();
    for (final element in find.byType(AnimatedScale).evaluate()) {
      final scale = element.widget as AnimatedScale;
      expect(scale.scale, 1);
      expect(scale.duration, Duration.zero);
    }
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
      _battleDecoration(tester, find.byType(BattleCommand)).image!.image,
      AssetImage(BattleArt.path('action-face')),
    );
    await gesture.cancel();
  });

  testWidgets('pending preserves the command label and occupied geometry', (
    tester,
  ) async {
    Widget command(bool loading) => _shell(
      Center(
        child: SizedBox(
          width: 290,
          child: LunoButton(
            key: const ValueKey('stable-command'),
            label: 'Confirm',
            icon: Icons.check,
            onPressed: () {},
            loading: loading,
          ),
        ),
      ),
      scale: 1.5,
    );
    await tester.pumpWidget(command(false));
    final size = tester.getSize(find.byKey(const ValueKey('stable-command')));
    await tester.pumpWidget(command(true));
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('Confirm'), findsOneWidget);
    expect(tester.getSize(find.byKey(const ValueKey('stable-command'))), size);
    await tester.pumpWidget(const SizedBox());
  });

  test(
    'shared foregrounds meet normal-text contrast on native control bases',
    () {
      double ratio(Color text, Color surface) =>
          (text.computeLuminance() + .05) / (surface.computeLuminance() + .05);
      for (final surface in [
        LunoColors.bgPanel,
        LunoColors.bgRaised,
        BattleTokens.surface,
        const Color(0xFF351D29),
      ]) {
        expect(ratio(LunoColors.ivory, surface), greaterThanOrEqualTo(4.5));
        expect(ratio(LunoColors.textDim, surface), greaterThanOrEqualTo(4.5));
      }
    },
  );

  testWidgets('background and covered ticker reset a held press safely', (
    tester,
  ) async {
    var ticker = true;
    late StateSetter update;
    await tester.pumpWidget(
      _shell(
        StatefulBuilder(
          builder: (_, setter) {
            update = setter;
            return TickerMode(
              enabled: ticker,
              child: Center(
                child: LunoButton(label: 'Confirm', onPressed: () {}),
              ),
            );
          },
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(LunoButton)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale,
      lessThan(1),
    );
    tester.binding.handleAppLifecycleStateChanged(
      AppLifecycleState.paused,
    );
    await tester.pump();
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
    tester.binding.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
    await gesture.cancel();
    final next = await tester.startGesture(
      tester.getCenter(find.byType(LunoButton)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    update(() => ticker = false);
    await tester.pump();
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
    await next.cancel();
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('captured native callback cannot bypass a newly pending button', (
    tester,
  ) async {
    var busy = false, taps = 0;
    late StateSetter update;
    await tester.pumpWidget(
      _shell(
        StatefulBuilder(
          builder: (_, setter) {
            update = setter;
            return LunoButton(
              label: 'Confirm',
              loading: busy,
              onPressed: () => taps++,
            );
          },
        ),
      ),
    );
    final callback =
        tester
            .widget<InkWell>(
              find.descendant(
                of: find.byType(LunoButton),
                matching: find.byType(InkWell),
              ),
            )
            .onTap!;
    update(() => busy = true);
    await tester.pump();
    callback();
    expect(taps, 0);
    await tester.pumpWidget(const SizedBox());
    callback();
    expect(taps, 0);
    expect(tester.takeException(), isNull);
  });

  for (final language in ['tr', 'en']) {
    testWidgets('native states render $language without hiding busy identity', (
      tester,
    ) async {
      await _fonts(tester);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final boundary = GlobalKey();
      final tr = language == 'tr';
      var taps = 0;
      await tester.pumpWidget(
        _shell(
          Center(
            child: RepaintBoundary(
              key: boundary,
              child: ColoredBox(
                color: LunoColors.bgDeep,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      LunoButton(
                        label: tr ? 'Onayla' : 'Confirm',
                        icon: Icons.check,
                        onPressed: () => taps++,
                        loading: true,
                      ),
                      const SizedBox(height: 12),
                      BattleCommand(
                        key: const ValueKey('held-command'),
                        label: tr ? 'Kart\u0131 Kullan' : 'Play Card',
                        icon: Icons.auto_fix_high,
                        primary: true,
                        onPressed: () => taps++,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          LunoIconControl(
                            label: tr ? 'Geri' : 'Back',
                            icon: Icons.arrow_back,
                            onPressed: () => taps++,
                            loading: true,
                          ),
                          LunoIconControl(
                            label: tr ? 'Kapat' : 'Close',
                            icon: Icons.close,
                            contextStyle: LunoIconContext.sheet,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          language: language,
          scale: 1.5,
          reduced: true,
        ),
      );
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('held-command'))),
      );
      await tester.pump();
      expect(taps, 0);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
      if (_capture) {
        await tester.runAsync(() async {
          final render =
              boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await render.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final directory = Directory('qa/v214/visual/controls');
          await directory.create(recursive: true);
          await File(
            '${directory.path}/$language-states.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await gesture.cancel();
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final language in ['tr', 'en']) {
    for (final width in [320.0, 360.0, 390.0, 430.0, 768.0]) {
      for (final scale in [1.0, 1.3, 1.5]) {
        testWidgets('control atlas $language $width scale $scale', (
          tester,
        ) async {
          await _fonts(tester);
          tester.view.physicalSize = Size(width, width == 320 ? 568 : 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final boundary = GlobalKey();
          await tester.pumpWidget(
            _shell(
              _atlas(language, boundary),
              language: language,
              scale: scale,
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          for (final element in find.byType(LunoButton).evaluate()) {
            expect(
              tester.getSize(find.byWidget(element.widget)).height,
              greaterThanOrEqualTo(48),
            );
          }
          for (final element in find.byType(BattleCommand).evaluate()) {
            expect(
              tester.getSize(find.byWidget(element.widget)).height,
              greaterThanOrEqualTo(BattleTokens.touch),
            );
          }
          await tester.ensureVisible(
            find.byKey(const ValueKey('last-control')),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          if (_capture) {
            await tester.runAsync(() async {
              final render =
                  boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary;
              final image = await render.toImage(pixelRatio: 1);
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final directory = Directory('qa/v214/visual/controls');
              await directory.create(recursive: true);
              await File(
                '${directory.path}/$language-${width.toInt()}-$scale.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
          await tester.pumpWidget(const SizedBox());
        });
      }
    }
  }
}
