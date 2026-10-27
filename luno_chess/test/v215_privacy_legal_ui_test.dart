import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/i18n/luno_localizations.dart';
import 'package:luno_chess/services/legal_link_service.dart';
import 'package:luno_chess/services/product_privacy_settings.dart';
import 'package:luno_chess/services/product_telemetry.dart';
import 'package:luno_chess/services/ugc_consent.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

bool fontsLoaded = false;
Future<void> fonts(WidgetTester tester) async {
  if (Platform.environment['LUNO_QA_CAPTURE'] != '1' || fontsLoaded) return;
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
  fontsLoaded = true;
}

Future<void> capture(WidgetTester tester, String name) async {
  if (Platform.environment['LUNO_QA_CAPTURE'] != '1') return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('capture')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('qa/v215/visual/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Widget harness(String language, Widget dialog) => RepaintBoundary(
  key: const Key('capture'),
  child: MaterialApp(
    theme: LunoTheme.dark,
    locale: Locale(language),
    debugShowCheckedModeBanner: false,
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
                    builder: (_) => dialog,
                  ),
              child: const Text('Show'),
            ),
      ),
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'legal allowlist rejects unsafe scheme, host, userinfo, fragment and query',
    () async {
      final calls = <String>[];
      final service = LegalLinkService(
        launch: (url) async {
          calls.add(url);
          return true;
        },
      );
      for (final url in [
        'http://luno-legal-site.vercel.app/',
        'https://evil.example/',
        '$ugcTermsUrl?token=secret',
        '$ugcPrivacyUrl#secret',
        'https://luno-legal-site.vercel.app@evil.example/',
        'javascript:alert(1)',
        'https://luno-legal-site.vercel.app/delete-account',
        ' $ugcTermsUrl',
      ]) {
        expect(await service.open(url), isFalse);
      }
      expect(calls, isEmpty);
      expect(await service.open(ugcTermsUrl), isTrue);
      expect(await service.open(ugcPrivacyUrl), isTrue);
      expect(calls, [ugcTermsUrl, ugcPrivacyUrl]);
    },
  );

  test(
    'missing external-browser channel fails safely rather than throwing',
    () async {
      final service = LegalLinkService(
        launch: (_) async => throw PlatformException(code: 'missing'),
      );
      expect(await service.open(ugcTermsUrl), isFalse);
    },
  );

  for (final language in ['tr', 'en']) {
    for (final width in [320.0, 390.0, 430.0, 768.0]) {
      for (final screen in ['ugc', 'privacy']) {
        testWidgets('$screen real fonts $language $width at 1.5', (
          tester,
        ) async {
          await fonts(tester);
          tester.view.physicalSize = Size(width, 760);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final telemetry = ProductTelemetry(
            flushDelay: const Duration(days: 1),
          );
          addTearDown(telemetry.dispose);
          await tester.runAsync(
            () => telemetry.bindOwner(
              uid: 'player_self',
              isCurrent: () => true,
              request:
                  (_, _) async => {
                    'ok': true,
                    'consent': {
                      'version': 1,
                      'revision': 0,
                      'analytics': false,
                      'diagnostics': false,
                    },
                  },
            ),
          );
          await tester.pumpWidget(
            harness(
              language,
              screen == 'ugc'
                  ? const UgcConsentDialog()
                  : ProductPrivacyDialog(telemetry: telemetry),
            ),
          );
          await tester.tap(find.text('Show'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await capture(tester, '$screen-$language-${width.toInt()}-150');
          if (screen == 'ugc') {
            expect(
              find.byTooltip(
                language == 'en'
                    ? 'Open policy in browser'
                    : 'Politikayı tarayıcıda aç',
              ),
              findsNWidgets(2),
            );
            await tester.ensureVisible(
              find.byKey(const Key('ugc-consent-checkbox')),
            );
            expect(
              tester
                  .widget<FilledButton>(
                    find.byKey(const Key('ugc-consent-accept')),
                  )
                  .onPressed,
              isNull,
            );
          } else {
            expect(
              tester
                  .widget<SwitchListTile>(
                    find.byKey(const Key('product-analytics-consent')),
                  )
                  .value,
              isFalse,
            );
            expect(
              tester
                  .widget<SwitchListTile>(
                    find.byKey(const Key('product-diagnostics-consent')),
                  )
                  .value,
              isFalse,
            );
            await tester.ensureVisible(
              find.byKey(const Key('product-diagnostics-consent')),
            );
            expect(
              find.text(language == 'en' ? 'Save choice' : 'Seçimi kaydet'),
              findsOneWidget,
            );
          }
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  testWidgets('optional privacy decline makes no mutation', (tester) async {
    final requests = <String>[];
    final telemetry = ProductTelemetry();
    addTearDown(telemetry.dispose);
    await tester.runAsync(
      () => telemetry.bindOwner(
        uid: 'player_self',
        isCurrent: () => true,
        request: (path, body) async {
          requests.add(path);
          return {
            'ok': true,
            'consent': {
              'version': 1,
              'revision': 0,
              'analytics': false,
              'diagnostics': false,
            },
          };
        },
      ),
    );
    await tester.pumpWidget(
      harness('en', ProductPrivacyDialog(telemetry: telemetry)),
    );
    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(requests, ['/getProductTelemetryConsent']);
    expect(find.byType(ProductPrivacyDialog), findsNothing);
  });

  testWidgets(
    'optional privacy save is single-flight and waits for server confirmation',
    (tester) async {
      final pending = Completer<Map<String, dynamic>>();
      var mutations = 0;
      final telemetry = ProductTelemetry();
      addTearDown(telemetry.dispose);
      await tester.runAsync(
        () => telemetry.bindOwner(
          uid: 'player_self',
          isCurrent: () => true,
          request: (path, body) async {
            if (path == '/setProductTelemetryConsent') {
              mutations++;
              return pending.future;
            }
            return {
              'ok': true,
              'consent': {
                'version': 1,
                'revision': 0,
                'analytics': false,
                'diagnostics': false,
              },
            };
          },
        ),
      );
      await tester.pumpWidget(
        harness('en', ProductPrivacyDialog(telemetry: telemetry)),
      );
      await tester.tap(find.text('Show'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('product-analytics-consent')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save choice'));
      await tester.pump();
      expect(mutations, 1);
      expect(find.byType(ProductPrivacyDialog), findsOneWidget);
      expect(
        await telemetry.setConsent(analytics: true, diagnostics: false),
        isFalse,
      );
      pending.complete({
        'ok': true,
        'consent': {
          'version': 1,
          'revision': 1,
          'analytics': true,
          'diagnostics': false,
        },
      });
      await tester.pumpAndSettle();
      expect(find.byType(ProductPrivacyDialog), findsNothing);
      expect(mutations, 1);
    },
  );

  for (final stale in ['covered', 'disposed', 'account']) {
    testWidgets('retained privacy save callback is inert when $stale', (
      tester,
    ) async {
      var current = true, mutations = 0;
      final telemetry = ProductTelemetry();
      addTearDown(telemetry.dispose);
      await tester.runAsync(
        () => telemetry.bindOwner(
          uid: 'player_self',
          isCurrent: () => current,
          request: (path, body) async {
            if (path == '/setProductTelemetryConsent') mutations++;
            return {
              'ok': true,
              'consent': {
                'version': 1,
                'revision': 0,
                'analytics': false,
                'diagnostics': false,
              },
            };
          },
        ),
      );
      await tester.pumpWidget(
        harness('en', ProductPrivacyDialog(telemetry: telemetry)),
      );
      await tester.tap(find.text('Show'));
      await tester.pumpAndSettle();
      final callback =
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Save choice'),
              )
              .onPressed!;
      if (stale == 'covered') {
        final context = tester.element(find.byType(ProductPrivacyDialog));
        unawaited(
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('Cover')),
            ),
          ),
        );
        await tester.pumpAndSettle();
      } else if (stale == 'disposed') {
        await tester.pumpWidget(const SizedBox());
      } else {
        current = false;
      }
      callback();
      await tester.pumpAndSettle();
      expect(mutations, 0);
      expect(tester.takeException(), isNull);
      if (stale == 'covered') expect(find.text('Cover'), findsOneWidget);
    });
  }

  testWidgets('failed consent can retry in place without opting in', (
    tester,
  ) async {
    var requests = 0;
    final telemetry = ProductTelemetry();
    addTearDown(telemetry.dispose);
    await tester.runAsync(
      () => telemetry.bindOwner(
        uid: 'player_self',
        isCurrent: () => true,
        request: (path, body) async {
          requests++;
          if (requests == 1) throw TimeoutException('offline');
          return {
            'ok': true,
            'consent': {
              'version': 1,
              'revision': 0,
              'analytics': false,
              'diagnostics': false,
            },
          };
        },
      ),
    );
    await tester.pumpWidget(
      harness('en', ProductPrivacyDialog(telemetry: telemetry)),
    );
    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('product-consent-retry')));
    await tester.tap(find.byKey(const Key('product-consent-retry')));
    await tester.pumpAndSettle();
    expect(requests, 2);
    expect(telemetry.confirmed, isTrue);
    expect(telemetry.consent.analytics, isFalse);
    expect(telemetry.consent.diagnostics, isFalse);
  });
}
