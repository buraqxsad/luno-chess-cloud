import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'luno_billing_models.dart';
import 'luno_google_play_billing_adapter.dart';
import 'luno_online_billing_backend.dart';
import 'luno_online_service.dart';

export 'luno_billing_models.dart';

/// No GameStore writes, local grants, receipt persistence, logs or telemetry.
/// Call start after online.start; retain this service across screen navigation.
/// Apply snapshots only while isCurrent(snapshot.owner) is true.
class LunoBillingService extends ChangeNotifier {
  static final instance = LunoBillingService.googlePlay();
  LunoBillingService({
    required LunoPlayBillingPort play,
    required LunoBillingBackend backend,
    this.storeTimeout = const Duration(seconds: 20),
    this.requestTimeout = const Duration(seconds: 45),
  }) : _play = play,
       _backend = backend {
    _backend.addListener(_onBackendChanged);
  }

  factory LunoBillingService.googlePlay({LunoOnlineService? online}) =>
      LunoBillingService(
        play: LunoGooglePlayBillingAdapter(),
        backend: LunoOnlineBillingBackend(online ?? LunoOnlineService.instance),
      );

  final LunoPlayBillingPort _play;
  final LunoBillingBackend _backend;
  final Duration storeTimeout;
  final Duration requestTimeout;
  final _events = StreamController<LunoBillingEvent>.broadcast();
  final _snapshots = StreamController<LunoBillingSnapshot>.broadcast();
  final Map<String, LunoBillingProduct> _products = {};
  final Map<String, LunoBillingStatus> _productStatuses = {};
  final Map<String, _QueuedPurchase> _queue = {};
  final Set<String> _completed = {};
  final Map<String, String> _rejected = {};
  StreamSubscription<List<LunoPlayPurchase>>? _subscription;
  LunoBillingOwner? _owner;
  Future<void>? _initialization;
  Future<void>? _draining;
  Future<void>? _restoring;
  String? _launchProduct;
  Object? _launchOperation;
  bool _enabled = false;
  bool _disposed = false;
  bool _ownsMembership = false;
  bool _available = false;
  LunoBillingStatus _status = LunoBillingStatus.idle;
  String? _errorCode;
  Set<String> _missing = const {};
  LunoBillingSnapshot? _latestSnapshot;

  Stream<LunoBillingEvent> get events => _events.stream;
  Stream<LunoBillingSnapshot> get snapshots => _snapshots.stream;
  LunoBillingOwner? get owner => _owner;
  bool get available => _available;
  LunoBillingStatus get status => _status;
  String? get errorCode => _errorCode;
  Map<String, LunoBillingProduct> get products => Map.unmodifiable(_products);
  Map<String, LunoBillingStatus> get productStatuses =>
      Map.unmodifiable(_productStatuses);
  Set<String> get missingProductIds => Set.unmodifiable(_missing);
  int get queuedVerificationCount => _queue.length;
  LunoBillingSnapshot? get latestSnapshot =>
      _latestSnapshot != null && isCurrent(_latestSnapshot!.owner)
          ? _latestSnapshot
          : null;

  /// Identity also invalidates a prior stop/start session with the same UID.
  bool isCurrent(LunoBillingOwner owner) =>
      !_disposed &&
      _enabled &&
      identical(owner, _owner) &&
      owner.sameAccount(_backend.currentOwner);

  Future<void> start() {
    if (_disposed) throw const LunoBillingFailure('service-disposed');
    _enabled = true;
    if (_owner != null &&
        _initialization == null &&
        (_subscription == null || !_available)) {
      unawaited(_clearSession());
    }
    _onBackendChanged();
    if (_owner == null) {
      throw const LunoBillingFailure('auth-not-ready');
    }
    return _initialization ?? Future<void>.value();
  }

  void _onBackendChanged() {
    if (_disposed || !_enabled) return;
    final account = _backend.currentOwner;
    if (_owner != null && !_owner!.sameAccount(account)) {
      unawaited(_clearSession());
      _emit(LunoBillingStatus.idle);
    }
    if (_owner == null && account != null && _backend.readyForBilling) {
      // A fresh identity stamp cannot be reused by delayed UI callbacks.
      final owner = LunoBillingOwner(account.uid, account.accountRevision);
      _owner = owner;
      try {
        _subscription = _play.purchaseStream.listen(
          (batch) => _handleBatch(owner, batch),
          onError: (Object _, StackTrace _) {
            if (isCurrent(owner)) {
              _emit(LunoBillingStatus.error, code: 'purchase-stream-failed');
            }
          },
          onDone: () {
            if (isCurrent(owner)) {
              _subscription = null;
              _available = false;
              _emit(LunoBillingStatus.error, code: 'purchase-stream-closed');
            }
          },
        );
        _initialization = _initialize(owner);
      } catch (_) {
        _available = false;
        _emit(LunoBillingStatus.unavailable, code: 'store-unavailable');
      }
    }
  }

  Future<void> _initialize(LunoBillingOwner owner) async {
    _emit(LunoBillingStatus.loading);
    try {
      final available = await _play.isAvailable().timeout(storeTimeout);
      _guard(owner);
      _available = available;
      if (!available) {
        _emit(LunoBillingStatus.unavailable, code: 'store-unavailable');
        return;
      }
      await queryProducts();
      _guard(owner);
      await restore();
    } catch (error) {
      if (isCurrent(owner)) _report(_failure(error));
    } finally {
      if (isCurrent(owner)) _initialization = null;
    }
  }

  LunoBillingOwner _requireOwner() {
    final owner = _owner;
    if (owner == null || !isCurrent(owner)) {
      throw const LunoBillingFailure('auth-not-ready');
    }
    return owner;
  }

  void _guard(LunoBillingOwner owner) {
    if (!isCurrent(owner)) throw const LunoBillingFailure('session-changed');
  }

  Future<LunoBillingProductQuery> queryProducts() async {
    final owner = _requireOwner();
    try {
      final result = await _play
          .queryProducts(lunoBillingCatalog.keys.toSet())
          .timeout(storeTimeout);
      _guard(owner);
      _products.clear();
      for (final product in result.products) {
        if (lunoBillingCatalog.containsKey(product.id)) {
          _products[product.id] = product;
        }
      }
      _missing = lunoBillingCatalog.keys.toSet().difference(
        _products.keys.toSet(),
      );
      _emit(LunoBillingStatus.idle);
      return LunoBillingProductQuery(
        List.unmodifiable(_products.values),
        Set.unmodifiable(_missing),
      );
    } catch (error) {
      if (isCurrent(owner)) _report(_failure(error));
      throw _failure(error);
    }
  }

  /// A true result means Play's flow launched, not that anything was granted.
  Future<bool> purchase(String productId) async {
    final owner = _requireOwner();
    if (!_available) throw const LunoBillingFailure('store-unavailable');
    final product = _products[productId];
    if (product == null) throw const LunoBillingFailure('product-unavailable');
    const busy = {
      LunoBillingStatus.purchasing,
      LunoBillingStatus.pending,
      LunoBillingStatus.verifying,
      LunoBillingStatus.queued,
    };
    if (_launchProduct != null ||
        _restoring != null ||
        _queue.values.any((queued) => queued.productId == productId) ||
        busy.contains(_productStatuses[productId])) {
      throw const LunoBillingFailure('billing-busy');
    }
    if (product.kind == LunoBillingProductKind.membership) {
      if (_ownsMembership) {
        throw const LunoBillingFailure('membership-already-owned');
      }
      if (_productStatuses.entries.any(
        (entry) =>
            lunoBillingCatalog[entry.key] ==
                LunoBillingProductKind.membership &&
            busy.contains(entry.value),
      )) {
        throw const LunoBillingFailure('billing-busy');
      }
    }
    _launchProduct = productId;
    final operation = Object();
    _launchOperation = operation;
    _emit(LunoBillingStatus.purchasing, productId: productId);
    // If the native launch times out, keep it locked until its future settles;
    // a late launch must not be followed by a second payment sheet.
    final launch = Future<bool>.sync(() {
      _guard(owner);
      return _play.launch(product, _accountHash(owner));
    });
    unawaited(
      launch
          .then<void>((_) {}, onError: (Object _, StackTrace _) {})
          .whenComplete(() {
            if (isCurrent(owner) &&
                identical(_launchOperation, operation) &&
                _productStatuses[productId] != LunoBillingStatus.purchasing) {
              _launchProduct = null;
              _launchOperation = null;
            }
          }),
    );
    try {
      final launched = await launch.timeout(storeTimeout);
      _guard(owner);
      if (!launched) {
        _launchProduct = null;
        _launchOperation = null;
        _emit(
          LunoBillingStatus.error,
          productId: productId,
          code: 'purchase-not-launched',
        );
      }
      return launched;
    } catch (error) {
      if (isCurrent(owner)) {
        if (error is! TimeoutException &&
            identical(_launchOperation, operation)) {
          _launchProduct = null;
          _launchOperation = null;
        }
        _report(_failure(error), productId: productId);
      }
      throw _failure(error);
    }
  }

  /// Queries current Play ownership, verifies each token, then refreshes server
  /// state. Consumed grants are recovered by this refresh, not a local receipt.
  /// Individual verify calls use the strict three-flag contract; the batch
  /// restore endpoint's count is intentionally not treated as grant authority.
  Future<void> restore() {
    final owner = _requireOwner();
    return _restoring ??= _restore(owner);
  }

  Future<void> _restore(LunoBillingOwner owner) async {
    try {
      final owned = await _play
          .queryOwned(_accountHash(owner))
          .timeout(storeTimeout);
      _guard(owner);
      for (final queued in _queue.values) {
        queued.deferred = false;
      }
      _handleBatch(owner, owned, replayCompleted: true);
      await retryQueued();
      _guard(owner);
      await _refreshState(owner);
      _guard(owner);
      if (_queue.isEmpty &&
          !_productStatuses.values.any(
            (s) =>
                s == LunoBillingStatus.pending || s == LunoBillingStatus.error,
          )) {
        _emit(LunoBillingStatus.idle);
      }
    } catch (error) {
      if (isCurrent(owner)) _report(_failure(error));
      throw _failure(error);
    } finally {
      if (isCurrent(owner)) _restoring = null;
    }
  }

  Future<void> retryQueued() {
    final owner = _requireOwner();
    if (_draining != null) return _draining!;
    for (final queued in _queue.values) {
      queued.deferred = false;
    }
    return _drainQueue(owner);
  }

  void _handleBatch(
    LunoBillingOwner owner,
    List<LunoPlayPurchase> batch, {
    bool replayCompleted = false,
  }) {
    if (!isCurrent(owner)) return;
    for (final receipt in batch) {
      final id = receipt.productId.isEmpty ? _launchProduct : receipt.productId;
      if (id == null || !lunoBillingCatalog.containsKey(id)) continue;
      if (receipt.obfuscatedAccountId != null &&
          receipt.obfuscatedAccountId != _accountHash(owner)) {
        _emit(LunoBillingStatus.error, productId: id, code: 'account-mismatch');
        continue;
      }
      if (_launchProduct == id) {
        _launchProduct = null;
        _launchOperation = null;
      }
      switch (receipt.status) {
        case LunoPlayPurchaseStatus.pending:
          _emit(LunoBillingStatus.pending, productId: id);
          continue;
        case LunoPlayPurchaseStatus.canceled:
          _emit(LunoBillingStatus.canceled, productId: id);
          continue;
        case LunoPlayPurchaseStatus.error:
          _emit(
            LunoBillingStatus.error,
            productId: id,
            code: 'purchase-failed',
          );
          continue;
        case LunoPlayPurchaseStatus.purchased:
        case LunoPlayPurchaseStatus.restored:
          break;
      }
      final token = receipt.purchaseToken;
      if (token.isEmpty || token.length > 4096 || receipt.productId.isEmpty) {
        _emit(LunoBillingStatus.error, productId: id, code: 'invalid-receipt');
        continue;
      }
      final key = sha256.convert(utf8.encode(token)).toString();
      final retryInactiveMembership =
          replayCompleted &&
          lunoBillingCatalog[id] == LunoBillingProductKind.membership &&
          _rejected[key] == 'purchase-not-active';
      if (_queue.containsKey(key) ||
          (_rejected.containsKey(key) && !retryInactiveMembership) ||
          (!replayCompleted && _completed.contains(key))) {
        continue;
      }
      if (_queue.length >= 64) {
        _emit(
          LunoBillingStatus.queued,
          productId: id,
          code: 'verification-queue-full',
        );
        continue;
      }
      if (retryInactiveMembership) _rejected.remove(key);
      _queue[key] = _QueuedPurchase(id, token);
    }
    unawaited(_drainQueue(owner));
  }

  Future<void> _drainQueue(LunoBillingOwner owner) {
    if (!isCurrent(owner)) return Future<void>.value();
    return _draining ??= Future<void>.microtask(() => _drain(owner));
  }

  Future<void> _drain(LunoBillingOwner owner) async {
    try {
      while (isCurrent(owner)) {
        final next =
            _queue.entries.where((entry) => !entry.value.deferred).firstOrNull;
        if (next == null) return;
        next.value.deferred = true;
        await _verifyQueued(owner, next.key, next.value);
      }
    } finally {
      if (isCurrent(owner)) _draining = null;
    }
  }

  Future<void> _verifyQueued(
    LunoBillingOwner owner,
    String key,
    _QueuedPurchase purchase,
  ) async {
    _emit(LunoBillingStatus.verifying, productId: purchase.productId);
    try {
      if (!purchase.granted) {
        _guard(owner);
        // Production transport already performs at most three request attempts.
        // Stream duplicates never trigger retries; retryQueued is explicit.
        final result = await _backend
            .verify(owner, purchase.productId, purchase.token)
            .timeout(requestTimeout);
        _guard(owner);
        if (result['ok'] != true ||
            result['verified'] != true ||
            result['entitlementGranted'] != true) {
          throw const LunoBillingFailure('verification-rejected');
        }
        purchase.granted = true;
        if (lunoBillingCatalog[purchase.productId] ==
            LunoBillingProductKind.membership) {
          _ownsMembership = true;
        }
      }
      await _refreshState(owner);
      _guard(owner);
      _queue.remove(key);
      _completed.add(key);
      if (_completed.length > 256) _completed.remove(_completed.first);
      _emit(LunoBillingStatus.verified, productId: purchase.productId);
    } catch (error) {
      if (!isCurrent(owner)) return;
      final failure = _failure(error);
      if (failure.retryable || purchase.granted) {
        _emit(
          LunoBillingStatus.queued,
          productId: purchase.productId,
          code: purchase.granted ? 'state-refresh-required' : failure.code,
        );
      } else {
        _queue.remove(key);
        _rejected[key] = failure.code;
        if (_rejected.length > 256) _rejected.remove(_rejected.keys.first);
        _report(failure, productId: purchase.productId);
      }
    }
  }

  Future<void> _refreshState(LunoBillingOwner owner) async {
    _guard(owner);
    final response = await _backend
        .getPlayerState(owner)
        .timeout(requestTimeout);
    _guard(owner);
    final state = response['state'];
    if (response['ok'] != true || state is! Map || state['uid'] != owner.uid) {
      throw const LunoBillingFailure('invalid-server-state', retryable: true);
    }
    final snapshot = LunoBillingSnapshot(
      owner,
      Map<String, dynamic>.from(state),
    );
    final membership = state['membership'];
    _ownsMembership = membership is Map && membership['active'] == true;
    _latestSnapshot = snapshot;
    _snapshots.add(snapshot);
    notifyListeners();
  }

  String _accountHash(LunoBillingOwner owner) =>
      sha256.convert(utf8.encode(owner.uid)).toString();

  LunoBillingFailure _failure(Object error) =>
      error is LunoBillingFailure
          ? error
          : const LunoBillingFailure('billing-unavailable', retryable: true);

  void _report(LunoBillingFailure failure, {String? productId}) => _emit(
    failure.retryable ? LunoBillingStatus.queued : LunoBillingStatus.error,
    productId: productId,
    code: failure.code,
  );

  void _emit(LunoBillingStatus status, {String? productId, String? code}) {
    if (_disposed) return;
    _status = status;
    _errorCode = code;
    if (productId != null) _productStatuses[productId] = status;
    _events.add(
      LunoBillingEvent(status, productId: productId, errorCode: code),
    );
    notifyListeners();
  }

  Future<void> _clearSession() {
    _owner = null;
    final subscription = _subscription;
    _subscription = null;
    _initialization = null;
    _draining = null;
    _restoring = null;
    _launchProduct = null;
    _launchOperation = null;
    _available = false;
    _ownsMembership = false;
    _products.clear();
    _productStatuses.clear();
    _queue.clear();
    _completed.clear();
    _rejected.clear();
    _missing = const {};
    _latestSnapshot = null;
    return subscription?.cancel() ?? Future<void>.value();
  }

  Future<void> stop() {
    _enabled = false;
    final canceled = _clearSession();
    _emit(LunoBillingStatus.idle);
    return canceled;
  }

  @override
  void dispose() {
    _disposed = true;
    _enabled = false;
    _backend.removeListener(_onBackendChanged);
    unawaited(_clearSession());
    unawaited(_events.close());
    unawaited(_snapshots.close());
    super.dispose();
  }
}

class _QueuedPurchase {
  _QueuedPurchase(this.productId, this.token);
  final String productId;
  final String token;
  bool granted = false;
  bool deferred = false;
}
