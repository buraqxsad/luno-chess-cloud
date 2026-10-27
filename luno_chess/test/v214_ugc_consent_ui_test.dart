import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luno_chess/i18n/luno_localizations.dart';
import 'package:luno_chess/models/app_settings.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'package:luno_chess/services/ugc_consent.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'online_request_session_test.dart' show TestAuth, TestUser;
import 'v214_ugc_safety_test.dart' show ugcRecord, ugcReply;

bool _fontsLoaded = false;

Future<void> _captureFonts(WidgetTester tester) async {
  if (Platform.environment['LUNO_QA_CAPTURE'] != '1' || _fontsLoaded) return;
  await tester.runAsync(() async {
    for (final entry
        in {
          'Nunito': 'assets/fonts/nunito/nunito-variable.ttf',
          'Cinzel': 'assets/fonts/cinzel-latin.ttf',
          'CinzelTurkish': 'assets/fonts/cinzel-turkish.ttf',
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

Future<void> accept(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('ugc-consent-checkbox')));
  await tester.tap(find.byKey(const Key('ugc-consent-checkbox')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('ugc-consent-accept')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  for (final scenario in [
    'decline',
    'success',
    'malformed',
    'account',
    'store',
    'covered',
    'disposed',
    'duplicate',
    'target',
  ]) {
    testWidgets('UGC acknowledgement owns session and modal: $scenario', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      LunoSettings.instance.language = LunoSettings.languageEnglish;
      final auth = TestAuth();
      final store =
          GameStore.createForTesting()
            ..loaded = true
            ..accountUid = 'first';
      final consent = UgcConsent();
      final reply = Completer<http.Response>();
      var requests = 0, relevant = true;
      final online = LunoOnlineService.forTesting(
        bootstrap: () async {},
        auth: auth,
        appCheck: () async => 'check',
        client: MockClient((request) {
          requests++;
          return reply.future;
        }),
      );
      addTearDown(() {
        consent.dispose();
        online.dispose();
        store.dispose();
      });
      await online.start();
      final navigator = GlobalKey<NavigatorState>();
      final futures = <Future<bool>>[];
      BuildContext? ownerContext;
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          theme: LunoTheme.dark,
          locale: const Locale('en'),
          supportedLocales: LunoLocalizations.supportedLocales,
          localizationsDelegates: const [
            LunoLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(
            body: Builder(
              builder: (context) {
                ownerContext = context;
                return FilledButton(
                  onPressed: () {
                    final future = consent.ensure(
                      context: context,
                      online: online,
                      playerStore: store,
                      isRelevant: () => relevant,
                    );
                    future.ignore();
                    futures.add(future);
                  },
                  child: const Text('Publish'),
                );
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('Publish'));
      await tester.pumpAndSettle();
      expect(requests, 0);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('ugc-consent-accept')))
            .onPressed,
        isNull,
      );
      if (scenario == 'decline') {
        await tester.tap(find.byKey(const Key('ugc-consent-decline')));
        await tester.pumpAndSettle();
        expect(await futures.single, false);
        expect(requests, 0);
      } else if (scenario == 'duplicate') {
        expect(
          await consent.ensure(
            context: ownerContext!,
            online: online,
            playerStore: store,
          ),
          false,
        );
        await accept(tester);
        expect(requests, 1);
        reply.complete(http.Response(jsonEncode(ugcReply('first')), 200));
        await tester.pumpAndSettle();
        expect(await futures.single, true);
      } else if (scenario == 'covered') {
        await tester.ensureVisible(
          find.byKey(const Key('ugc-consent-checkbox')),
        );
        await tester.tap(find.byKey(const Key('ugc-consent-checkbox')));
        await tester.pumpAndSettle();
        final oldAccept =
            tester
                .widget<FilledButton>(
                  find.byKey(const Key('ugc-consent-accept')),
                )
                .onPressed!;
        unawaited(
          navigator.currentState!.push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('Cover')),
            ),
          ),
        );
        await tester.pumpAndSettle();
        oldAccept();
        await tester.pumpAndSettle();
        expect(requests, 0);
        expect(find.text('Cover'), findsOneWidget);
        navigator.currentState!.pop();
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('ugc-consent-decline')));
        await tester.pumpAndSettle();
        expect(await futures.single, false);
      } else {
        await accept(tester);
        expect(requests, 1);
        if (scenario == 'account') auth.currentUser = TestUser('second');
        if (scenario == 'store') await store.bindAccount('second');
        if (scenario == 'target') relevant = false;
        if (scenario == 'disposed') {
          consent.dispose();
          await tester.pumpWidget(const SizedBox());
        }
        reply.complete(
          http.Response(
            jsonEncode(
              scenario == 'malformed' ? {'ok': true} : ugcReply('first'),
            ),
            200,
          ),
        );
        await tester.pumpAndSettle();
        if (scenario == 'malformed') {
          await expectLater(futures.single, throwsFormatException);
        } else if (scenario == 'disposed') {
          expect(await futures.single, false);
        } else {
          expect(await futures.single, scenario == 'success');
        }
      }
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.containsKey(ugcConsentStorageKey('first')),
        scenario == 'success' || scenario == 'duplicate',
      );
      expect(prefs.containsKey(ugcConsentStorageKey('second')), false);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'persisted acceptance is not reused by another account or an old version',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        ugcConsentStorageKey('first'): jsonEncode(ugcRecord('first')),
      });
      final auth = TestAuth(), consent = UgcConsent();
      final online = LunoOnlineService.forTesting(
        bootstrap: () async {},
        auth: auth,
        appCheck: () async => 'check',
      );
      addTearDown(() {
        consent.dispose();
        online.dispose();
      });
      await online.start();
      BuildContext? owner;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              owner = context;
              return const Scaffold();
            },
          ),
        ),
      );
      expect(await consent.ensure(context: owner!, online: online), true);
      auth.currentUser = TestUser('second');
      final next = consent.ensure(context: owner!, online: online);
      await tester.pumpAndSettle();
      expect(find.byType(UgcConsentDialog), findsOneWidget);
      await tester.tap(find.byKey(const Key('ugc-consent-decline')));
      await tester.pumpAndSettle();
      expect(await next, false);
      auth.currentUser = TestUser('first');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        ugcConsentStorageKey('first'),
        jsonEncode({...ugcRecord('first'), 'communityVersion': 'old'}),
      );
      final outdated = consent.ensure(context: owner!, online: online);
      await tester.pumpAndSettle();
      expect(find.byType(UgcConsentDialog), findsOneWidget);
      await tester.tap(find.byKey(const Key('ugc-consent-decline')));
      await tester.pumpAndSettle();
      expect(await outdated, false);
    },
  );
  for (final language in ['tr', 'en']) {
    for (final width in [320.0, 390.0, 768.0]) {
      testWidgets('consent real layout $language $width at 1.5 text scale', (
        tester,
      ) async {
        await _captureFonts(tester);
        tester.view.physicalSize = Size(width, 760);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        LunoSettings.instance.language = language;
        await tester.pumpWidget(
          RepaintBoundary(
            key: const Key('ugc-capture'),
            child: MaterialApp(
              theme: LunoTheme.dark,
              locale: Locale(language),
              supportedLocales: LunoLocalizations.supportedLocales,
              localizationsDelegates: const [
                LunoLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              builder:
                  (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(1.5)),
                    child: child!,
                  ),
              home: Scaffold(
                body: Builder(
                  builder:
                      (context) => FilledButton(
                        onPressed:
                            () => showDialog<void>(
                              context: context,
                              builder: (_) => const UgcConsentDialog(),
                            ),
                        child: const Text('Show'),
                      ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Show'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final buttons = find.byType(FilledButton);
        expect(tester.getSize(buttons.last).height, greaterThanOrEqualTo(48));
        if (Platform.environment['LUNO_QA_CAPTURE'] == '1') {
          final render = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const Key('ugc-capture')),
          );
          await tester.runAsync(() async {
            final image = await render.toImage(pixelRatio: 1);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final file = File(
              'qa/v214/visual/ugc-$language-${width.toInt()}.png',
            );
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.ensureVisible(
          find.byKey(const Key('ugc-consent-checkbox')),
        );
        await tester.tap(find.byKey(const Key('ugc-consent-checkbox')));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('ugc-consent-accept')))
              .onPressed,
          isNotNull,
        );
      });
    }
  }
}
