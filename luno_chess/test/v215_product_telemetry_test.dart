import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/services/first_session_telemetry.dart';
import 'package:luno_chess/services/product_crash_reporter.dart';
import 'package:luno_chess/services/product_telemetry.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'online_request_session_test.dart' show TestAuth;

const enabled = {
  'version': 1,
  'revision': 1,
  'analytics': true,
  'diagnostics': true,
};
const off = {
  'version': 1,
  'revision': 0,
  'analytics': false,
  'diagnostics': false,
};
const sample = FirstSessionSample(
  FirstSessionEvent.cardPlayed,
  15000,
  mode: SessionMatchMode.ai,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'production bind is inert before readiness and shares one consent fetch',
    () async {
      final auth = TestAuth();
      final store =
          GameStore.createForTesting()
            ..loaded = true
            ..accountUid = 'first';
      final pending = Completer<http.Response>();
      final entered = Completer<void>();
      var requests = 0, bootstraps = 0;
      final online = LunoOnlineService.forTesting(
        bootstrap: () async {
          bootstraps++;
        },
        auth: auth,
        appCheck: () async => 'check',
        client: MockClient((request) async {
          requests++;
          entered.complete();
          return pending.future;
        }),
      );
      final telemetry = ProductTelemetry();
      addTearDown(() {
        telemetry.dispose();
        online.dispose();
        store.dispose();
      });
      await telemetry.bind(store: store, online: online);
      expect(requests, 0);
      expect(bootstraps, 0);
      expect(telemetry.hasCurrentBinding, isFalse);
      await online.start();
      final first = telemetry.bind(store: store, online: online);
      await entered.future;
      var secondCompleted = false;
      final second = telemetry.bind(store: store, online: online).then((_) {
        secondCompleted = true;
      });
      await Future<void>.delayed(Duration.zero);
      expect(secondCompleted, isFalse);
      expect(requests, 1);
      pending.complete(
        http.Response(jsonEncode({'ok': true, 'consent': off}), 200),
      );
      await first;
      await second;
      expect(telemetry.confirmed, isTrue);
      expect(telemetry.loadingConsent, isFalse);
      expect(requests, 1);
    },
  );

  test(
    'consent bind times out OFF and a late response cannot enable it',
    () async {
      final pending = Completer<Map<String, dynamic>>();
      final telemetry = ProductTelemetry(
        requestTimeout: const Duration(milliseconds: 5),
      );
      addTearDown(telemetry.dispose);
      await telemetry.bindOwner(
        uid: 'player_self',
        isCurrent: () => true,
        request: (_, _) => pending.future,
      );
      expect(telemetry.confirmed, isFalse);
      expect(telemetry.loadingConsent, isFalse);
      pending.complete({'ok': true, 'consent': enabled});
      await Future<void>.delayed(Duration.zero);
      telemetry.record(sample);
      expect(telemetry.queuedSamples, 0);
    },
  );

  Future<ProductTelemetry> bind({
    Object consent = enabled,
    ProductTelemetryRequest? request,
    bool Function()? isCurrent,
  }) async {
    final telemetry = ProductTelemetry(flushDelay: const Duration(days: 1));
    addTearDown(telemetry.dispose);
    await telemetry.bindOwner(
      uid: 'player_self',
      isCurrent: isCurrent ?? () => true,
      request:
          request ?? (path, body) async => {'ok': true, 'consent': consent},
    );
    return telemetry;
  }

  test(
    'default and unconfirmed consent never transmit or buffer private history',
    () async {
      var delivered = 0;
      final telemetry = await bind(
        consent: off,
        request: (path, body) async {
          if (path == '/submitProductTelemetry') delivered++;
          return {'ok': true, 'consent': off};
        },
      );
      telemetry.record(sample);
      await telemetry.flush();
      expect(telemetry.queuedSamples, 0);
      expect(delivered, 0);
      expect(telemetry.consent.analytics, isFalse);
    },
  );

  test(
    'retry replaces failed consent state and still requires server confirmation',
    () async {
      var attempts = 0;
      final telemetry = await bind(
        request: (_, _) async {
          if (++attempts == 1) throw TimeoutException('offline');
          return {'ok': true, 'consent': off};
        },
      );
      expect(telemetry.failed, isTrue);
      await telemetry.retryConsent();
      expect(attempts, 2);
      expect(telemetry.confirmed, isTrue);
      expect(telemetry.failed, isFalse);
      telemetry.record(sample);
      expect(telemetry.queuedSamples, 0);
    },
  );

  test(
    'explicit consent delivers bounded typed samples with no identity or card id',
    () async {
      final sent = <Map<String, dynamic>>[];
      final telemetry = await bind(
        request: (path, body) async {
          if (path == '/submitProductTelemetry') {
            sent.add(body);
            return {
              'ok': true,
              'accepted': (body['samples'] as List).length,
              'idempotent': false,
            };
          }
          return {'ok': true, 'consent': enabled};
        },
      );
      telemetry.record(sample);
      await telemetry.flush();
      expect(sent, hasLength(1));
      expect(sent.single.keys.toSet(), {
        'version',
        'kind',
        'consentRevision',
        'deliveryId',
        'samples',
      });
      expect((sent.single['samples'] as List).single, {
        'event': 'card_played',
        'elapsedMs': 15000,
        'mode': 'ai',
      });
      for (final private in [
        'uid',
        'player_self',
        'token',
        'FEN',
        'deck',
        'cardId',
        'username',
      ]) {
        expect(jsonEncode(sent), isNot(contains(private)));
      }
      expect(telemetry.queuedSamples, 0);
    },
  );

  test(
    'retry reuses delivery ID/payload; successful idempotent receipt consumes once',
    () async {
      final sent = <String>[];
      final telemetry = await bind(
        request: (path, body) async {
          if (path == '/submitProductTelemetry') {
            sent.add(jsonEncode(body));
            if (sent.length == 1) throw TimeoutException('secret endpoint');
            return {'ok': true, 'accepted': 1, 'idempotent': true};
          }
          return {'ok': true, 'consent': enabled};
        },
      );
      telemetry.record(sample);
      await telemetry.flush();
      await telemetry.flush();
      expect(sent, hasLength(2));
      expect(sent[0], sent[1]);
      expect(telemetry.queuedSamples, 0);
    },
  );

  test(
    'three failed deliveries drop optional metrics without gameplay exception',
    () async {
      var attempts = 0;
      final telemetry = await bind(
        request: (path, body) async {
          if (path == '/submitProductTelemetry') {
            attempts++;
            throw StateError('private');
          }
          return {'ok': true, 'consent': enabled};
        },
      );
      telemetry.record(sample);
      for (var i = 0; i < 4; i++) {
        await telemetry.flush();
      }
      expect(attempts, 3);
      expect(telemetry.queuedSamples, 0);
    },
  );

  test('queue is capped at 64 and each delivery is capped at 16', () async {
    final sizes = <int>[];
    final telemetry = await bind(
      request: (path, body) async {
        if (path == '/submitProductTelemetry') {
          sizes.add((body['samples'] as List).length);
          return {'ok': true, 'accepted': sizes.last, 'idempotent': false};
        }
        return {'ok': true, 'consent': enabled};
      },
    );
    for (var i = 0; i < 1000; i++) {
      telemetry.record(sample);
    }
    expect(telemetry.queuedSamples, 64);
    for (var i = 0; i < 4; i++) {
      await telemetry.flush();
    }
    expect(sizes, [16, 16, 16, 16]);
    expect(telemetry.queuedSamples, 0);
  });

  test(
    'in-flight batch cannot be shifted by queue overflow or double flush',
    () async {
      final pending = Completer<Map<String, dynamic>>();
      var deliveries = 0;
      final telemetry = await bind(
        request: (path, body) async {
          if (path == '/submitProductTelemetry') {
            deliveries++;
            return pending.future;
          }
          return {'ok': true, 'consent': enabled};
        },
      );
      for (var i = 0; i < 64; i++) {
        telemetry.record(sample);
      }
      final flush = telemetry.flush();
      await telemetry.flush();
      for (var i = 0; i < 100; i++) {
        telemetry.record(sample);
      }
      expect(telemetry.queuedSamples, 64);
      expect(deliveries, 1);
      pending.complete({'ok': true, 'accepted': 16, 'idempotent': false});
      await flush;
      expect(telemetry.queuedSamples, 48);
    },
  );

  test('departed account rejects late consent and late diagnostics', () async {
    var current = true;
    final pending = Completer<Map<String, dynamic>>();
    final telemetry = ProductTelemetry(flushDelay: const Duration(days: 1));
    addTearDown(telemetry.dispose);
    final binding = telemetry.bindOwner(
      uid: 'player_self',
      isCurrent: () => current,
      request: (_, _) => pending.future,
    );
    await Future<void>.delayed(Duration.zero);
    current = false;
    pending.complete({'ok': true, 'consent': enabled});
    await binding;
    telemetry.record(sample);
    expect(telemetry.confirmed, isFalse);
    expect(telemetry.queuedSamples, 0);
  });

  test(
    'account switch clears pending queue and cannot redirect old delivery',
    () async {
      final pending = Completer<Map<String, dynamic>>();
      var oldDeliveries = 0, newDeliveries = 0;
      final telemetry = await bind(
        request: (path, body) async {
          if (path == '/submitProductTelemetry') {
            oldDeliveries++;
            return pending.future;
          }
          return {'ok': true, 'consent': enabled};
        },
      );
      telemetry.record(sample);
      final flushing = telemetry.flush();
      telemetry.unbind();
      await telemetry.bindOwner(
        uid: 'player_other',
        isCurrent: () => true,
        request: (path, body) async {
          if (path == '/submitProductTelemetry') newDeliveries++;
          return {'ok': true, 'consent': off};
        },
      );
      pending.complete({'ok': true, 'accepted': 1, 'idempotent': false});
      await flushing;
      expect(oldDeliveries, 1);
      expect(newDeliveries, 0);
      expect(telemetry.queuedSamples, 0);
      expect(telemetry.consent.analytics, isFalse);
    },
  );

  test(
    'departed delivery releases current owner queue without another tap',
    () async {
      final pending = Completer<Map<String, dynamic>>();
      final delivered = Completer<void>();
      final telemetry = ProductTelemetry(
        flushDelay: const Duration(milliseconds: 5),
      );
      addTearDown(telemetry.dispose);
      await telemetry.bindOwner(
        uid: 'player_old',
        isCurrent: () => true,
        request:
            (path, _) async =>
                path == '/submitProductTelemetry'
                    ? pending.future
                    : {'ok': true, 'consent': enabled},
      );
      telemetry.record(sample);
      final oldFlush = telemetry.flush();
      telemetry.unbind();
      await telemetry.bindOwner(
        uid: 'player_new',
        isCurrent: () => true,
        request: (path, _) async {
          if (path == '/submitProductTelemetry') {
            delivered.complete();
            return {'ok': true, 'accepted': 1, 'idempotent': false};
          }
          return {'ok': true, 'consent': enabled};
        },
      );
      telemetry.record(sample);
      await telemetry.flush();
      expect(delivered.isCompleted, isFalse);
      pending.complete({'ok': true, 'accepted': 1, 'idempotent': false});
      await oldFlush;
      await delivered.future.timeout(const Duration(seconds: 1));
      await Future<void>.delayed(Duration.zero);
      expect(telemetry.queuedSamples, 0);
      expect(telemetry.consent.analytics, isTrue);
    },
  );

  test('consent decline sends nothing; damaged response remains OFF', () async {
    final telemetry = await bind(
      consent: {
        'version': 1,
        'revision': '1',
        'analytics': true,
        'diagnostics': true,
      },
    );
    telemetry.record(sample);
    expect(telemetry.failed, isTrue);
    expect(telemetry.confirmed, isFalse);
    expect(telemetry.queuedSamples, 0);
  });

  test(
    'failed revocation persists pending denial and restart cannot silently opt in',
    () async {
      final telemetry = await bind(
        request: (path, body) async {
          if (path == '/setProductTelemetryConsent') {
            throw TimeoutException('offline');
          }
          return {'ok': true, 'consent': enabled};
        },
      );
      telemetry.record(sample);
      expect(
        await telemetry.setConsent(analytics: false, diagnostics: false),
        isFalse,
      );
      expect(telemetry.queuedSamples, 0);
      expect(telemetry.consent.analytics, isFalse);
      telemetry.unbind();
      final restored = await bind(
        request: (path, body) async {
          if (path == '/setProductTelemetryConsent') {
            throw TimeoutException('still offline');
          }
          return {'ok': true, 'consent': enabled};
        },
      );
      restored.record(sample);
      expect(restored.consent.analytics, isFalse);
      expect(restored.consent.diagnostics, isFalse);
      expect(restored.queuedSamples, 0);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(productDenialStorageKey('player_self')),
        isNotNull,
      );
    },
  );

  test(
    'pending denial is scoped to one UID and confirmed retry clears it',
    () async {
      SharedPreferences.setMockInitialValues({
        productDenialStorageKey('player_self'): jsonEncode({
          'version': 1,
          'uid': 'player_self',
          'analytics': true,
          'diagnostics': false,
        }),
      });
      final changes = <Map<String, dynamic>>[];
      final telemetry = await bind(
        request: (path, body) async {
          if (path == '/setProductTelemetryConsent') {
            changes.add(body);
            return {
              'ok': true,
              'consent': {...enabled, 'revision': 2, 'analytics': false},
            };
          }
          return {'ok': true, 'consent': enabled};
        },
      );
      expect(changes.single['analytics'], isFalse);
      expect(telemetry.consent.diagnostics, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(productDenialStorageKey('player_self')), isNull);
      expect(prefs.getString(productConsentStorageKey('player_other')), isNull);
    },
  );

  test(
    'diagnostic input has a closed schema, not arbitrary user strings',
    () async {
      final telemetry = await bind();
      telemetry.recordDiagnostic({
        'source': 'framework',
        'category': 'unknown',
        'component': 'unknown',
        'fingerprint': 'a' * 16,
        'message': 'private',
      });
      telemetry.recordDiagnostic({
        'source': 'private',
        'category': 'unknown',
        'component': 'unknown',
        'fingerprint': 'a' * 16,
      });
      expect(telemetry.queuedSamples, 0);
    },
  );

  test(
    'framework and async reporters deduplicate the same error without raw text',
    () {
      final reports = <Map<String, Object>>[],
          error = StateError('UID/private_token/DM_content');
      final reporter = ProductCrashReporter(sink: reports.add);
      final stack = StackTrace.fromString(
        '#0 private (package:luno_chess/screens/battle_v1_screen.dart:100:4)\nhttps://private.example/token=secret\nprivate DM',
      );
      reporter.report(error, stack, source: ProductErrorSource.framework);
      reporter.report(error, stack, source: ProductErrorSource.asyncError);
      expect(reports, hasLength(1));
      expect(reports.single.keys.toSet(), {
        'source',
        'category',
        'component',
        'fingerprint',
      });
      expect(reports.single['component'], 'battle');
      expect(reports.single['category'], 'state');
      for (final private in [
        'UID',
        'token',
        'DM',
        'example',
        'private',
        'battle_v1_screen.dart',
      ]) {
        expect(jsonEncode(reports), isNot(contains(private)));
      }
    },
  );

  test('different raw secret text cannot affect a sanitized fingerprint', () {
    final reports = <Map<String, Object>>[];
    var clock = DateTime.utc(2026, 10, 9);
    final reporter = ProductCrashReporter(
      sink: reports.add,
      clock: () => clock,
    );
    reporter.report(
      StateError('secret A'),
      StackTrace.fromString('package:luno_chess/app.dart:20:4) privateA'),
      source: ProductErrorSource.startup,
    );
    clock = clock.add(const Duration(seconds: 11));
    reporter.report(
      StateError('secret B'),
      StackTrace.fromString('package:luno_chess/app.dart:20:4) privateB'),
      source: ProductErrorSource.startup,
    );
    expect(reports, hasLength(2));
    expect(reports[0]['fingerprint'], reports[1]['fingerprint']);
  });

  for (final entry
      in {
        'battle_v1/local_session.dart': 'battle',
        'battle_v1/authoritative.dart': 'battle',
        'battle_v1/core.dart': 'battle',
        'battle_v1/introduction.dart': 'battle',
        'battle_v1/online.dart': 'network',
        'navigation/luno_route.dart': 'navigation',
        'navigation/online_match_recovery.dart': 'navigation',
      }.entries) {
    test(
      'diagnostics classify actual source ${entry.key} without sending it',
      () {
        final reports = <Map<String, Object>>[];
        ProductCrashReporter(sink: reports.add).report(
          StateError('private'),
          StackTrace.fromString('package:luno_chess/${entry.key}:20:4)'),
          source: ProductErrorSource.framework,
        );
        expect(reports.single['component'], entry.value);
        expect(jsonEncode(reports), isNot(contains(entry.key)));
        expect(jsonEncode(reports), isNot(contains('private')));
      },
    );
  }

  test('collector failure never escapes or causes duplicate reporting', () {
    var calls = 0;
    final reporter = ProductCrashReporter(
      sink: (_) {
        calls++;
        throw StateError('collector');
      },
    );
    final error = FormatException('private');
    expect(
      () => reporter.report(error, null, source: ProductErrorSource.asyncError),
      returnsNormally,
    );
    reporter.report(error, null, source: ProductErrorSource.framework);
    expect(calls, 1);
  });
}
