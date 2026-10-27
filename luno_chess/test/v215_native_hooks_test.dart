import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luno_chess/services/legal_link_service.dart';
import 'package:luno_chess/services/legal_urls.dart';
import 'package:luno_chess/services/product_crash_reporter.dart';
import 'package:luno_chess/services/product_error_handlers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('release framework logging cannot expose raw details or collector', () {
    final reports = <Map<String, Object>>[];
    final logged = <FlutterErrorDetails>[];
    final error = StateError('private auth_token DM name FEN');
    var collected = false;
    final details = FlutterErrorDetails(
      exception: error,
      stack: StackTrace.fromString('PRIVATE_STACK'),
      context: ErrorDescription('PRIVATE_CONTEXT'),
      informationCollector: () {
        collected = true;
        return [ErrorDescription('PRIVATE_INFO')];
      },
    );
    ProductErrorHandlers(
      release: true,
      reporter: ProductCrashReporter(sink: reports.add),
      frameworkHandler: logged.add,
    ).framework(details);
    expect(reports, hasLength(1));
    expect(logged, hasLength(1));
    expect(logged.single.stack, isNull);
    expect(logged.single.context, isNull);
    expect(logged.single.informationCollector, isNull);
    expect(logged.single.exception.toString(), isNot(contains('private')));
    expect(collected, isFalse);
  });

  for (final handled in [false, true]) {
    test('release async prior handler $handled has safe payload', () {
      final reports = <Map<String, Object>>[];
      final logged = <FlutterErrorDetails>[];
      Object? received;
      StackTrace? receivedStack;
      final handlers = ProductErrorHandlers(
        release: true,
        reporter: ProductCrashReporter(sink: reports.add),
        asyncHandler: (error, stack) {
          received = error;
          receivedStack = stack;
          return handled;
        },
        presentError: logged.add,
      );
      expect(
        handlers.asynchronous(
          StateError('private auth_token'),
          StackTrace.fromString('PRIVATE_STACK'),
        ),
        isTrue,
      );
      expect(reports, hasLength(1));
      expect(received.toString(), isNot(contains('private')));
      expect(receivedStack.toString(), isEmpty);
      expect(logged, hasLength(handled ? 0 : 1));
    });
  }

  test('debug handlers retain original details and unhandled return', () {
    final error = StateError('debug');
    final stack = StackTrace.fromString('debug stack');
    final details = FlutterErrorDetails(exception: error, stack: stack);
    FlutterErrorDetails? received;
    final handlers = ProductErrorHandlers(
      release: false,
      reporter: ProductCrashReporter(sink: (_) {}),
      frameworkHandler: (value) => received = value,
      asyncHandler: (value, trace) {
        expect(identical(value, error), isTrue);
        expect(identical(trace, stack), isTrue);
        return false;
      },
    );
    handlers.framework(details);
    expect(identical(received, details), isTrue);
    expect(handlers.asynchronous(error, stack), isFalse);
  });

  test('native legal channel only receives exact allowlisted URLs', () async {
    const channel = MethodChannel('com.luno.chess/legal');
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final service = LegalLinkService();
    expect(await service.open(ugcPrivacyUrl), isTrue);
    expect(await service.open(ugcTermsUrl), isTrue);
    for (final url in [
      'http://luno-legal-site.vercel.app/',
      'https://luno-legal-site.vercel.app/?token=private',
      'https://luno-legal-site.vercel.app.evil.example/',
      'file:///private',
    ]) {
      expect(await service.open(url), isFalse);
    }
    expect(calls, hasLength(2));
    expect(calls.every((call) => call.method == 'openLegalUrl'), isTrue);
  });

  test('Android legal bridge and shell recovery integration stay wired', () {
    final activity =
        File(
          'android/app/src/main/kotlin/com/luno/chess/MainActivity.kt',
        ).readAsStringSync();
    expect(activity, contains('com.luno.chess/legal'));
    expect(activity, contains('openLegalUrl'));
    expect(activity, contains(ugcPrivacyUrl));
    expect(activity, contains(ugcTermsUrl));
    expect(activity, contains('Intent.ACTION_VIEW'));
    expect(activity, contains('result.success(false)'));
    expect(activity, contains('setMethodCallHandler(null)'));
    final app = File('lib/app.dart').readAsStringSync();
    expect(app, contains('_measurementOwner == owner &&'));
    expect(app, contains('ProductTelemetry.instance.hasCurrentBinding'));
  });
}
