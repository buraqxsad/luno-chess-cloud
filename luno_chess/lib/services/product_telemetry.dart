import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/game_store.dart';
import 'first_session_telemetry.dart';
import 'luno_online_service.dart';

typedef ProductTelemetryRequest =
    Future<Map<String, dynamic>> Function(
      String path,
      Map<String, dynamic> body,
    );

class ProductConsent {
  const ProductConsent({
    this.revision = 0,
    this.analytics = false,
    this.diagnostics = false,
  });
  final int revision;
  final bool analytics;
  final bool diagnostics;

  static ProductConsent parse(Object? value) {
    if (value is! Map ||
        value['version'] != 1 ||
        value['revision'] is! int ||
        (value['revision'] as int) < 0 ||
        (value['revision'] as int) > 1000000000 ||
        value['analytics'] is! bool ||
        value['diagnostics'] is! bool ||
        value['revision'] == 0 &&
            (value['analytics'] == true || value['diagnostics'] == true)) {
      throw const FormatException('Invalid measurement consent');
    }
    return ProductConsent(
      revision: value['revision'] as int,
      analytics: value['analytics'] as bool,
      diagnostics: value['diagnostics'] as bool,
    );
  }

  Map<String, Object> toJson() => {
    'version': 1,
    'revision': revision,
    'analytics': analytics,
    'diagnostics': diagnostics,
  };
}

String productConsentStorageKey(String uid) =>
    'luno.product-consent.v1.${Uri.encodeComponent(uid)}';
String productDenialStorageKey(String uid) =>
    'luno.product-denial.v1.${Uri.encodeComponent(uid)}';

class _Delivery {
  _Delivery(this.body, this.count);
  final Map<String, dynamic> body;
  final int count;
  int attempts = 0;
}

/// Optional measurement never gates play. Pre-consent and departed-account
/// samples are not replayed; no raw exception, user text or card data is queued.
class ProductTelemetry extends ChangeNotifier {
  ProductTelemetry({
    Duration flushDelay = const Duration(seconds: 8),
    Duration requestTimeout = const Duration(seconds: 12),
    Random? random,
  }) : _flushDelay = flushDelay,
       _requestTimeout = requestTimeout,
       _random = random ?? Random.secure();
  static final instance = ProductTelemetry();
  final Duration _flushDelay;
  final Duration _requestTimeout;
  final Random _random;
  final _queue = Queue<(String, Map<String, Object>)>();
  ProductConsent _consent = const ProductConsent();
  ProductConsent get consent => _consent;
  bool _confirmed = false;
  bool get confirmed => _confirmed;
  bool _saving = false;
  bool get saving => _saving;
  bool _failed = false;
  bool _loadingConsent = false;
  bool get loadingConsent => _loadingConsent;
  Future<void>? _bindingFuture;
  bool _deniedAnalytics = false, _deniedDiagnostics = false;
  bool get failed => _failed;
  bool get hasCurrentBinding => _current;
  int _epoch = 0;
  int? _inFlight;
  String? _uid;
  bool Function()? _ownerCurrent;
  ProductTelemetryRequest? _request;
  FirstSessionTelemetry? _funnel;
  Timer? _timer;
  _Delivery? _delivery;
  GameStore? _store;
  LunoOnlineService? _online;
  bool get _current => _uid != null && (_ownerCurrent?.call() ?? false);
  int get queuedSamples => _queue.length;

  Future<void> bind({
    required GameStore store,
    required LunoOnlineService online,
  }) async {
    final uid = online.user?.uid;
    if (!online.ready ||
        online.authTransitioning ||
        uid == null ||
        store.accountUid != uid ||
        online.accountFailure != null) {
      unbind();
      return;
    }
    final revision = store.accountBindingRevision,
        onlineRevision = online.accountRevision;
    if (identical(_store, store) &&
        identical(_online, online) &&
        _uid == uid &&
        _current &&
        (_confirmed || _loadingConsent)) {
      await _bindingFuture;
      return;
    }
    unbind();
    _store = store;
    _online = online;
    store.addListener(_checkOwner);
    online.addListener(_checkOwner);
    final binding = bindOwner(
      uid: uid,
      isCurrent:
          () =>
              store.accountUid == uid &&
              store.accountBindingRevision == revision &&
              online.user?.uid == uid &&
              online.accountRevision == onlineRevision &&
              online.ready &&
              !online.authTransitioning &&
              online.accountFailure == null,
      request: (path, body) => online.api(path, body),
      funnel: FirstSessionTelemetry.forStore(store),
    );
    _bindingFuture = binding;
    await binding;
  }

  @visibleForTesting
  Future<void> bindOwner({
    required String uid,
    required bool Function() isCurrent,
    required ProductTelemetryRequest request,
    FirstSessionTelemetry? funnel,
  }) {
    final binding = _loadOwnerConsent(
      uid: uid,
      isCurrent: isCurrent,
      request: request,
      funnel: funnel,
    );
    _bindingFuture = binding;
    return binding;
  }

  Future<void> _loadOwnerConsent({
    required String uid,
    required bool Function() isCurrent,
    required ProductTelemetryRequest request,
    FirstSessionTelemetry? funnel,
  }) async {
    _uid = uid;
    _ownerCurrent = isCurrent;
    _request = request;
    _funnel = funnel;
    final epoch = ++_epoch;
    _queue.clear();
    _delivery = null;
    _confirmed = false;
    _loadingConsent = true;
    _consent = const ProductConsent();
    _configureFunnel();
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      if (epoch != _epoch || !_current) return;
      _deniedAnalytics = false;
      _deniedDiagnostics = false;
      final raw = prefs.getString(productDenialStorageKey(uid));
      if (raw != null) {
        try {
          final denial = jsonDecode(raw);
          if (denial is! Map ||
              denial['uid'] != uid ||
              denial['version'] != 1 ||
              denial['analytics'] is! bool ||
              denial['diagnostics'] is! bool) {
            throw const FormatException('Invalid pending privacy choice');
          }
          _deniedAnalytics = denial['analytics'] as bool;
          _deniedDiagnostics = denial['diagnostics'] as bool;
        } catch (_) {
          _deniedAnalytics = true;
          _deniedDiagnostics = true;
        }
      }
      final result = await request(
        '/getProductTelemetryConsent',
        const {},
      ).timeout(_requestTimeout);
      if (epoch != _epoch || !_current) return;
      if (result['ok'] != true) {
        throw const FormatException('Unconfirmed measurement consent');
      }
      _consent = ProductConsent.parse(result['consent']);
      _confirmed = true;
      _failed = false;
      if (_deniedAnalytics || _deniedDiagnostics) {
        final desiredAnalytics = _consent.analytics && !_deniedAnalytics;
        final desiredDiagnostics = _consent.diagnostics && !_deniedDiagnostics;
        if (_consent.analytics != desiredAnalytics ||
            _consent.diagnostics != desiredDiagnostics) {
          final oldRevision = _consent.revision;
          _consent = ProductConsent(
            revision: oldRevision,
            analytics: desiredAnalytics,
            diagnostics: desiredDiagnostics,
          );
          final repaired = await request('/setProductTelemetryConsent', {
            'version': 1,
            'expectedRevision': oldRevision,
            'analytics': desiredAnalytics,
            'diagnostics': desiredDiagnostics,
          }).timeout(_requestTimeout);
          if (epoch != _epoch || !_current) return;
          final confirmed = ProductConsent.parse(repaired['consent']);
          if (repaired['ok'] != true ||
              confirmed.analytics != desiredAnalytics ||
              confirmed.diagnostics != desiredDiagnostics) {
            throw const FormatException('Unconfirmed privacy revocation');
          }
          _consent = confirmed;
        }
        _deniedAnalytics = false;
        _deniedDiagnostics = false;
        await prefs.remove(productDenialStorageKey(uid));
      }
      await _persist(epoch);
      if (epoch != _epoch || !_current) return;
      _configureFunnel();
      notifyListeners();
    } catch (_) {
      if (epoch == _epoch && _current) {
        _confirmed = false;
        _failed = true;
        notifyListeners();
      }
    } finally {
      if (epoch == _epoch && _current) {
        _loadingConsent = false;
        notifyListeners();
      }
    }
  }

  Future<void> retryConsent() async {
    final uid = _uid, current = _ownerCurrent, request = _request;
    if (uid == null ||
        current == null ||
        request == null ||
        !_current ||
        _saving ||
        _loadingConsent) {
      return;
    }
    await bindOwner(
      uid: uid,
      isCurrent: current,
      request: request,
      funnel: _funnel,
    );
  }

  void _checkOwner() {
    if (!_current) unbind();
  }

  void _configureFunnel() => _funnel?.configure(
    sink: record,
    transmissionAllowed: _confirmed && _consent.analytics && _current,
  );

  Future<void> _persist(int epoch) async {
    final uid = _uid;
    if (uid == null) return;
    final prefs = await SharedPreferences.getInstance();
    if (epoch != _epoch || !_current) return;
    if (!await prefs.setString(
      productConsentStorageKey(uid),
      jsonEncode({'uid': uid, ..._consent.toJson()}),
    )) {
      throw const FormatException('Measurement preference was not saved');
    }
  }

  Future<bool> setConsent({
    required bool analytics,
    required bool diagnostics,
  }) async {
    final request = _request;
    if (!_current || request == null || _saving || !_confirmed) return false;
    final epoch = _epoch, previous = _consent;
    _saving = true;
    _failed = false;
    // Revocation stops queued/in-flight follow-up immediately, before network.
    _consent = ProductConsent(
      revision: previous.revision,
      analytics: previous.analytics && analytics,
      diagnostics: previous.diagnostics && diagnostics,
    );
    _deniedAnalytics = _deniedAnalytics || previous.analytics && !analytics;
    _deniedDiagnostics =
        _deniedDiagnostics || previous.diagnostics && !diagnostics;
    _queue.clear();
    _delivery = null;
    _timer?.cancel();
    _configureFunnel();
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      if (epoch != _epoch || !_current) return false;
      if (_deniedAnalytics || _deniedDiagnostics) {
        final stored = await prefs.setString(
          productDenialStorageKey(_uid!),
          jsonEncode({
            'version': 1,
            'uid': _uid,
            'analytics': _deniedAnalytics,
            'diagnostics': _deniedDiagnostics,
          }),
        );
        if (epoch != _epoch || !_current) return false;
        if (!stored) {
          throw const FormatException('Privacy revocation was not saved');
        }
      }
      final result = await request('/setProductTelemetryConsent', {
        'version': 1,
        'expectedRevision': previous.revision,
        'analytics': analytics,
        'diagnostics': diagnostics,
      }).timeout(_requestTimeout);
      if (epoch != _epoch || !_current) return false;
      final consent = ProductConsent.parse(result['consent']);
      if (result['ok'] != true ||
          consent.revision < 1 ||
          consent.analytics != analytics ||
          consent.diagnostics != diagnostics) {
        throw const FormatException('Unconfirmed measurement choice');
      }
      _consent = consent;
      await _persist(epoch);
      if (epoch != _epoch || !_current) return false;
      _deniedAnalytics = false;
      _deniedDiagnostics = false;
      await prefs.remove(productDenialStorageKey(_uid!));
      if (epoch != _epoch || !_current) return false;
      _configureFunnel();
      return true;
    } catch (_) {
      if (epoch == _epoch && _current) _failed = true;
      return false;
    } finally {
      if (epoch == _epoch && _current) {
        _saving = false;
        notifyListeners();
      }
    }
  }

  void record(FirstSessionSample sample) =>
      _enqueue('analytics', sample.toJson());
  void recordDiagnostic(Map<String, Object> sample) {
    const allowed = {'source', 'category', 'component', 'fingerprint'};
    if (sample.keys.toSet().difference(allowed).isNotEmpty ||
        sample.length != 4 ||
        !const {
          'framework',
          'async',
          'navigation',
          'startup',
        }.contains(sample['source']) ||
        !const {
          'assertion',
          'state',
          'format',
          'range',
          'timeout',
          'network',
          'unknown',
        }.contains(sample['category']) ||
        !const {
          'battle',
          'startup',
          'navigation',
          'network',
          'store',
          'unknown',
        }.contains(sample['component']) ||
        sample['fingerprint'] is! String ||
        !RegExp(r'^[a-f0-9]{16}$').hasMatch(sample['fingerprint'] as String)) {
      return;
    }
    _enqueue('diagnostics', sample);
  }

  void _enqueue(String kind, Map<String, Object> sample) {
    if (!_current ||
        !_confirmed ||
        _saving ||
        !(kind == 'analytics'
            ? _consent.analytics && !_deniedAnalytics
            : _consent.diagnostics && !_deniedDiagnostics)) {
      return;
    }
    if (_queue.length == 64) {
      if (_delivery != null) return;
      _queue.removeFirst();
    }
    _queue.add((kind, Map.unmodifiable(sample)));
    _schedule();
  }

  void _schedule() {
    if (_timer?.isActive == true || !_current) return;
    _timer = Timer(_flushDelay, () => unawaited(flush()));
  }

  String _id() =>
      List.generate(
        16,
        (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();

  Future<void> flush() async {
    final request = _request;
    if (!_current ||
        !_confirmed ||
        _saving ||
        request == null ||
        _inFlight != null ||
        _queue.isEmpty) {
      return;
    }
    final epoch = _epoch;
    _timer?.cancel();
    _inFlight = epoch;
    final kind = _queue.first.$1;
    final samples =
        _queue
            .takeWhile((sample) => sample.$1 == kind)
            .take(16)
            .map((s) => s.$2)
            .toList();
    final delivery =
        _delivery ??= _Delivery({
          'version': 1,
          'kind': kind,
          'consentRevision': _consent.revision,
          'deliveryId': _id(),
          'samples': samples,
        }, samples.length);
    try {
      delivery.attempts++;
      final result = await request(
        '/submitProductTelemetry',
        delivery.body,
      ).timeout(_requestTimeout);
      if (epoch != _epoch || !_current || !identical(_delivery, delivery)) {
        return;
      }
      if (result['ok'] != true ||
          result['accepted'] != delivery.count ||
          result['idempotent'] is! bool) {
        throw const FormatException('Unconfirmed measurement delivery');
      }
      for (var i = 0; i < delivery.count && _queue.isNotEmpty; i++) {
        _queue.removeFirst();
      }
      _delivery = null;
    } catch (_) {
      if (epoch == _epoch &&
          _current &&
          identical(_delivery, delivery) &&
          delivery.attempts >= 3) {
        for (var i = 0; i < delivery.count && _queue.isNotEmpty; i++) {
          _queue.removeFirst();
        }
        _delivery = null;
      }
    } finally {
      if (_inFlight == epoch) _inFlight = null;
      // A departed account's transport may finish after a new owner queued
      // events. Release the single flight and resume only the current queue.
      if (_current && _confirmed && _queue.isNotEmpty && !_saving) {
        _schedule();
      }
    }
  }

  void unbind() {
    ++_epoch;
    _timer?.cancel();
    _timer = null;
    _store?.removeListener(_checkOwner);
    _online?.removeListener(_checkOwner);
    _store = null;
    _online = null;
    _funnel?.configure();
    _funnel = null;
    _queue.clear();
    _delivery = null;
    _uid = null;
    _ownerCurrent = null;
    _request = null;
    _consent = const ProductConsent();
    _confirmed = false;
    _loadingConsent = false;
    _bindingFuture = null;
    _saving = false;
    _failed = false;
    _deniedAnalytics = false;
    _deniedDiagnostics = false;
    notifyListeners();
  }

  @override
  void dispose() {
    unbind();
    super.dispose();
  }
}
