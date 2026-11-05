import 'dart:async';
import 'dart:collection';

import 'package:http/http.dart' as http;

import 'product_telemetry.dart';

enum ProductErrorSource { framework, asyncError, navigation, startup }

/// Diagnostics intentionally contain no exception message or raw stack. Only
/// fixed categories and locations in explicitly known application files survive.
class ProductCrashReporter {
  ProductCrashReporter({
    void Function(Map<String, Object>)? sink,
    DateTime Function()? clock,
  }) : _sink = sink ?? ProductTelemetry.instance.recordDiagnostic,
       _clock = clock ?? DateTime.now;
  static final instance = ProductCrashReporter();
  final void Function(Map<String, Object>) _sink;
  final DateTime Function() _clock;
  final _identities = LinkedHashMap<Object, DateTime>.identity();
  final _fingerprints = <String, DateTime>{};

  static const _files = {
    'screens/battle_v1_screen.dart': 'battle',
    'battle_v1/local_session.dart': 'battle',
    'battle_v1/authoritative.dart': 'battle',
    'battle_v1/core.dart': 'battle',
    'battle_v1/introduction.dart': 'battle',
    'battle_v1/online.dart': 'network',
    'main.dart': 'startup',
    'app.dart': 'startup',
    'navigation/luno_route.dart': 'navigation',
    'navigation/online_match_recovery.dart': 'navigation',
    'navigation/luno_account_scope.dart': 'navigation',
    'services/luno_online_service.dart': 'network',
    'models/game_store.dart': 'store',
  };

  void report(
    Object error,
    StackTrace? stack, {
    required ProductErrorSource source,
  }) {
    try {
      final now = _clock(), cutoff = now.subtract(const Duration(seconds: 10));
      _identities.removeWhere((_, at) => at.isBefore(cutoff));
      _fingerprints.removeWhere((_, at) => at.isBefore(cutoff));
      if (_identities.containsKey(error)) return;
      final category =
          error is AssertionError
              ? 'assertion'
              : error is RangeError
              ? 'range'
              : error is StateError
              ? 'state'
              : error is FormatException
              ? 'format'
              : error is TimeoutException
              ? 'timeout'
              : error is http.ClientException
              ? 'network'
              : 'unknown';
      var component = 'unknown';
      final frames = <String>[];
      final text = stack?.toString() ?? '';
      for (final entry in _files.entries) {
        final match = RegExp(
          'package:luno_chess/${RegExp.escape(entry.key)}:([0-9]{1,6}):([0-9]{1,5})(?:[)\\s]|\$)',
        ).firstMatch(text);
        if (match == null) continue;
        if (component == 'unknown') component = entry.value;
        frames.add('${entry.key}:${match[1]}:${match[2]}');
      }
      final signature = '$category|${frames.join('|')}';
      final fingerprint = _fingerprint(signature);
      if (frames.isNotEmpty && _fingerprints.containsKey(fingerprint)) return;
      if (_identities.length == 64) _identities.remove(_identities.keys.first);
      _identities[error] = now;
      if (_fingerprints.length == 64) {
        _fingerprints.remove(_fingerprints.keys.first);
      }
      if (frames.isNotEmpty) _fingerprints[fingerprint] = now;
      _sink({
        'source':
            source == ProductErrorSource.asyncError ? 'async' : source.name,
        'category': category,
        'component': component,
        'fingerprint': fingerprint,
      });
    } catch (_) {
      // The crash collector itself must not create another uncaught error.
    }
  }

  String _fingerprint(String safeValue) {
    var first = 0x811c9dc5, second = 0x9e3779b9;
    for (final value in safeValue.codeUnits) {
      first = ((first ^ value) * 0x01000193) & 0xffffffff;
      second = ((second ^ value) * 0x85ebca6b) & 0xffffffff;
    }
    return first.toRadixString(16).padLeft(8, '0') +
        second.toRadixString(16).padLeft(8, '0');
  }
}
