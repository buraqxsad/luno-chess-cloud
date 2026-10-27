import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/game_store.dart';
import '../data/username.dart';
import 'social_action_result.dart';
import 'app_release_identity.dart';
import 'google_account_credentials.dart';
import 'social_safety_result.dart';
import 'public_player_profile.dart';
import 'battle_v1_rank.dart';
import 'direct_message_rows.dart';
import 'pass_action_result.dart';
import 'shop_action_result.dart';
import '../data/permanent_purchase.dart';
import '../data/pass_purchase.dart';
import '../battle_v1/online.dart';
import '../battle_v1/deck_account.dart';
import '../battle_v1/model.dart';

class BlockedPlayersPage {
  const BlockedPlayersPage({
    required this.players,
    required this.nextPageToken,
    this.unavailableUids = const <String>{},
  });
  final List<BlockedPlayer> players;
  final String? nextPageToken;
  final Set<String> unavailableUids;

  static String cursorKey(String value, String ownerUid) {
    if (value.isEmpty ||
        value.length > 512 ||
        !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value)) {
      throw const FormatException('Invalid blocked-list cursor');
    }
    final bytes = base64Url.decode(base64Url.normalize(value));
    if (base64Url.encode(bytes).replaceAll('=', '') != value) {
      throw const FormatException('Invalid blocked-list cursor');
    }
    final token = jsonDecode(utf8.decode(bytes));
    if (token is! Map ||
        token.length != 4 ||
        token.keys.any(
          (key) => !const {'v', 'scope', 'uid', 'after'}.contains(key),
        ) ||
        token['v'] != 1 ||
        token['scope'] != 'blocked-users' ||
        token['uid'] != ownerUid ||
        token['after'] is! String ||
        !RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(token['after'] as String)) {
      throw const FormatException('Invalid blocked-list cursor');
    }
    return token['after'] as String;
  }

  factory BlockedPlayersPage.fromResponse(
    Map<String, dynamic> result, {
    required String ownerUid,
    String? requestedToken,
  }) {
    final rows = result['results'];
    if (rows is! List || rows.length > 25) {
      throw const FormatException('Invalid blocked-list page');
    }
    final players = parseBlockedPlayers(result, viewerUid: ownerUid);
    final next = result['nextPageToken'];
    if (next != null && next is! String) {
      throw const FormatException('Invalid blocked-list cursor');
    }
    if (requestedToken != null) {
      cursorKey(requestedToken, ownerUid);
    }
    if (next is String) {
      cursorKey(next, ownerUid);
      if (next == requestedToken) {
        throw const FormatException('Blocked-list cursor did not advance');
      }
    }
    final unavailable = <String>{};
    for (final row in rows) {
      if (row is Map && row.containsKey('unavailable')) {
        if (row['unavailable'] is! bool) {
          throw const FormatException('Invalid blocked-player state');
        }
        if (row['unavailable'] == true) {
          unavailable.add(row['uid'] as String);
        }
      }
    }
    return BlockedPlayersPage(
      players: players,
      nextPageToken: next as String?,
      unavailableUids: Set.unmodifiable(unavailable),
    );
  }
}

class LunoApiException implements Exception {
  final String code;
  final int status;
  const LunoApiException(this.code, this.status);

  String? get accountAccessMessage => switch (code) {
    'account-deleted' =>
      'Bu hesap silinmiş. Bu hesapla online oyuna devam edilemez.',
    'account-deletion-in-progress' =>
      'Hesap silme işlemi sürüyor. Online işlemler durduruldu.',
    _ => null,
  };

  @override
  String toString() => 'LunoApiException($code, $status)';
}

/// Native Firebase oturumu ve sunucu API köprüsü.
///
/// Uygulama açılışında ağı bekletmez: bağlantı yoksa AI/yerel ekranlar açılır,
/// bağlantı geldiğinde aynı Firebase anonim hesabı üzerinden senkron yapılır.
class LunoOnlineService extends ChangeNotifier {
  LunoOnlineService._({
    Future<void> Function()? bootstrapOverride,
    bool validateAuthForTesting = false,
    FirebaseAuth? auth,
    http.Client? client,
    Future<String?> Function()? appCheckOverride,
    Future<AppReleaseIdentity> Function()? appReleaseIdentityOverride,
    Future<OAuthCredential> Function()? googleCredentialOverride,
    Future<Object?> Function(String)? databaseReadOverride,
    Stream<User?>? authChangesOverride,
    GameStore? playerStoreOverride,
    Stream<List<Map<String, dynamic>>>? friendRequestStreamOverride,
    Stream<List<Map<String, dynamic>>>? matchInviteStreamOverride,
    Stream<List<Map<String, dynamic>>> Function(String)?
    directMessageStreamOverride,
  }) : _bootstrapOverride = bootstrapOverride,
       _validateAuthForTesting = validateAuthForTesting,
       _appCheckOverride = appCheckOverride,
       _appReleaseIdentity =
           appReleaseIdentityOverride ?? AppReleaseIdentity.fromPlatform,
       _googleCredential =
           googleCredentialOverride ?? GoogleAccountCredentials.select,
       _databaseReadOverride = databaseReadOverride,
       _playerStoreOverride = playerStoreOverride,
       _friendRequestStreamOverride = friendRequestStreamOverride,
       _matchInviteStreamOverride = matchInviteStreamOverride,
       _directMessageStreamOverride = directMessageStreamOverride,
       _client = client ?? http.Client(),
       _auth = auth,
       _user = auth?.currentUser {
    if (authChangesOverride != null) _bindAuthChanges(authChangesOverride);
  }
  @visibleForTesting
  factory LunoOnlineService.forTesting({
    required Future<void> Function() bootstrap,
    bool validateAuth = false,
    FirebaseAuth? auth,
    http.Client? client,
    Future<String?> Function()? appCheck,
    Future<AppReleaseIdentity> Function()? appReleaseIdentity,
    Future<OAuthCredential> Function()? googleCredential,
    Future<Object?> Function(String)? databaseRead,
    Stream<User?>? authChanges,
    GameStore? playerStore,
    Stream<List<Map<String, dynamic>>>? friendRequestStream,
    Stream<List<Map<String, dynamic>>>? matchInviteStream,
    Stream<List<Map<String, dynamic>>> Function(String)? directMessageStream,
  }) => LunoOnlineService._(
    bootstrapOverride: bootstrap,
    validateAuthForTesting: validateAuth,
    auth: auth,
    client: client,
    appCheckOverride: appCheck,
    appReleaseIdentityOverride:
        appReleaseIdentity ??
        () async =>
            const AppReleaseIdentity(versionName: 'test', buildNumber: 1),
    googleCredentialOverride:
        googleCredential ??
        () async =>
            GoogleAuthProvider.credential(idToken: 'test-google-id-token'),
    databaseReadOverride: databaseRead,
    authChangesOverride: authChanges,
    playerStoreOverride: playerStore,
    friendRequestStreamOverride: friendRequestStream,
    matchInviteStreamOverride: matchInviteStream,
    directMessageStreamOverride: directMessageStream,
  );
  final Future<void> Function()? _bootstrapOverride;
  final bool _validateAuthForTesting;
  final Future<String?> Function()? _appCheckOverride;
  final Future<AppReleaseIdentity> Function() _appReleaseIdentity;
  final Future<OAuthCredential> Function() _googleCredential;
  final Future<Object?> Function(String)? _databaseReadOverride;
  final GameStore? _playerStoreOverride;
  final Stream<List<Map<String, dynamic>>>? _friendRequestStreamOverride;
  final Stream<List<Map<String, dynamic>>>? _matchInviteStreamOverride;
  final Stream<List<Map<String, dynamic>>> Function(String)?
  _directMessageStreamOverride;
  bool get _bindsPlayerStore =>
      _bootstrapOverride == null || _playerStoreOverride != null;
  GameStore get _playerStore => _playerStoreOverride ?? GameStore.instance;
  bool _bootstrapApiReady = false;
  bool _deletingAccount = false;
  bool _deletionInFlight = false;
  bool _linkingGoogle = false;
  bool _signingInGoogle = false;
  bool _choosingGoogleAccount = false;
  bool get accountSignInInProgress => _signingInGoogle;
  static final instance = LunoOnlineService._();

  static const apiBase =
      'https://europe-west1-luno-chess.cloudfunctions.net/lunoApi';
  final http.Client _client;
  FirebaseAuth? _auth;
  User? _user;
  bool ready = false;
  bool loading = false;
  String? lastError;
  Object? _lastFailure;
  LunoApiException? get accountFailure {
    final failure = _lastFailure;
    return failure is LunoApiException && failure.accountAccessMessage != null
        ? failure
        : null;
  }

  DateTime? lastSyncAt;
  bool _appCheckActivated = false;
  final String _requestInstance = Random.secure()
      .nextInt(0x7fffffff)
      .toRadixString(36);
  int _requestCounter = 0;
  int _requestGeneration = 0;
  int _accountRevision = 0;
  int get accountRevision => _accountRevision;
  final Stopwatch _battleClock = Stopwatch()..start();
  final _battleClockSamples = <(String, int, String), (int, int)>{};

  int? battleV1ServerNow(String matchId) {
    final uid = user?.uid;
    if (_disposed || uid == null) return null;
    final sample = _battleClockSamples[(uid, accountRevision, matchId)];
    return sample == null
        ? null
        : sample.$1 + _battleClock.elapsedMilliseconds - sample.$2;
  }

  BattleDeckAccount? _battleDeckCache;
  (String?, int, int)? _battleDeckCacheOwner;
  (String?, int, int)? _battleDeckSaveOwner;
  int _battleDeckWriteRevision = 0;
  int _battleDeckReadRevision = 0;
  (String?, int, int) get _battleDeckOwner => (
    user?.uid,
    accountRevision,
    _playerStore.accountBindingRevision,
  );
  BattleDeckAccount? get cachedBattleDeck =>
      !_disposed &&
              !_authTransitioning &&
              user != null &&
              accountFailure == null &&
              _battleDeckCacheOwner == _battleDeckOwner
          ? _battleDeckCache
          : null;
  bool _authTransitioning = false;
  bool _disposed = false;
  bool get authTransitioning => _authTransitioning;
  String? _observedAuthUid;
  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<DatabaseEvent>? _connectionSubscription;
  final List<StreamSubscription<List<Map<String, dynamic>>>>
  _activitySubscriptions = [];
  List<Map<String, dynamic>> _notificationCache = const [];
  final Map<(String?, int, String), Future<void>> _notificationReads = {};
  final Map<(String, int, String, String), Future<Map<String, dynamic>>>
  _chestOpenings = {};
  final Map<(String, int, String), Future<Map<String, dynamic>>>
  _permanentPurchases = {};
  final Map<(String, int), Future<Map<String, dynamic>>> _premiumPurchases = {};
  List<Map<String, dynamic>> _directMessageCache = const [];
  List<Map<String, dynamic>> _friendRequestCache = const [];
  List<Map<String, dynamic>> _matchInviteCache = const [];
  bool? _databaseConnected;
  bool _bootstrapping = false;
  bool _recoveringConnection = false;
  int _recoverySerial = 0;
  int _connectionMonitorGeneration = 0;
  int _activityGeneration = 0;
  String? _activityUid;

  User? get user => _auth == null ? _user : _auth!.currentUser;
  bool get isOnline => ready && user != null && lastError == null;
  int get unreadNotificationCount =>
      _hasCurrentActivity ? countUnreadNotifications(_notificationCache) : 0;
  bool notificationIsRead(String notificationId) =>
      _hasCurrentActivity &&
      _notificationCache.any(
        (row) =>
            row['notificationId']?.toString() == notificationId &&
            row['read'] == true,
      );
  int get unreadDirectMessageCount =>
      _hasCurrentActivity ? countUnreadDirectMessages(_directMessageCache) : 0;
  int get pendingFriendRequestCount =>
      _hasCurrentActivity ? _friendRequestCache.length : 0;
  int get pendingMatchInviteCount =>
      _hasCurrentActivity ? _matchInviteCache.length : 0;
  bool get _hasCurrentActivity =>
      _activityUid != null &&
      user?.uid == _activityUid &&
      accountFailure == null;
  int get socialActivityBadgeCount => activityBadgeCount(
    unreadNotifications: unreadNotificationCount,
    pendingFriendRequests: pendingFriendRequestCount,
    pendingMatchInvites: pendingMatchInviteCount,
  );

  Future<void>? _startFuture;
  Future<(User, int)>? _cachedSessionRecovery;
  String? _cachedSessionRecoveryUid;
  String? _recoveredCachedSessionUid;
  bool _recoveringCachedSession = false;

  /// Tek bir Firebase bootstrap isteği paylaşılır; açılışta main(), profil ve
  /// online ekranı aynı anda çağırsa bile birden fazla anonim hesap açılmaz.
  Future<void> start() {
    if (_disposed) return Future.error(StateError('Online service disposed'));
    if (_choosingGoogleAccount) {
      return Future.error(
        const LunoApiException('account-signin-in-progress', 409),
      );
    }
    if (_startFuture case final running?) return running;
    if (ready && lastError == null) return Future<void>.value();
    // Install the gate before bootstrap can fail or notify synchronously.
    final completion = Completer<void>();
    final attempt = completion.future;
    _startFuture = attempt;
    void clearAttempt() {
      if (identical(_startFuture, attempt)) _startFuture = null;
    }

    unawaited(
      _startInternal().then<void>(
        (_) {
          clearAttempt();
          completion.complete();
        },
        onError: (Object error, StackTrace stack) {
          clearAttempt();
          completion.completeError(error, stack);
        },
      ),
    );
    return attempt;
  }

  Future<void> _startInternal() async {
    var generation = ++_requestGeneration;
    if (_bindsPlayerStore) _playerStore.invalidateServerStates();
    _clearActivityStreams();
    ready = false;
    loading = true;
    _bootstrapping = true;
    _bootstrapApiReady = false;
    lastError = null;
    _lastFailure = null;
    notifyListeners();
    try {
      if (_bootstrapOverride == null) {
        try {
          await Firebase.initializeApp();
        } on FirebaseException catch (error) {
          if (error.code != 'duplicate-app') rethrow;
        }
        await _activateAppCheck();
        _auth = FirebaseAuth.instance;
        if (_authSubscription == null) {
          _bindAuthChanges(_auth!.authStateChanges());
        }
      }
      if (_bootstrapOverride == null || _validateAuthForTesting) {
        final prepared = await _prepareAuthUser(generation);
        _user = prepared.$1;
        generation = prepared.$2;
      }
      if (_bootstrapOverride != null) {
        if (_bindsPlayerStore) await _playerStore.bindAccount(user?.uid);
        await _bootstrapOverride();
      } else {
        if (generation != _requestGeneration) return;
        await _playerStore.bindAccount(_user!.uid);
        if (generation != _requestGeneration) return;
        _bootstrapApiReady = true;
        _bindConnectionMonitor();
        await _ensureRemoteProfile();
        _bindActivityStreams();
      }
      if (generation != _requestGeneration) return;
      ready = true;
      lastSyncAt = DateTime.now();
    } catch (error) {
      if (generation != _requestGeneration) return;
      ready = false;
      final failure =
          error is LocalAccountErasedException
              ? const LunoApiException('account-deleted', 403)
              : error;
      if ((error is LocalAccountErasedException ||
              (failure is LunoApiException &&
                  failure.code == 'account-deleted')) &&
          _bindsPlayerStore &&
          user != null) {
        final deletedUid = user!.uid;
        try {
          await _playerStore.eraseLocalAccount(deletedUid);
          if (generation != _requestGeneration) return;
          if (user?.uid == deletedUid) await _auth!.signOut();
          if (user == null) {
            _lastFailure = null;
            lastError = null;
            return;
          }
        } catch (cleanupError) {
          if (kDebugMode) {
            debugPrint('Local account erasure incomplete: $cleanupError');
          }
        }
        if (generation != _requestGeneration) return;
      }
      _lastFailure = failure;
      lastError = _friendlyError(failure);
      if (kDebugMode) debugPrint('Luno native online boot failed: $error');
    } finally {
      _bootstrapping = false;
      _bootstrapApiReady = false;
      loading = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> retry() async {
    ready = false;
    lastError = null;
    notifyListeners();
    await start();
  }

  static bool _isInvalidCachedUser(Object error) =>
      error is FirebaseAuthException &&
      const {
        'user-not-found',
        'user-token-expired',
        'invalid-user-token',
      }.contains(error.code);

  Future<(User, int)> _prepareAuthUser(int generation) async {
    final cached = _auth!.currentUser;
    if (cached != null) {
      try {
        // Admin deletion does not update the locally persisted currentUser.
        await cached.reload();
      } on FirebaseAuthException catch (error) {
        if (!_isInvalidCachedUser(error)) rethrow;
        return _recoverInvalidCachedUser(cached, generation, error);
      }
    } else {
      await _auth!.signInAnonymously();
    }
    final current = user;
    if (_disposed ||
        generation != _requestGeneration ||
        (cached != null && current?.uid != cached.uid)) {
      throw const LunoApiException('session-changed', 409);
    }
    if (current == null) {
      throw const LunoApiException('auth-user-missing', 401);
    }
    return (current, generation);
  }

  Future<(User, int)> _recoverInvalidCachedUser(
    User invalidUser,
    int generation,
    FirebaseAuthException failure,
  ) {
    final pending = _cachedSessionRecovery;
    if (pending != null && _cachedSessionRecoveryUid == invalidUser.uid) {
      return pending;
    }
    if (_linkingGoogle ||
        _signingInGoogle ||
        _deletingAccount ||
        _deletionInFlight) {
      return Future.error(failure);
    }
    // Some Firebase SDKs sign out automatically on invalid-user errors.
    if (_disposed ||
        (user != null &&
            (user!.uid != invalidUser.uid ||
                generation != _requestGeneration))) {
      return Future.error(const LunoApiException('session-changed', 409));
    }
    _cachedSessionRecoveryUid = invalidUser.uid;
    return _cachedSessionRecovery = _replaceInvalidCachedUser(
      invalidUser,
      failure,
    );
  }

  Future<(User, int)> _replaceInvalidCachedUser(
    User invalidUser,
    FirebaseAuthException failure,
  ) async {
    _recoveringCachedSession = true;
    _authTransitioning = true;
    _requestGeneration++;
    ready = false;
    _clearActivityStreams();
    if (_bindsPlayerStore) _playerStore.invalidateServerStates();
    notifyListeners();
    try {
      // Revoked/invalid credentials do not prove that account data was deleted.
      if (failure.code == 'user-not-found' && _bindsPlayerStore) {
        await _playerStore.eraseLocalAccount(invalidUser.uid);
      }
      if (_disposed || (user != null && user!.uid != invalidUser.uid)) {
        throw const LunoApiException('session-changed', 409);
      }
      if (user != null) await _auth!.signOut();
      if (_disposed || user != null) {
        throw const LunoApiException('session-changed', 409);
      }
      if (_bindsPlayerStore) await _playerStore.bindAccount(null);
      if (_disposed || user != null) {
        throw const LunoApiException('session-changed', 409);
      }
      final fresh = (await _auth!.signInAnonymously()).user;
      if (_disposed || fresh == null || user?.uid != fresh.uid) {
        throw const LunoApiException('session-changed', 409);
      }
      _user = fresh;
      if (_observedAuthUid != fresh.uid) {
        _recoveredCachedSessionUid = fresh.uid;
      }
      return (fresh, _requestGeneration);
    } catch (error) {
      if (!_disposed) {
        final current = user;
        if (current != null && current.uid != invalidUser.uid) {
          unawaited(_restartAfterAuthChange(_accountRevision, current.uid));
        } else {
          _markConnectionFailure(error);
        }
      }
      rethrow;
    } finally {
      _recoveringCachedSession = false;
      _cachedSessionRecovery = null;
      _cachedSessionRecoveryUid = null;
      _authTransitioning = false;
      if (!_disposed) notifyListeners();
    }
  }

  void _bindAuthChanges(Stream<User?> changes) {
    _observedAuthUid = user?.uid;
    _authSubscription = changes.listen(
      (next) => _observeAuthUser(next),
      onError: (Object error, StackTrace stack) {
        _markConnectionFailure(error);
      },
    );
  }

  void _observeAuthUser(User? next) {
    if (_signingInGoogle && next?.uid != user?.uid) return;
    final uid = next?.uid;
    if (_recoveredCachedSessionUid != null) {
      // Native auth events can trail the completed sign-in Future.
      if (user?.uid == _recoveredCachedSessionUid &&
          uid != _recoveredCachedSessionUid) {
        return;
      }
      _recoveredCachedSessionUid = null;
    }
    if (uid == _observedAuthUid) return;
    final hadAccount = _observedAuthUid != null;
    _observedAuthUid = uid;
    _accountRevision++;
    _battleClockSamples.clear();
    if (_bindsPlayerStore) _playerStore.invalidateServerStates();
    // Initial anonymous sign-in is part of the running bootstrap; later
    // transitions invalidate in-flight work even when the same UID returns.
    if (hadAccount || uid == null) _requestGeneration++;
    _recoverySerial++;
    if (hadAccount || uid == null) {
      _connectionMonitorGeneration++;
      unawaited(_connectionSubscription?.cancel());
      _connectionSubscription = null;
      _databaseConnected = null;
    }
    _clearActivityStreams();
    ready = false;
    lastError = null;
    _lastFailure = null;
    _user = next;
    if (uid == null && _bindsPlayerStore) {
      unawaited(_clearSignedOutStore(_accountRevision));
    }
    final restart =
        !_signingInGoogle &&
        !_recoveringCachedSession &&
        uid != null &&
        (hadAccount || !_bootstrapping);
    _authTransitioning =
        _signingInGoogle || restart || _recoveringCachedSession;
    notifyListeners();
    if (restart) unawaited(_restartAfterAuthChange(_accountRevision, uid));
  }

  Future<void> _clearSignedOutStore(int revision) async {
    try {
      await _playerStore.bindAccount(null);
    } catch (error) {
      if (!_disposed && revision == _accountRevision) {
        _markConnectionFailure(error);
      }
    }
  }

  Future<void> _ensureReadyForApi({bool resumeDeletion = false}) async {
    // _startInternal syncs the guest profile before it can mark the service
    // ready. Once Firebase has supplied both auth objects, waiting for the
    // current bootstrap Future here would make that bootstrap await itself.
    if (_bootstrapping &&
        _bootstrapApiReady &&
        _auth != null &&
        _user != null) {
      return;
    }
    if (resumeDeletion &&
        accountFailure?.code == 'account-deletion-in-progress' &&
        _auth?.currentUser != null) {
      return;
    }
    if (accountFailure != null) throw accountFailure!;
    if (ready && lastError == null && _auth != null && _user != null) return;
    try {
      await start().timeout(const Duration(seconds: 12));
    } on TimeoutException {
      const failure = LunoApiException('network-unavailable', 0);
      _markConnectionFailure(failure);
      throw failure;
    }
    if (!ready || lastError != null || _auth == null || _user == null) {
      if (_lastFailure != null) throw _lastFailure!;
      throw const LunoApiException('network-unavailable', 0);
    }
  }

  /// Firebase RTDB'nin bağlantı sinyali Wi-Fi/mobil veri değişimlerinde
  /// istemcinin eski sokete takılı kalmasını engeller. RTDB stream'leri kendi
  /// başına yeniden bağlansa da HTTP Functions oturumunu da aynı anda tazeler.
  void _bindConnectionMonitor() {
    final generation = ++_connectionMonitorGeneration;
    _connectionSubscription?.cancel();
    _databaseConnected = null;
    final ref = FirebaseDatabase.instance.ref('.info/connected');
    _connectionSubscription = ref.onValue.listen(
      (event) {
        if (generation != _connectionMonitorGeneration) return;
        final connected = event.snapshot.value == true;
        final previous = _databaseConnected;
        _databaseConnected = connected;
        if (!connected) {
          _recoverySerial++;
          _markConnectionFailure(
            const LunoApiException('network-unavailable', 0),
          );
          return;
        }
        if (previous != true) unawaited(_recoverAfterReconnect());
      },
      onError: (Object error, StackTrace stack) {
        if (generation != _connectionMonitorGeneration) return;
        _markConnectionFailure(error);
      },
    );
  }

  Future<void> _recoverAfterReconnect() async {
    if (_signingInGoogle || _recoveringConnection || accountFailure != null) {
      return;
    }
    _recoveringConnection = true;
    final serial = ++_recoverySerial;
    try {
      if (!ready || lastError != null || _auth == null || _user == null) {
        await retry();
      } else {
        await refreshState().timeout(const Duration(seconds: 10));
      }
      if (serial == _recoverySerial && ready && lastError == null) {
        ready = true;
        _markOnline();
      }
    } catch (error) {
      if (serial == _recoverySerial) {
        ready = false;
        _markConnectionFailure(error);
      }
    } finally {
      _recoveringConnection = false;
    }
  }

  @visibleForTesting
  Future<void> recoverAfterReconnectForTesting() => _recoverAfterReconnect();

  void _clearActivityStreams() {
    _activityGeneration++;
    _activityUid = null;
    for (final subscription in _activitySubscriptions) {
      unawaited(subscription.cancel());
    }
    _activitySubscriptions.clear();
    _notificationCache = const [];
    _directMessageCache = const [];
    _friendRequestCache = const [];
    _matchInviteCache = const [];
  }

  @visibleForTesting
  void bindActivityStreamsForTesting(
    List<Stream<List<Map<String, dynamic>>>> streams,
  ) {
    if (streams.length != 4) {
      throw ArgumentError('Expected four activity streams');
    }
    _bindActivityStreams(streams: streams);
  }

  void _bindActivityStreams({
    List<Stream<List<Map<String, dynamic>>>>? streams,
  }) {
    _clearActivityStreams();
    final uid = user?.uid;
    if (uid == null) {
      notifyListeners();
      return;
    }
    _activityUid = uid;
    final generation = _activityGeneration;
    bool isCurrent() =>
        generation == _activityGeneration && _hasCurrentActivity;
    void onStreamError(Object error, StackTrace stack) {
      if (!isCurrent()) return;
      _markConnectionFailure(error);
    }

    final sources =
        streams ??
        [
          notificationsStream(),
          directMessageInboxStream(),
          friendRequestsStream(),
          matchInvitesStream(),
        ];
    _activitySubscriptions.add(
      sources[0].listen((rows) {
        if (!isCurrent()) return;
        _notificationCache = rows;
        notifyListeners();
      }, onError: onStreamError),
    );
    _activitySubscriptions.add(
      sources[1].listen((rows) {
        if (!isCurrent()) return;
        _directMessageCache = rows;
        notifyListeners();
      }, onError: onStreamError),
    );
    _activitySubscriptions.add(
      sources[2].listen((rows) {
        if (!isCurrent()) return;
        _friendRequestCache = rows;
        notifyListeners();
      }, onError: onStreamError),
    );
    _activitySubscriptions.add(
      sources[3].listen((rows) {
        if (!isCurrent()) return;
        _matchInviteCache = rows;
        notifyListeners();
      }, onError: onStreamError),
    );
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _battleClock.stop();
    _battleClockSamples.clear();
    if (_bindsPlayerStore) _playerStore.invalidateServerStates();
    ready = false;
    _authTransitioning = false;
    _accountRevision++;
    _requestGeneration++;
    _connectionMonitorGeneration++;
    _recoverySerial++;
    _clearActivityStreams();
    unawaited(_authSubscription?.cancel());
    unawaited(_connectionSubscription?.cancel());
    _client.close();
    super.dispose();
  }

  static int countUnreadNotifications(Iterable<Map<String, dynamic>> rows) =>
      rows.where((row) => row['read'] != true).length;

  static int countUnreadDirectMessages(Iterable<Map<String, dynamic>> rows) =>
      rows.where((row) => row['unread'] == true).length;

  static int activityBadgeCount({
    required int unreadNotifications,
    required int pendingFriendRequests,
    required int pendingMatchInvites,
  }) => max(
    0,
    max(unreadNotifications, max(pendingFriendRequests, pendingMatchInvites)),
  );

  Future<void> refreshState() async {
    final uid = user?.uid;
    final revision = _playerStore.accountBindingRevision;
    final draft =
        _playerStore.hasChosenUsername
            ? _playerStore.data.username
            : _playerStore.pendingUsernameDraft;
    final result = await getPlayerState();
    final state = result['state'];
    if (state is Map) {
      final profile = state['profile'];
      if (_bindsPlayerStore &&
          uid != null &&
          profile is Map &&
          profile['usernameGenerated'] == true) {
        await _playerStore.requireUsernamePublication(uid, revision, draft);
      }
      _playerStore.applyServerState(Map<String, dynamic>.from(state));
      lastSyncAt = DateTime.now();
      lastError = null;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> getPlayerState() =>
      api('/getPlayerState', const {});

  Future<String> deleteAccount({required bool confirmed}) async {
    if (!confirmed) throw const LunoApiException('confirmation-required', 400);
    if (_deletingAccount) throw const LunoApiException('deletion-busy', 409);
    if (_linkingGoogle) {
      throw const LunoApiException('account-link-in-progress', 409);
    }
    if (_signingInGoogle) {
      throw const LunoApiException('account-signin-in-progress', 409);
    }
    _deletingAccount = true;
    try {
      final alreadyDeleted = accountFailure?.code == 'account-deleted';
      if (!alreadyDeleted) await _ensureReadyForApi(resumeDeletion: true);
      final deletingUser = user;
      if (deletingUser == null) {
        throw const LunoApiException('auth-required', 401);
      }
      final revision = accountRevision;
      _deletionInFlight = true;
      void checkOwner() {
        if (_disposed ||
            user?.uid != deletingUser.uid ||
            accountRevision != revision) {
          throw const LunoApiException('session-changed', 409);
        }
      }

      _requestGeneration++;
      if (_bindsPlayerStore) _playerStore.invalidateServerStates();
      if (!alreadyDeleted && !deletingUser.isAnonymous) {
        if (!deletingUser.providerData.any(
          (entry) => entry.providerId == 'google.com',
        )) {
          throw const LunoApiException('reauth-provider-unavailable', 401);
        }
        final google = await _googleCredential();
        checkOwner();
        final credential = await deletingUser.reauthenticateWithCredential(
          google,
        );
        checkOwner();
        if (credential.user?.uid != deletingUser.uid) {
          throw const LunoApiException('session-changed', 409);
        }
      }
      checkOwner();
      try {
        if (!alreadyDeleted) {
          final result = await api('/deleteAccount', const {'confirm': true});
          if (result['ok'] != true || result['deleted'] != true) {
            throw const FormatException('Unconfirmed account deletion');
          }
        }
      } on LunoApiException catch (error) {
        if (error.code != 'account-deleted') rethrow;
      }
      // Deletion is authoritative even if the user switches during disk cleanup.
      _requestGeneration++;
      if (user?.uid == deletingUser.uid && accountRevision == revision) {
        ready = false;
        _lastFailure = const LunoApiException('account-deleted', 403);
        lastError = (_lastFailure as LunoApiException).accountAccessMessage;
        _clearActivityStreams();
        if (!_disposed) notifyListeners();
      }
      if (_bindsPlayerStore) {
        try {
          await _playerStore.eraseLocalAccount(deletingUser.uid);
        } catch (error) {
          if (kDebugMode) debugPrint('Deleted account cleanup pending: $error');
          throw const LunoApiException('account-deletion-local-cleanup', 0);
        }
      }
      if (user?.uid == deletingUser.uid && accountRevision == revision) {
        try {
          await _auth!.signOut();
        } catch (_) {
          throw const LunoApiException('account-deletion-signout-pending', 0);
        }
      }
      return deletingUser.uid;
    } finally {
      _deletionInFlight = false;
      _deletingAccount = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<Map<String, dynamic>> acceptLegalTerms() =>
      api('/acceptLegalTerms', const {});

  Future<Map<String, dynamic>> updateProfile(Map<String, dynamic> payload) =>
      api('/updateProfile', payload);

  Future<Map<String, dynamic>> changeUsername(String username) =>
      api('/changeUsername', {'username': normalizeUsernameValue(username)});

  Future<Map<String, dynamic>> setPieceSet(String pieceSet) =>
      updateProfile({'activePieceSet': pieceSet});

  Future<Map<String, dynamic>> updatePreferences({
    List<String>? deck,
    List<String>? emojiLoadout,
  }) => api('/updatePreferences', {
    if (deck != null) 'deck': deck,
    if (emojiLoadout != null) 'emojiLoadout': emojiLoadout,
  });

  Future<Map<String, dynamic>> claimDailyReward() =>
      api('/claimDailyReward', const {});

  Future<Map<String, dynamic>> claimOnboardingReward() =>
      api('/claimOnboardingReward', const {});

  Future<Map<String, dynamic>> claimMissionReward(
    String category,
    String missionId,
  ) => api('/claimMissionReward', {
    'category': category,
    'missionId': missionId,
  });

  Future<Map<String, dynamic>> claimAchievementReward(String achievementId) =>
      api('/claimAchievementReward', {'achievementId': achievementId});

  Future<Map<String, dynamic>> claimPassReward(int level, String track) =>
      api('/claimPassReward', {'level': level, 'track': track});

  Future<Map<String, dynamic>> claimSeasonReward() =>
      api('/claimSeasonReward', const {});

  Future<Map<String, dynamic>> claimSeasonPathReward(String tierId) =>
      api('/claimSeasonPathReward', {'tierId': tierId});

  Future<Map<String, dynamic>> purchaseSoftItem(String itemId) async {
    if (!_bindsPlayerStore) {
      return api('/purchaseSoftItem', {'itemId': itemId});
    }
    if (itemId == 'pass:premium') return _purchasePremiumPass();
    if (permanentPurchaseIdentity(itemId) == null) {
      throw ArgumentError('Invalid permanent item identity');
    }
    await _ensureReadyForApi();
    final owner = user?.uid;
    if (owner == null) throw const LunoApiException('auth-required', 401);
    final generation = _requestGeneration,
        key = (owner, _requestGeneration, itemId);
    final existing = _permanentPurchases[key];
    if (existing != null) return existing;
    void checkSession() {
      if (user?.uid != owner || generation != _requestGeneration) {
        throw const LunoApiException('session-changed', 409);
      }
      if (accountFailure != null) throw accountFailure!;
    }

    Future<Map<String, dynamic>> purchase() async {
      final requestId = await _playerStore.stagePermanentPurchase(
        owner,
        itemId,
        _requestId('/purchaseSoftItem'),
      );
      checkSession();
      late final Map<String, dynamic> result;
      try {
        result = await api('/purchaseSoftItem', {
          'itemId': itemId,
        }, requestIdOverride: requestId);
      } on LunoApiException catch (error) {
        if (error.status == 409 &&
            {'insufficient-balance', 'already-owned'}.contains(error.code)) {
          checkSession();
          await _playerStore.clearPermanentPurchase(owner, itemId, requestId);
        }
        rethrow;
      }
      checkSession();
      validatePermanentPurchaseResult(result, itemId);
      await _playerStore.clearPermanentPurchase(owner, itemId, requestId);
      checkSession();
      return result;
    }

    final operation = purchase();
    _permanentPurchases[key] = operation;
    try {
      return await operation;
    } finally {
      if (identical(_permanentPurchases[key], operation)) {
        _permanentPurchases.remove(key);
      }
    }
  }

  Future<Map<String, dynamic>> _purchasePremiumPass() async {
    await _ensureReadyForApi();
    final owner = user?.uid;
    if (owner == null) throw const LunoApiException('auth-required', 401);
    final generation = _requestGeneration, key = (owner, _requestGeneration);
    final existing = _premiumPurchases[key];
    if (existing != null) return existing;
    void checkSession() {
      if (user?.uid != owner || generation != _requestGeneration) {
        throw const LunoApiException('session-changed', 409);
      }
      if (accountFailure != null) throw accountFailure!;
    }

    Future<Map<String, dynamic>> purchase() async {
      var pending = await _playerStore.pendingPassPremiumPurchase(owner);
      checkSession();
      if (pending == null) {
        final snapshot = await getPlayerState();
        checkSession();
        final state = snapshot['state'],
            economy = state is Map ? state['economy'] : null;
        final periods = economy is Map ? economy['periods'] : null,
            pass = state is Map ? state['passState'] : null;
        final seasonId = periods is Map ? periods['seasonId'] : null;
        if (snapshot['ok'] != true ||
            !validPassPurchaseSeason(seasonId) ||
            pass is! Map ||
            pass['seasonKey'] != 'ranked-$seasonId-v2') {
          throw const FormatException('Missing authoritative Pass season');
        }
        pending = await _playerStore.stagePassPremiumPurchase(
          owner,
          PassPremiumPurchase(
            seasonId: seasonId as String,
            requestId: _requestId('/purchaseSoftItem'),
          ),
        );
        checkSession();
      }
      final intent = pending;
      late final Map<String, dynamic> result;
      try {
        result = await api('/purchaseSoftItem', {
          'itemId': 'pass:premium',
          'seasonId': intent.seasonId,
        }, requestIdOverride: intent.requestId);
      } on LunoApiException catch (error) {
        if (error.status == 409 &&
            {
              'insufficient-balance',
              'already-owned',
              'pass-season-changed',
            }.contains(error.code)) {
          checkSession();
          await _playerStore.clearPassPremiumPurchase(owner, intent);
        }
        rethrow;
      }
      checkSession();
      validatePassPremiumPurchaseResult(result, intent.seasonId);
      await _playerStore.clearPassPremiumPurchase(owner, intent);
      checkSession();
      return result;
    }

    final operation = purchase();
    _premiumPurchases[key] = operation;
    try {
      return await operation;
    } finally {
      if (identical(_premiumPurchases[key], operation)) {
        _premiumPurchases.remove(key);
      }
    }
  }

  Future<Map<String, dynamic>> upgradeCard(String family, int targetLevel) =>
      api('/upgradeCard', {'family': family, 'targetLevel': targetLevel});

  Future<Map<String, dynamic>> openChest(
    String chestId, {
    bool recoverPendingOnly = false,
  }) => _openRecoverableChest(
    chestId,
    fromPass: false,
    recoverPendingOnly: recoverPendingOnly,
  );

  Future<Map<String, dynamic>> openPassChest(String chestId) =>
      _openRecoverableChest(chestId, fromPass: true);

  Future<Map<String, dynamic>> _openRecoverableChest(
    String chestId, {
    required bool fromPass,
    bool recoverPendingOnly = false,
  }) async {
    final path = fromPass ? '/openPassChest' : '/openChest';
    if (!_bindsPlayerStore) {
      if (recoverPendingOnly) {
        throw StateError('Chest recovery needs an owned journal');
      }
      return api(path, {'chestId': chestId});
    }
    await _ensureReadyForApi();
    final owner = user?.uid;
    if (owner == null) throw const LunoApiException('auth-required', 401);
    final generation = _requestGeneration;
    final key = (owner, generation, path, chestId);
    final existing = _chestOpenings[key];
    if (existing != null) return existing;
    void checkSession() {
      if (user?.uid != owner || generation != _requestGeneration) {
        throw const LunoApiException('session-changed', 409);
      }
      if (accountFailure != null) throw accountFailure!;
    }

    Future<Map<String, dynamic>> open() async {
      final clear =
          fromPass
              ? _playerStore.clearPassChestRequest
              : _playerStore.clearShopChestRequest;
      final requestId =
          fromPass
              ? await _playerStore.stagePassChestRequest(
                owner,
                chestId,
                _requestId(path),
              )
              : await _playerStore.stageShopChestRequest(
                owner,
                chestId,
                _requestId(path),
                requireExisting: recoverPendingOnly,
              );
      checkSession();
      late final Map<String, dynamic> result;
      try {
        result = await api(path, {
          'chestId': chestId,
        }, requestIdOverride: requestId);
      } on LunoApiException catch (error) {
        // These terminal errors are returned only after durable receipt lookup.
        final unconsumed =
            fromPass
                ? error.code == 'pass-chest-not-owned'
                : error.code == 'insufficient-balance';
        if (unconsumed && error.status == 409) {
          checkSession();
          await clear(owner, chestId, requestId);
        }
        rethrow;
      }
      checkSession();
      if (fromPass) {
        validatePassActionResult(result, 'opened');
      } else {
        validateShopActionResult(result, outcome: 'opened');
        final purchaseId = result['transactionId'];
        final rewardIds = result['rewardTransactionIds'];
        if (result['chestId'] != chestId ||
            (result['rewards'] as List).isEmpty ||
            purchaseId is! String ||
            purchaseId.trim().isEmpty ||
            rewardIds is! List ||
            rewardIds.isEmpty ||
            rewardIds.toSet().length != rewardIds.length ||
            rewardIds.any((id) => id is! String || id.trim().isEmpty)) {
          throw const FormatException('Unconfirmed chest purchase receipt');
        }
      }
      await clear(owner, chestId, requestId);
      checkSession();
      return result;
    }

    final operation = open();
    _chestOpenings[key] = operation;
    try {
      return await operation;
    } finally {
      if (identical(_chestOpenings[key], operation)) {
        _chestOpenings.remove(key);
      }
    }
  }

  /// Open the selected Google account, never merge a guest into another UID.
  Future<String> signInGoogle({required bool confirmed}) async {
    if (!confirmed) throw const LunoApiException('confirmation-required', 400);
    if (_signingInGoogle ||
        _linkingGoogle ||
        _deletingAccount ||
        _deletionInFlight) {
      throw const LunoApiException('account-signin-in-progress', 409);
    }
    _signingInGoogle = true;
    int? restoredRevision;
    try {
      final startingUid = user?.uid;
      final startingRevision = accountRevision;
      final starting = _startFuture;
      if (starting != null) await starting.timeout(const Duration(seconds: 12));
      if (_disposed ||
          (startingUid != null &&
              (user?.uid != startingUid ||
                  accountRevision != startingRevision))) {
        throw const LunoApiException('session-changed', 409);
      }
      if (_auth == null) {
        if (_bootstrapOverride != null) {
          throw const LunoApiException('auth-required', 401);
        }
        try {
          await Firebase.initializeApp();
        } on FirebaseException catch (error) {
          if (error.code != 'duplicate-app') rethrow;
        }
        await _activateAppCheck();
        if (_disposed) throw const LunoApiException('session-changed', 409);
        _auth = FirebaseAuth.instance;
        if (_authSubscription == null) {
          _bindAuthChanges(_auth!.authStateChanges());
        }
      }
      final owner = (user?.uid, accountRevision);
      _choosingGoogleAccount = true;
      _authTransitioning = true;
      _requestGeneration++;
      _clearActivityStreams();
      if (_bindsPlayerStore) _playerStore.invalidateServerStates();
      ready = false;
      notifyListeners();
      final google = await _googleCredential();
      if (_disposed || owner != (user?.uid, accountRevision)) {
        throw const LunoApiException('session-changed', 409);
      }
      final result = await _auth!.signInWithCredential(google);
      final restored = result.user;
      if (_disposed ||
          restored == null ||
          user?.uid != restored.uid ||
          accountRevision > owner.$2 + 1) {
        throw const LunoApiException('session-changed', 409);
      }
      if (restored.isAnonymous ||
          !restored.providerData.any((p) => p.providerId == 'google.com')) {
        throw const LunoApiException('google-account-required', 401);
      }
      _choosingGoogleAccount = false;
      _observeAuthUser(restored);
      _user = restored;
      restoredRevision = accountRevision;
      void checkOwner() {
        if (_disposed ||
            user?.uid != restored.uid ||
            accountRevision != restoredRevision) {
          throw const LunoApiException('session-changed', 409);
        }
      }

      if (_bindsPlayerStore) {
        await _playerStore.bindAccount(restored.uid, restoreExisting: true);
      }
      checkOwner();
      await retry().timeout(const Duration(seconds: 15));
      checkOwner();
      if (!isOnline) {
        throw _lastFailure ?? const LunoApiException('network-unavailable', 0);
      }
      final response = await getPlayerState();
      checkOwner();
      final state = response['state'];
      if (state is! Map ||
          state['uid'] != restored.uid ||
          state['profile'] is! Map) {
        throw const FormatException('Unconfirmed restored player state');
      }
      if (_bindsPlayerStore) {
        _playerStore.applyServerState(Map<String, dynamic>.from(state));
        final profile = state['profile'] as Map;
        final username = profile['username'];
        if (profile['usernameGenerated'] == false &&
            username is String &&
            isUsernameShapeValid(username)) {
          await _playerStore.chooseUsername(username);
          checkOwner();
        }
      }
      lastSyncAt = DateTime.now();
      return restored.uid;
    } catch (error) {
      // A canceled native selector must not strand the unchanged guest offline.
      if (_choosingGoogleAccount && !_disposed) {
        _choosingGoogleAccount = false;
        _observeAuthUser(user);
        if (user != null) {
          try {
            await retry().timeout(const Duration(seconds: 15));
          } catch (recoveryError) {
            _markConnectionFailure(recoveryError);
          }
        }
      } else if (error is! LunoApiException ||
          error.code != 'session-changed') {
        ready = false;
        _markConnectionFailure(error);
      }
      rethrow;
    } finally {
      _choosingGoogleAccount = false;
      _signingInGoogle = false;
      final current = user;
      final needsRestart =
          !_disposed &&
          current != null &&
          ((restoredRevision != null && restoredRevision != accountRevision) ||
              (_bindsPlayerStore && _playerStore.accountUid != current.uid));
      _authTransitioning = needsRestart;
      if (!_disposed) {
        notifyListeners();
        if (needsRestart) {
          unawaited(_restartAfterAuthChange(accountRevision, current.uid));
        }
      }
    }
  }

  /// Link the native credential and confirm it for the same starting Firebase UID.
  Future<void> linkGoogle() async {
    if (_linkingGoogle) {
      throw const LunoApiException('account-link-in-progress', 409);
    }
    if (_deletingAccount) {
      throw const LunoApiException('account-deletion-in-progress', 409);
    }
    if (_signingInGoogle) {
      throw const LunoApiException('account-signin-in-progress', 409);
    }
    _linkingGoogle = true;
    try {
      await _ensureReadyForApi();
      final linkingUser = user;
      if (linkingUser == null) {
        throw const LunoApiException('auth-required', 401);
      }
      final revision = accountRevision;
      final generation = _requestGeneration;
      void checkOwner() {
        if (_disposed ||
            user?.uid != linkingUser.uid ||
            accountRevision != revision ||
            generation != _requestGeneration ||
            accountFailure != null) {
          throw const LunoApiException('session-changed', 409);
        }
      }

      var attemptId =
          _bindsPlayerStore
              ? await _playerStore.readGoogleLinkAttempt(linkingUser.uid)
              : null;
      checkOwner();
      var serverLinked = false;
      if (attemptId == null) {
        final prepared = await api('/prepareGoogleLink', const {});
        checkOwner();
        final id = prepared['attemptId'];
        if (prepared['ok'] != true ||
            id is! String ||
            !RegExp(r'^[a-f0-9]{32}$').hasMatch(id) ||
            prepared['alreadyLinked'] is! bool) {
          throw const FormatException('Unconfirmed Google link preparation');
        }
        attemptId = id;
        serverLinked = prepared['alreadyLinked'] == true;
        if (_bindsPlayerStore) {
          await _playerStore.writeGoogleLinkAttempt(linkingUser.uid, id);
        }
        checkOwner();
      }
      try {
        final alreadyLinked =
            serverLinked ||
            linkingUser.providerData.any(
              (provider) => provider.providerId == 'google.com',
            );
        if (!alreadyLinked) {
          final google = await _googleCredential();
          checkOwner();
          final credential = await linkingUser.linkWithCredential(google);
          checkOwner();
          if (credential.user?.uid != linkingUser.uid) {
            throw const LunoApiException('session-changed', 409);
          }
        }
        await linkingUser.getIdToken(true);
        checkOwner();
        final completed = await api('/completeGoogleLink', {
          'attemptId': attemptId,
        });
        checkOwner();
        final state = completed['state'];
        if (completed['ok'] != true ||
            completed['linked'] != true ||
            completed['uid'] != linkingUser.uid ||
            state is! Map ||
            state.isEmpty) {
          throw const FormatException('Unconfirmed Google link completion');
        }
        if (_bindsPlayerStore) {
          _playerStore.applyServerState(Map<String, dynamic>.from(state));
          checkOwner();
          try {
            await _playerStore.writeGoogleLinkAttempt(linkingUser.uid, null);
          } catch (error) {
            checkOwner();
            if (kDebugMode) {
              debugPrint('Confirmed Google link cleanup pending: $error');
            }
          }
          checkOwner();
        }
        lastSyncAt = DateTime.now();
      } on FirebaseAuthException catch (error) {
        checkOwner();
        if ({
          'credential-already-in-use',
          'email-already-in-use',
          'account-exists-with-different-credential',
        }.contains(error.code)) {
          try {
            await api('/recordGoogleLinkConflict', {
              'attemptId': attemptId,
              'reason': error.code,
            });
            checkOwner();
            if (_bindsPlayerStore) {
              await _playerStore.writeGoogleLinkAttempt(linkingUser.uid, null);
            }
          } catch (_) {
            checkOwner();
          }
        }
        rethrow;
      } on LunoApiException catch (error) {
        checkOwner();
        if (_bindsPlayerStore &&
            {
              'account-link-attempt-mismatch',
              'invalid-link-attempt',
            }.contains(error.code)) {
          await _playerStore.writeGoogleLinkAttempt(linkingUser.uid, null);
        }
        rethrow;
      }
    } finally {
      _linkingGoogle = false;
    }
  }

  Future<Map<String, dynamic>> enqueueRanked() =>
      api('/enqueueRanked', const {});

  Future<Map<String, dynamic>> cancelRankedQueue() =>
      api('/cancelRankedQueue', const {});

  Future<Map<String, dynamic>> getRankedMatch(String matchId) =>
      api('/getRankedMatch', {'matchId': matchId});

  Map<String, dynamic> get battleV1Client => {
    'platform': defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
    if (defaultTargetPlatform != TargetPlatform.android) 'build': 17,
    'protocolVersion': battleV1Protocol,
  };
  Future<Map<String, dynamic>> enqueueBattleV1() =>
      battleV1Api('/enqueueBattleV1', {'client': battleV1Client});
  Future<Map<String, dynamic>> getBattleV1(String matchId) => battleV1Api(
    '/getBattleV1',
    {'matchId': matchId, 'protocolVersion': battleV1Protocol},
  );
  Future<Map<String, dynamic>> cancelBattleV1Queue() => battleV1Api(
    '/cancelBattleV1Queue',
    {'protocolVersion': battleV1Protocol},
  );
  Future<Map<String, dynamic>> getBattleV1Deck() async {
    final owner = _battleDeckOwner;
    final write = _battleDeckWriteRevision;
    final read = ++_battleDeckReadRevision;
    final writing = _battleDeckSaveOwner == owner;
    final result = await battleV1Api('/getBattleV1Deck', {
      'client': battleV1Client,
    });
    final parsed = BattleDeckAccount.fromResponse(result);
    if (!_disposed &&
        owner == _battleDeckOwner &&
        owner.$1 != null &&
        write == _battleDeckWriteRevision &&
        read == _battleDeckReadRevision &&
        !writing &&
        _battleDeckSaveOwner != owner) {
      _battleDeckCache = parsed;
      _battleDeckCacheOwner = owner;
      notifyListeners();
    }
    return result;
  }

  /// AI may use a confirmed deck offline in this account session. After a
  /// restart it must reload; a missing cache must never select a different deck.
  Future<BattleDeckAccount> resolveAiBattleDeck() async {
    final owner = _battleDeckOwner;
    if (_disposed ||
        _authTransitioning ||
        owner.$1 == null ||
        accountFailure != null) {
      throw const LunoApiException('account-required', 401);
    }
    if (_battleDeckSaveOwner == owner) {
      throw const LunoApiException('deck-save-pending', 409);
    }
    final confirmed = cachedBattleDeck;
    if (confirmed != null) return confirmed;
    await getBattleV1Deck();
    if (_disposed ||
        owner != _battleDeckOwner ||
        _battleDeckSaveOwner == owner) {
      throw const LunoApiException('session-changed', 409);
    }
    final loaded = cachedBattleDeck;
    if (loaded == null) {
      throw const LunoApiException('deck-unavailable', 503);
    }
    return loaded;
  }

  Future<Map<String, dynamic>> setBattleV1Deck(List<String> deck) async {
    final submitted = List<String>.unmodifiable(deck);
    final cards = submitted.map(CardId.parse).toList();
    if (cards.length != 10 || cards.toSet().length != 10) {
      throw const FormatException('Invalid battle deck');
    }
    final owner = _battleDeckOwner;
    if (_battleDeckSaveOwner == owner) {
      throw StateError('Battle deck save already pending');
    }
    final previous = cachedBattleDeck;
    final write = ++_battleDeckWriteRevision;
    _battleDeckSaveOwner = owner;
    try {
      final result = await battleV1Api('/setBattleV1Deck', {
        'client': battleV1Client,
        'deck': submitted,
      });
      if (result['ok'] != true ||
          result['deck'] is! List ||
          !listEquals(result['deck'] as List, submitted)) {
        throw const FormatException('Unconfirmed battle deck save');
      }
      if (!_disposed &&
          owner == _battleDeckOwner &&
          owner.$1 != null &&
          write == _battleDeckWriteRevision &&
          previous != null &&
          previous.owned.containsAll(cards)) {
        _battleDeckCache = BattleDeckAccount(
          deck: List.unmodifiable(cards),
          owned: previous.owned,
          available: previous.available,
          progression: previous.progression,
        );
        _battleDeckCacheOwner = owner;
        notifyListeners();
      }
      return result;
    } finally {
      if (_battleDeckSaveOwner == owner) _battleDeckSaveOwner = null;
    }
  }

  Future<Map<String, dynamic>> battleV1Api(
    String path,
    Map<String, dynamic> body, {
    String? ownerUid,
    int? ownerRevision,
  }) async {
    final clockOwner = (user?.uid, accountRevision);
    try {
      var requestBody = body;
      final client = body['client'];
      if (defaultTargetPlatform == TargetPlatform.android && client is Map) {
        final identity = await _appReleaseIdentity();
        if (_disposed ||
            user?.uid != clockOwner.$1 ||
            accountRevision != clockOwner.$2) {
          throw const LunoApiException('session-changed', 409);
        }
        requestBody = {
          ...body,
          'client': {
            ...Map<String, dynamic>.from(client),
            'build': identity.buildNumber,
          },
        };
      }
      final response = await api(
        path,
        requestBody,
        ownerUid: ownerUid,
        ownerRevision: ownerRevision,
      );
      final serverNow = response['serverNow'], matchId = response['matchId'];
      if (clockOwner.$1 != null &&
          user?.uid == clockOwner.$1 &&
          accountRevision == clockOwner.$2 &&
          serverNow is int &&
          serverNow >= 0 &&
          matchId is String &&
          response['view'] is Map) {
        final key = (clockOwner.$1!, clockOwner.$2, matchId);
        final previous = battleV1ServerNow(matchId);
        _battleClockSamples[key] = (
          previous != null && previous > serverNow ? previous : serverNow,
          _battleClock.elapsedMilliseconds,
        );
        if (_battleClockSamples.length > 16) {
          _battleClockSamples.remove(_battleClockSamples.keys.first);
        }
      }
      return response;
    } on LunoApiException catch (e) {
      throw BattleV1Rejection(e.code);
    }
  }

  Future<Map<String, dynamic>> createBattleV1Room() =>
      battleV1Api('/createBattleV1Room', {'client': battleV1Client});
  Future<Map<String, dynamic>> joinBattleV1Room(String code) => battleV1Api(
    '/joinBattleV1Room',
    {'client': battleV1Client, 'roomCode': code},
  );
  Future<void> cancelBattleV1Room(String code) async {
    await battleV1Api('/cancelBattleV1Room', {
      'roomCode': code,
      'protocolVersion': battleV1Protocol,
    });
  }

  Future<String> sendBattleV1Invite(String uid) async {
    final result = await battleV1Api('/sendBattleV1Invite', {
      'client': battleV1Client,
      'targetUid': uid,
    });
    // V1 stores invitations by the player pair, not a legacy inviteId.
    final expiry = result['expiresAt'];
    if (result['ok'] != true ||
        result['sent'] != true ||
        result['status'] != 'pending' ||
        expiry is! int ||
        expiry <= 0) {
      throw const FormatException('Unconfirmed V1 invitation');
    }
    return 'sent';
  }

  Future<Map<String, dynamic>> respondBattleV1Invite(
    String uid, {
    required bool accept,
  }) async {
    final result = await battleV1Api('/respondBattleV1Invite', {
      'client': battleV1Client,
      'fromUid': uid,
      'accept': accept,
    });
    if (result['ok'] != true || result['accepted'] != accept) {
      throw const FormatException('Unconfirmed V1 invitation response');
    }
    if (accept) {
      final owner = user?.uid;
      if (owner == null) throw const BattleV1Rejection('session-changed');
      BattleV1Snapshot.fromResponse(result, owner);
    }
    return result;
  }

  Future<Map<String, dynamic>> submitMatchAction(
    Map<String, dynamic> payload,
  ) => api('/submitMatchAction', payload);

  Future<Map<String, dynamic>> heartbeatRankedMatch(String matchId) =>
      api('/heartbeatRankedMatch', {'matchId': matchId});

  Future<Map<String, dynamic>> sendRankedMessage(
    String matchId,
    String kind,
    String tab,
    String id,
  ) => api('/sendRankedMessage', {
    'matchId': matchId,
    'kind': kind,
    'tab': tab,
    'id': id,
  });

  Future<String> openDirectMessage(String targetUid) async {
    final result = await api('/openDirectMessage', {'targetUid': targetUid});
    return result['conversationId']?.toString() ?? '';
  }

  Future<Map<String, dynamic>> createFriendlyRoom({int durationMinutes = 5}) =>
      api('/createFriendlyRoom', {'durationMinutes': durationMinutes});

  Future<Map<String, dynamic>> joinFriendlyRoom(String roomCode) =>
      api('/joinFriendlyRoom', {'roomCode': roomCode});

  Future<void> cancelFriendlyRoom(String roomCode) async {
    await api('/cancelFriendlyRoom', {'roomCode': roomCode});
  }

  Future<String> sendMatchInvite(
    String targetUid, {
    int durationMinutes = 5,
  }) async {
    final result = await api('/sendMatchInvite', {
      'targetUid': targetUid,
      'durationMinutes': durationMinutes,
    });
    return matchInviteStatus(result);
  }

  Future<Map<String, dynamic>> respondMatchInvite(
    String fromUid, {
    required bool accept,
  }) async {
    final result = await api('/respondMatchInvite', {
      'fromUid': fromUid,
      'accept': accept,
    });
    validateMatchInviteResponse(result, accept: accept);
    return result;
  }

  Stream<List<Map<String, dynamic>>> matchInvitesStream() {
    final uid = user?.uid;
    if (uid == null) return Stream.value(const []);
    if (_matchInviteStreamOverride != null) {
      return _accountScopedRows(uid, _matchInviteStreamOverride);
    }
    final source = FirebaseDatabase.instance
        .ref('matchInvites/$uid')
        .onValue
        .map((event) {
          final raw = _asMap(event.snapshot.value);
          final rows = <Map<String, dynamic>>[];
          for (final entry in raw.entries) {
            final invite = _asMap(entry.value);
            if (invite['status']?.toString() != 'pending') continue;
            final fromUsername = usernameFromMap({
              'username': invite['fromUsername'],
              'name': invite['fromName'],
            });
            rows.add({
              'fromUid': invite['fromUid']?.toString() ?? entry.key,
              'fromName': fromUsername,
              'fromUsername': fromUsername,
              'fromAvatar': invite['fromAvatar']?.toString() ?? 'av_pawn',
              'fromCountry': invite['fromCountry']?.toString() ?? 'TR',
              'fromTrophies': _number(invite['fromTrophies']),
              'durationMinutes': _number(invite['durationMinutes']),
              'sentAt': _number(invite['sentAt']),
              'expiresAt': _number(invite['expiresAt']),
            });
          }
          rows.sort(
            (a, b) => _number(b['sentAt']).compareTo(_number(a['sentAt'])),
          );
          return rows;
        });
    return _accountScopedRows(uid, source);
  }

  Future<void> _restartAfterAuthChange(int revision, String uid) async {
    try {
      await _startFuture;
      if (_accountRevision != revision || user?.uid != uid) return;
      await retry();
    } finally {
      if (_accountRevision == revision) {
        _authTransitioning = false;
        notifyListeners();
      }
    }
  }

  Future<void> sendDirectMessage(String targetUid, String message) async {
    final result = await api('/sendDirectMessage', {
      'targetUid': targetUid,
      'text': message,
    });
    final messageId = result['messageId'];
    if (messageId is! String || messageId.trim().isEmpty) {
      throw const FormatException('Unconfirmed direct message');
    }
  }

  Future<bool> markDirectMessageRead(
    String targetUid, {
    String? lastMessageId,
  }) async {
    final body = <String, dynamic>{'targetUid': targetUid};
    if (lastMessageId != null) {
      if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(lastMessageId)) {
        throw const FormatException('Invalid direct-message receipt cursor');
      }
      body['lastMessageId'] = lastMessageId;
    }
    final result = await api('/markDirectMessageRead', body);
    final marked = result['marked'];
    if (marked is! bool) {
      throw const FormatException('Unconfirmed direct-message read');
    }
    return marked;
  }

  Future<void> markNotificationRead(String notificationId) {
    final id = notificationId.trim();
    if (id.isEmpty) return Future<void>.value();
    final key = (user?.uid, accountRevision, id);
    return _notificationReads.putIfAbsent(
      key,
      () => _markNotificationRead(key),
    );
  }

  Future<void> _markNotificationRead((String?, int, String) key) async {
    try {
      final result = await api('/markNotificationRead', {
        'notificationId': key.$3,
      });
      if (_disposed || user?.uid != key.$1 || accountRevision != key.$2) {
        throw const LunoApiException('session-changed', 0);
      }
      if (result['ok'] != true || result['updated'] is! bool) {
        throw const FormatException('Unconfirmed notification read');
      }
      if (_activityUid != key.$1) return;
      _notificationCache = [
        for (final row in _notificationCache)
          if (row['notificationId']?.toString() != key.$3)
            row
          else if (result['updated'] == true)
            {...row, 'read': true},
      ];
      notifyListeners();
    } finally {
      _notificationReads.remove(key);
    }
  }

  Future<Set<String>> markAllNotificationsRead() async {
    if (!_hasCurrentActivity) return const {};
    final uid = user?.uid;
    final revision = accountRevision;
    void requireOwner() {
      if (_disposed || user?.uid != uid || accountRevision != revision) {
        throw const LunoApiException('session-changed', 0);
      }
    }

    final ids =
        _notificationCache
            .where((row) => row['read'] != true)
            .map((row) => row['notificationId']?.toString().trim() ?? '')
            .where((id) => id.isNotEmpty)
            .toSet();
    for (final id in ids) {
      requireOwner();
      await markNotificationRead(id);
      requireOwner();
    }
    return ids;
  }

  Future<String> sendFriendRequest(String targetUid) async {
    final result = await api('/sendFriendRequest', {'targetUid': targetUid});
    return friendRequestStatus(result);
  }

  Future<void> respondFriendRequest(
    String fromUid, {
    required bool accept,
  }) async {
    final result = await api('/respondFriendRequest', {
      'fromUid': fromUid,
      'accept': accept,
    });
    validateFriendResponse(result, accept: accept);
  }

  Future<void> removeFriend(String targetUid) async {
    final result = await api('/removeFriend', {'targetUid': targetUid});
    validateFriendRemoval(result);
  }

  Stream<List<Map<String, dynamic>>> directMessageInboxStream() {
    final uid = user?.uid;
    if (uid == null) return Stream.value(const []);
    final source = FirebaseDatabase.instance.ref('dmInbox/$uid').onValue.map((
      event,
    ) {
      final raw = _asMap(event.snapshot.value);
      final rows = <Map<String, dynamic>>[];
      for (final entry in raw.entries) {
        final targetUid = entry.key.trim();
        if (targetUid.isEmpty) continue;
        final summary = _asMap(entry.value);
        if (summary.isEmpty) continue;
        final username = usernameFromMap(summary, fallback: 'Oyuncu');
        rows.add({
          'targetUid': targetUid,
          'name': username,
          'username': username,
          'last': summary['last']?.toString() ?? '',
          'unread': summary['unread'] == true,
          'ts': _number(summary['ts']),
        });
      }
      rows.sort((a, b) {
        final time = _number(b['ts']).compareTo(_number(a['ts']));
        if (time != 0) return time;
        return (a['targetUid']?.toString() ?? '').compareTo(
          b['targetUid']?.toString() ?? '',
        );
      });
      return rows;
    });
    return _accountScopedRows(uid, source);
  }

  Future<List<Map<String, dynamic>>> directMessages(String targetUid) =>
      _readUserData((uid, read) async {
        validateDirectMessageParticipants(uid, targetUid);
        final conversation = [uid, targetUid]..sort();
        final value = await read('dm/${conversation.join('_')}/msgs');
        return parseDirectMessageRows(
          value,
          viewerUid: uid,
          targetUid: targetUid,
        );
      });

  Future<Map<String, dynamic>> _socialSafetyRequest(
    String path,
    Map<String, dynamic> payload,
  ) async {
    final owner = user?.uid;
    final revision = accountRevision;
    if (owner == null) throw const LunoApiException('auth-required', 401);
    final target = payload['targetUid'];
    if (target != null &&
        (target is! String ||
            !isPublicPlayerUidValid(target) ||
            target == owner)) {
      throw const FormatException('Invalid safety target');
    }
    await start();
    if (user?.uid != owner || accountRevision != revision) {
      throw const LunoApiException('session-changed', 409);
    }
    return api(path, payload);
  }

  Future<void> blockPlayer(String targetUid) async {
    final result = await _socialSafetyRequest('/blockUser', {
      'targetUid': targetUid,
    });
    validateSocialBlockResult(result, targetUid: targetUid, blocked: true);
  }

  Future<void> unblockPlayer(String targetUid) async {
    final result = await _socialSafetyRequest('/unblockUser', {
      'targetUid': targetUid,
    });
    validateSocialBlockResult(result, targetUid: targetUid, blocked: false);
  }

  Future<BlockedPlayersPage> blockedPlayersPage({String? pageToken}) async {
    final owner = user?.uid;
    final revision = accountRevision;
    if (owner == null) throw const LunoApiException('auth-required', 401);
    if (pageToken != null) {
      BlockedPlayersPage.cursorKey(pageToken, owner);
    }
    final result = await _socialSafetyRequest('/listBlockedUsers', {
      if (pageToken != null) 'pageToken': pageToken,
    });
    if (user?.uid != owner ||
        accountRevision != revision ||
        accountFailure != null) {
      throw const LunoApiException('session-changed', 409);
    }
    return BlockedPlayersPage.fromResponse(
      result,
      ownerUid: owner,
      requestedToken: pageToken,
    );
  }

  Future<List<BlockedPlayer>> blockedPlayers() async {
    final owner = user?.uid, revision = accountRevision;
    final players = <BlockedPlayer>[],
        seenUids = <String>{},
        seenTokens = <String>{};
    String? token;
    for (var pageNumber = 0; pageNumber < 100; pageNumber++) {
      if (user?.uid != owner ||
          accountRevision != revision ||
          accountFailure != null) {
        throw const LunoApiException('session-changed', 409);
      }
      final page = await blockedPlayersPage(pageToken: token);
      if (user?.uid != owner ||
          accountRevision != revision ||
          accountFailure != null) {
        throw const LunoApiException('session-changed', 409);
      }
      for (final player in page.players) {
        if (!seenUids.add(player.uid)) {
          throw const FormatException('Duplicate blocked player across pages');
        }
        players.add(player);
      }
      token = page.nextPageToken;
      if (token == null) return List.unmodifiable(players);
      if (!seenTokens.add(token)) {
        throw const FormatException('Repeated blocked-list cursor');
      }
    }
    // Convenience reads fail explicitly at the request budget; the paged UI
    // remains able to reach further rows without a relationship count cap.
    throw const FormatException('Blocked-list request budget exceeded');
  }

  Future<void> reportPlayer(String targetUid, SocialReportReason reason) async {
    final result = await _socialSafetyRequest('/reportUser', {
      'targetUid': targetUid,
      'reason': reason.id,
    });
    validateSocialReportResult(result);
  }

  Future<void> reportDirectMessage(
    String targetUid,
    String messageId,
    SocialReportReason reason,
  ) async {
    if (!isPublicPlayerUidValid(messageId)) {
      throw const FormatException('Invalid report message ID');
    }
    final result = await _socialSafetyRequest('/reportMessage', {
      'targetUid': targetUid,
      'messageId': messageId,
      'reason': reason.id,
    });
    validateSocialReportResult(result);
  }

  Stream<List<Map<String, dynamic>>> directMessagesStream(String targetUid) {
    final uid = user?.uid;
    if (uid == null) return Stream.value(const []);
    validateDirectMessageParticipants(uid, targetUid);
    if (_directMessageStreamOverride != null) {
      return _accountScopedRows(uid, _directMessageStreamOverride(targetUid));
    }
    final conversation = [uid, targetUid]..sort();
    final source = FirebaseDatabase.instance
        .ref('dm/${conversation.join('_')}/msgs')
        .onValue
        .map(
          (event) => parseDirectMessageRows(
            event.snapshot.value,
            viewerUid: uid,
            targetUid: targetUid,
          ),
        );
    return _accountScopedRows(uid, source);
  }

  Future<List<Map<String, dynamic>>> friendRequests() =>
      _readUserData((uid, read) async {
        return _friendRequestRows(await read('friendRequests/$uid'));
      });

  Stream<List<Map<String, dynamic>>> friendRequestsStream() {
    final uid = user?.uid;
    if (uid == null) return Stream.value(const []);
    if (_friendRequestStreamOverride != null) {
      return _accountScopedRows(uid, _friendRequestStreamOverride);
    }
    final source = FirebaseDatabase.instance
        .ref('friendRequests/$uid')
        .onValue
        .map((event) => _friendRequestRows(event.snapshot.value));
    return _accountScopedRows(uid, source);
  }

  Stream<List<Map<String, dynamic>>> notificationsStream() {
    final uid = user?.uid;
    if (uid == null) return Stream.value(const []);
    final source = FirebaseDatabase.instance
        .ref('notifications/$uid')
        .onValue
        .map((event) {
          final raw = _asMap(event.snapshot.value);
          final rows = <Map<String, dynamic>>[];
          for (final entry in raw.entries) {
            final notification = _asMap(entry.value);
            rows.add({
              'notificationId': entry.key,
              'type': notification['type']?.toString() ?? 'general',
              'fromUid': notification['fromUid']?.toString() ?? '',
              'fromName': usernameFromMap({
                'username': notification['fromUsername'],
                'name': notification['fromName'],
              }, fallback: 'Oyuncu'),
              'message': notification['message']?.toString() ?? '',
              'read': notification['read'] == true,
              'ts': _number(notification['ts']),
            });
          }
          rows.sort((a, b) => _number(b['ts']).compareTo(_number(a['ts'])));
          return rows;
        });
    return _accountScopedRows(uid, source);
  }

  Stream<List<Map<String, dynamic>>> _accountScopedRows(
    String uid,
    Stream<List<Map<String, dynamic>>> source,
  ) {
    final revision = accountRevision;
    bool current() =>
        !_disposed &&
        !_deletionInFlight &&
        accountFailure == null &&
        user?.uid == uid &&
        accountRevision == revision;
    return source.transform(
      StreamTransformer<
        List<Map<String, dynamic>>,
        List<Map<String, dynamic>>
      >.fromHandlers(
        handleData: (rows, sink) => sink.add(current() ? rows : const []),
        handleError: (error, stack, sink) {
          if (current()) {
            sink.addError(error, stack);
          } else {
            sink.add(const []);
          }
        },
      ),
    );
  }

  List<Map<String, dynamic>> _friendRequestRows(Object? value) {
    final raw = _asMap(value);
    return raw.entries.map((entry) {
      final request = _asMap(entry.value);
      final fromUsername = usernameFromMap({
        'username': request['fromUsername'],
        'name': request['fromName'],
      });
      return <String, dynamic>{
        'fromUid': entry.key,
        'fromName': fromUsername,
        'fromUsername': fromUsername,
        'avatarEmoji': request['fromAvatar']?.toString() ?? 'av_pawn',
        'fromCountry': request['fromCountry']?.toString() ?? 'TR',
        'fromTrophies': _number(request['fromTrophies']),
        'sentAt': _number(request['sentAt']),
      };
    }).toList();
  }

  static const publicProfileReadTimeout = Duration(seconds: 12);

  Future<Map<String, dynamic>?> publicPlayerProfile(String targetUid) {
    if (!isPublicPlayerUidValid(targetUid)) {
      throw const FormatException('Invalid public player UID');
    }
    return _readUserData((_, read) async {
      // Injected database reads remain a test seam. Production rank reads
      // require the server's current identity and deletion/block checks.
      if (_databaseReadOverride != null) {
        return parsePublicPlayerProfile(
          targetUid,
          await read('publicProfiles/$targetUid'),
        );
      }
      try {
        final result = await api('/getPublicPlayerProfile', {
          'targetUid': targetUid,
          'protocolVersion': BattleV1Rank.protocolVersion,
        });
        final profile = result['profile'];
        if (result['ok'] != true ||
            profile is! Map ||
            !profile.containsKey('battleV1Rank')) {
          throw const FormatException('Invalid current public profile');
        }
        return parsePublicPlayerProfile(targetUid, profile);
      } on LunoApiException catch (error) {
        if (error.status == 404 && error.code == 'target-not-found') {
          return null;
        }
        rethrow;
      }
    }).timeout(publicProfileReadTimeout);
  }

  Future<List<Map<String, dynamic>>> friends() =>
      _readUserData((uid, read) async {
        if (_databaseReadOverride == null) {
          final seen = <String>{};
          final cursors = <String>{};
          final rows = <Map<String, dynamic>>[];
          String? pageToken;
          final revision = accountRevision;
          for (var page = 0; ; page++) {
            if (user?.uid != uid || accountRevision != revision) {
              throw const LunoApiException('session-changed', 409);
            }
            if (page >= 100) {
              throw const FormatException('Friend roster page limit exceeded');
            }
            final result = await api('/getFriends', {
              'protocolVersion': BattleV1Rank.protocolVersion,
              if (pageToken != null) 'pageToken': pageToken,
            });
            final values = result['results'];
            if (result['ok'] != true ||
                result['protocolVersion'] != BattleV1Rank.protocolVersion ||
                values is! List ||
                values.length > 100) {
              throw const FormatException('Invalid current friend roster');
            }
            for (final value in values) {
              if (value is! Map ||
                  value['uid'] is! String ||
                  value['uid'] == uid ||
                  !seen.add(value['uid'] as String) ||
                  !value.containsKey('battleV1Rank')) {
                throw const FormatException('Invalid current friend profile');
              }
              final profile = parsePublicPlayerProfile(
                value['uid'] as String,
                value,
              );
              if (profile == null) {
                throw const FormatException('Missing friend profile');
              }
              rows.add(profile);
            }
            final next = result['nextPageToken'];
            if (next == null) break;
            if (next is! String ||
                next.isEmpty ||
                next.length > 2048 ||
                !cursors.add(next)) {
              throw const FormatException('Invalid friend roster cursor');
            }
            pageToken = next;
          }
          _sortPublicPlayers(rows);
          return rows;
        }
        final value = await read('friends/$uid');
        final ids =
            _asMap(value).entries
                .where((entry) => entry.value == true || entry.value is Map)
                .map((entry) => entry.key)
                .where((id) => id != uid && isPublicPlayerUidValid(id))
                .toSet()
                .toList();
        final profiles = await Future.wait(
          ids.map((id) => read('publicProfiles/$id')),
        );
        final rows = <Map<String, dynamic>>[];
        for (var i = 0; i < profiles.length; i++) {
          final profile = parsePublicPlayerProfile(ids[i], profiles[i]);
          if (profile != null) rows.add(profile);
        }
        _sortPublicPlayers(rows);
        return rows;
      });

  void _sortPublicPlayers(List<Map<String, dynamic>> rows) {
    rows.sort((a, b) {
      final score = _number(b['trophies']).compareTo(_number(a['trophies']));
      if (score != 0) return score;
      final name = usernameFromMap(a).compareTo(usernameFromMap(b));
      if (name != 0) return name;
      return (a['uid']?.toString() ?? '').compareTo(b['uid']?.toString() ?? '');
    });
  }

  Future<(String, int)> _requireReadSession() async {
    if (accountFailure != null) throw accountFailure!;
    if (user == null) {
      await start();
    }
    if (accountFailure != null) throw accountFailure!;
    final current = user;
    if (current == null) throw const LunoApiException('auth-required', 401);
    return (current.uid, _requestGeneration);
  }

  Future<T> _readUserData<T>(
    Future<T> Function(String uid, Future<Object?> Function(String) read)
    action,
  ) async {
    final (uid, generation) = await _requireReadSession();
    void checkSession() {
      if (user?.uid != uid || generation != _requestGeneration) {
        throw const LunoApiException('session-changed', 409);
      }
      if (accountFailure != null) throw accountFailure!;
    }

    Future<Object?> read(String path) async {
      checkSession();
      final value =
          _databaseReadOverride != null
              ? await _databaseReadOverride(path)
              : (await FirebaseDatabase.instance.ref(path).get()).value;
      checkSession();
      return value;
    }

    try {
      checkSession();
      final result = await action(uid, read);
      checkSession();
      return result;
    } catch (_) {
      checkSession();
      rethrow;
    }
  }

  Map<String, dynamic> _asMap(Object? value) {
    if (value is! Map) return <String, dynamic>{};
    return value.map((key, value) => MapEntry(key.toString(), value));
  }

  int _number(Object? value) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? 0;

  Future<Map<String, dynamic>> api(
    String path,
    Map<String, dynamic> payload, {
    String? requestIdOverride,
    String? ownerUid,
    int? ownerRevision,
  }) async {
    if (_choosingGoogleAccount) {
      throw const LunoApiException('account-signin-in-progress', 409);
    }
    void assertOwner() {
      if (_disposed ||
          (ownerUid != null && this.user?.uid != ownerUid) ||
          (ownerRevision != null && accountRevision != ownerRevision)) {
        throw const LunoApiException('session-changed', 409);
      }
    }

    assertOwner();
    // One request identity must describe the same bytes across every retry.
    final encodedPayload = jsonEncode(payload);
    // Ekranlar açılış bootstrap'ından önce dokunursa aynı hazırlık Future'ını
    // paylaş; internetsiz açılışta ikinci bir bekleme zinciri oluşturma.
    final deletionRequest = path == '/deleteAccount';
    if (_deletionInFlight && !deletionRequest) {
      throw const LunoApiException('account-deletion-in-progress', 409);
    }
    await _ensureReadyForApi(resumeDeletion: deletionRequest);
    assertOwner();
    if (_deletionInFlight && !deletionRequest) {
      throw const LunoApiException('account-deletion-in-progress', 409);
    }
    final user = this.user;
    if (user == null) throw const LunoApiException('auth-required', 401);
    final generation = _requestGeneration;
    final stateEpoch = _bindsPlayerStore ? _playerStore.serverStateEpoch : null;
    void assertCurrentRequest() {
      assertOwner();
      if (generation != _requestGeneration || this.user?.uid != user.uid) {
        throw const LunoApiException('session-changed', 409);
      }
      if (accountFailure != null &&
          !(deletionRequest &&
              accountFailure?.code == 'account-deletion-in-progress')) {
        throw accountFailure!;
      }
      if (stateEpoch != null &&
          (_playerStore.serverStateEpoch != stateEpoch ||
              _playerStore.accountUid != user.uid)) {
        throw const LunoApiException('session-changed', 409);
      }
    }

    Object? lastFailure;
    // A retry after a timed-out response may happen after the server already
    // committed the mutation. Reusing the id keeps server idempotency intact.
    final requestId = requestIdOverride ?? _requestId(path);
    final fastRecovery = _bootstrapping || _recoveringConnection;
    final attemptLimit = fastRecovery ? 2 : 3;
    final requestTimeout =
        fastRecovery ? const Duration(seconds: 5) : const Duration(seconds: 12);
    for (var attempt = 0; attempt < attemptLimit; attempt++) {
      try {
        assertCurrentRequest();
        String? token;
        try {
          token = await user.getIdToken(attempt > 0).timeout(requestTimeout);
        } on FirebaseAuthException catch (error) {
          if (!_isInvalidCachedUser(error)) rethrow;
          final recovered = await _recoverInvalidCachedUser(
            user,
            generation,
            error,
          );
          unawaited(
            _restartAfterAuthChange(_accountRevision, recovered.$1.uid),
          );
          // Never replay an old account's read or mutation as the new guest.
          throw const LunoApiException('session-changed', 409);
        }
        assertCurrentRequest();
        if (token == null || token.isEmpty) {
          throw const LunoApiException('token-missing', 401);
        }
        final appCheckToken = await _appCheckToken().timeout(requestTimeout);
        assertCurrentRequest();
        final headers = <String, String>{
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
          'X-Luno-Request-Id': requestId,
        };
        if (appCheckToken != null && appCheckToken.isNotEmpty) {
          headers['X-Firebase-AppCheck'] = appCheckToken;
        }
        final response = await _client
            .post(
              Uri.parse('$apiBase$path'),
              headers: headers,
              body: encodedPayload,
            )
            .timeout(requestTimeout);
        assertCurrentRequest();
        Map<String, dynamic> decoded;
        try {
          decoded = _decode(response.body);
        } on FormatException {
          // Gateways may return HTML on outages; preserve the HTTP status.
          throw LunoApiException(
            'invalid-server-response',
            response.statusCode,
          );
        }
        if (response.statusCode >= 200 &&
            response.statusCode < 300 &&
            decoded['ok'] == true) {
          _markOnline();
          assertCurrentRequest();
          final state = decoded['state'];
          if (stateEpoch != null && state is Map) {
            decoded['state'] = <String, dynamic>{
              ...Map<String, dynamic>.from(state),
              GameStore.serverStateOwnerKey: user.uid,
              GameStore.serverStateEpochKey: stateEpoch,
            };
          }
          return decoded;
        }
        if (response.statusCode >= 200 &&
            response.statusCode < 300 &&
            decoded['ok'] != false) {
          throw LunoApiException(
            'invalid-server-response',
            response.statusCode,
          );
        }
        final code =
            decoded['error']?.toString() ?? 'http-${response.statusCode}';
        throw LunoApiException(code, response.statusCode);
      } catch (error) {
        assertCurrentRequest();
        lastFailure = error;
        if (error is LunoApiException && error.accountAccessMessage != null) {
          _markConnectionFailure(error);
          if (error.code == 'account-deleted' && _bindsPlayerStore) {
            await _playerStore.eraseLocalAccount(user.uid);
          }
        }
        if (attempt < attemptLimit - 1 && isRetryableFailure(error)) {
          await Future<void>.delayed(
            Duration(milliseconds: 500 * (attempt + 1)),
          );
          continue;
        }
        if (isRetryableFailure(error)) {
          _markConnectionFailure(error);
        }
        rethrow;
      }
    }
    throw lastFailure ?? const LunoApiException('network-error', 0);
  }

  Future<void> _ensureRemoteProfile() async {
    try {
      await refreshState();
    } on LunoApiException catch (error) {
      if (error.code != 'profile-not-found') rethrow;
      final uid = user!.uid;
      final revision = _playerStore.accountBindingRevision;
      final draft =
          _playerStore.hasChosenUsername
              ? _playerStore.data.username
              : _playerStore.pendingUsernameDraft;
      // Bootstrap reserves a server alias only. A chosen local name must go
      // through the consent-gated public username endpoint.
      final created = await api('/createGuestPlayer', const {});
      if (_bindsPlayerStore &&
          created['usernameGenerated'] == true &&
          created['uid'] == uid) {
        await _playerStore.requireUsernamePublication(uid, revision, draft);
      }
      await refreshState();
    }
  }

  @visibleForTesting
  Future<void> ensureRemoteProfileForTesting() => _ensureRemoteProfile();

  Future<void> _activateAppCheck() async {
    if (_appCheckActivated) return;
    try {
      await FirebaseAppCheck.instance.activate(
        providerAndroid:
            kDebugMode
                ? const AndroidDebugProvider()
                : const AndroidPlayIntegrityProvider(),
      );
      _appCheckActivated = true;
    } catch (error) {
      // Production API calls fail closed until Play Integrity/App Check is
      // configured correctly. Local/AI play remains available offline.
      if (kDebugMode) debugPrint('Firebase App Check unavailable: $error');
    }
  }

  Future<String?> _appCheckToken() async {
    if (_appCheckOverride != null) return _appCheckOverride();
    if (!_appCheckActivated) return null;
    try {
      // Missing or expired attestation is intentionally surfaced to the
      // strict production API instead of silently downgrading to Auth-only.
      return await FirebaseAppCheck.instance.getToken().timeout(
        const Duration(seconds: 3),
      );
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Firebase App Check token unavailable: $error');
      }
      return null;
    }
  }

  Map<String, dynamic> _decode(String body) {
    final value = jsonDecode(body);
    if (value is! Map) throw const FormatException('Invalid response envelope');
    return Map<String, dynamic>.from(value);
  }

  static bool isRetryableFailure(Object error) {
    if (error is LunoApiException) {
      return error.status == 0 ||
          error.status == 408 ||
          error.status == 429 ||
          error.status >= 500 ||
          (error.status == 401 &&
              const {
                'invalid-token',
                'token-expired',
                'auth/id-token-expired',
              }.contains(error.code));
    }
    if (error is TimeoutException || error is http.ClientException) return true;
    final text = error.toString().toLowerCase();
    return text.contains('timeout') ||
        text.contains('network') ||
        text.contains('socket') ||
        text.contains('abort') ||
        text.contains('failed host lookup') ||
        text.contains('connection reset') ||
        text.contains('connection closed') ||
        text.contains('network is unreachable');
  }

  void _markOnline() {
    if (accountFailure != null) return;
    final changed = lastError != null || (!loading && !ready);
    lastError = null;
    _lastFailure = null;
    if (!loading && !_bootstrapping) ready = true;
    if (changed) notifyListeners();
  }

  void _markConnectionFailure(Object error) {
    if (accountFailure != null) return;
    _lastFailure = error;
    if (_bindsPlayerStore &&
        error is LunoApiException &&
        error.accountAccessMessage != null) {
      _playerStore.invalidateServerStates();
    }
    final message = _friendlyError(error);
    final changed = lastError != message || ready;
    lastError = message;
    ready = false;
    if (changed) notifyListeners();
  }

  String _requestId(String path) {
    final safePath = path.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    return 'flutter-$safePath-$_requestInstance-${_requestCounter++}';
  }

  String _friendlyError(Object error) {
    if (error is LunoApiException && error.accountAccessMessage != null) {
      return error.accountAccessMessage!;
    }
    final text = error.toString().toLowerCase();
    if (text.contains('app-check') || text.contains('app check')) {
      return 'Güvenli uygulama doğrulaması tamamlanamadı. Play Store sürümünü ve bağlantını kontrol et.';
    }
    if (text.contains('operation-not-allowed')) {
      return 'Misafir oturumu Firebase tarafında kapalı.';
    }
    if (text.contains('profile-not-found')) {
      return 'Oyuncu profili oluşturulamadı.';
    }
    if (text.contains('timeout') ||
        text.contains('network') ||
        text.contains('socket') ||
        text.contains('connection') ||
        text.contains('host lookup')) {
      return 'Sunucuya bağlanılamadı.';
    }
    return 'Online servis hazır değil.';
  }
}
