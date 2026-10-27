import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/battle_ui/board.dart';
import 'package:luno_chess/battle_v1/authoritative.dart';
import 'package:luno_chess/battle_v1/model.dart';
import 'package:luno_chess/engine/piece.dart';
import 'package:luno_chess/i18n/luno_localizations.dart';
import 'package:luno_chess/theme/luno_theme.dart';

const _boundaryKey = ValueKey('v216-costume-comparison');

Widget _shell(Widget child) => MaterialApp(
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
        child: RepaintBoundary(key: _boundaryKey, child: child!),
      ),
  home: child,
);

Future<void> _warm(WidgetTester tester) async {
  await tester.runAsync(() async {
    final context = tester.element(find.byType(Scaffold).first);
    for (final image in tester.widgetList<Image>(find.byType(Image)).toList()) {
      await precacheImage(image.image, context);
    }
  });
  await tester.pumpAndSettle();
}

const _sets = [
  'ottoman',
  'roma',
  'brit',
  'viking',
  'tasdevri',
  'samuray',
  'ice',
  'dragon',
  'neon',
];

class _ComparisonBundle extends CachingAssetBundle {
  _ComparisonBundle(bool candidate) {
    for (final set in _sets) {
      for (final side in ['w', 'b']) {
        for (final type in [
          'king',
          'queen',
          'rook',
          'bishop',
          'knight',
          'pawn',
        ]) {
          final stem = 'piece-$set-$side-$type';
          final path =
              candidate
                  ? 'assets/native_art/$stem-v216.webp'
                  : 'assets/native_art/$stem-v11-mobile.webp';
          final data = ByteData.sublistView(File(path).readAsBytesSync());
          _pieces['assets/native_art/$stem-v11-mobile.webp'] = data;
          _pieces['assets/native_art/$stem-v216.webp'] = data;
        }
      }
    }
  }
  final _pieces = <String, ByteData>{};

  @override
  Future<ByteData> load(String key) {
    final data = _pieces[key];
    return data == null ? rootBundle.load(key) : SynchronousFuture(data);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final font
        in {
          'Nunito': 'assets/fonts/nunito/nunito-variable.ttf',
          'Cinzel': 'assets/fonts/cinzel-latin.ttf',
          'CinzelTurkish': 'assets/fonts/cinzel-turkish.ttf',
          'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
        }.entries) {
      await (FontLoader(font.key)..addFont(rootBundle.load(font.value))).load();
    }
  });
  final state = DeckManager.newBattle(white: starterDeck, black: starterDeck);
  for (final set in _sets) {
    for (final size in [28.0, 40.0, 52.0]) {
      for (final candidate in [false, true]) {
        final stage = candidate ? 'candidate' : 'old';
        testWidgets('$set $stage real battle piece boxes ${size.toInt()}px', (
          tester,
        ) async {
          final boardWidth = 8 * (size + 4) + 12;
          tester.view.physicalSize = Size(boardWidth + 32, boardWidth + 72);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            _shell(
              DefaultAssetBundle(
                bundle: _ComparisonBundle(candidate),
                child: Scaffold(
                  body: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          '$set · $stage · ${size.toInt()} px',
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                      SizedBox(
                        width: boardWidth,
                        child: BattleBoard(
                          view: state.view(PieceColor.white),
                          pieceSet: set,
                          enabled: false,
                          onTap: (_) {},
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
          await _warm(tester);
          expect(find.byType(BattleBoard), findsOneWidget);
          expect(
            find.byWidgetPredicate((widget) {
              if (widget is! Image) return false;
              final provider =
                  widget.image is ResizeImage
                      ? (widget.image as ResizeImage).imageProvider
                      : widget.image;
              return provider is AssetImage &&
                  provider.assetName.startsWith('assets/native_art/piece-');
            }),
            findsNWidgets(32),
          );
          expect(tester.takeException(), isNull);
          await tester.runAsync(() async {
            final boundary =
                tester.element(find.byKey(_boundaryKey)).renderObject!
                    as RenderRepaintBoundary;
            final image = await boundary.toImage(pixelRatio: 1);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final directory = Directory('qa/v216/costume-art/boards');
            await directory.create(recursive: true);
            await File(
              '${directory.path}/$set-$stage-${size.toInt()}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
          await tester.pumpWidget(const SizedBox());
          tester.binding.imageCache.clear();
          tester.binding.imageCache.clearLiveImages();
        });
      }
    }
  }
}
