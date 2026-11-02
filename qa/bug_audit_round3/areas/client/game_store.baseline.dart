import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/card_pool.dart';
import '../data/board_finishes.dart';
import '../data/rank_catalog.dart';
import '../data/pass.dart';
import '../data/pass_purchase.dart';
import '../data/permanent_purchase.dart';
import '../data/username.dart';
import '../engine/ai.dart';
import '../battle_v1/practice.dart';
import '../services/battle_v1_rank.dart';
import 'player_data.dart';

class ChestResult {
  final String ownedKey;
  final bool isNew;
  final int goldRefund; // çift çıktıysa altına çevrilir
  ChestResult(this.ownedKey, this.isNew, this.goldRefund);
}

class LocalAccountErasedException implements Exception {
  const LocalAccountErasedException();
}

class _LocalAccountErasure {
  final cleanupKeys = <String>{};
  int? departureRevision;
}

/// Tüm ekonomi/ilerleme durumu — kalıcı (shared_preferences) + ChangeNotifier.
class GameStore extends ChangeNotifier {
  GameStore._();
  static final GameStore instance = GameStore._();

  static const _key = 'luno_player_v1';
  static const _schemaVersionKey = 'luno_player_schema_v2';
  static const _schemaVersion = 2;
  static const _corruptSnapshotBackupKey = 'luno_player_corrupt_backup_v2';
  static const _usernameChosenKey = 'luno_username_chosen_v1';
  static const _tutorialCompletedKey = 'luno_tutorial_completed_v1';
  static const _tutorialStepKey = 'luno_tutorial_step_v1';
  static const tutorialStepCount = 10;
  static const introductionSchema = 1;
  static const introductionStepCount = 14;

  PlayerData data = PlayerData.initial();
  BattleV1Rank? _battleRank;
  BattleV1Rank? get battleRank => _battleRank;
  int get rankTrophies => _battleRank?.trophies ?? data.trophies;
  int get rankArenaIdx => _battleRank?.arenaIdx ?? data.arenaIdx;
  bool loaded = false;
  bool hasChosenUsername = false;
  String pendingUsernameDraft = '';
  bool hasCompletedTutorial = false;
  int tutorialStep = 0;
  int introductionStep = 0;
  int welcomeStep = 0;
  BattleLearningCheckpoint guidedLearning = const BattleLearningCheckpoint();
  static const welcomeStepCount = 3;
  // Retain V227 checkpoints for migration. Fresh onboarding uses one guided
  // lesson; the optional four-stage Academy has its own practiceStage.
  int onboardingBattleStage = 0;
  static const onboardingBattleCount = 3;
  int _readOnboardingBattleStage(Map<String, dynamic>? snapshot) {
    final stage = snapshot?['onboardingBattleStage'];
    return stage is int ? stage.clamp(0, onboardingBattleCount - 1) : 0;
  }

  int _readWelcomeStep(Map<String, dynamic>? snapshot) {
    final step = snapshot?['welcomeStep'];
    if (step is int) return step.clamp(0, welcomeStepCount);
    // Existing learners keep their position instead of receiving a new intro.
    if (snapshot?['tutorialCompleted'] == true ||
        _readOnboardingBattleStage(snapshot) > 0 ||
        _readIntroductionStep(snapshot) > 0 ||
        _parseTutorialStep(snapshot?['tutorialStep']) > 0 ||
        (snapshot?['firstSessionMatchesStarted'] is int &&
            (snapshot!['firstSessionMatchesStarted'] as int) > 0)) {
      return welcomeStepCount;
    }
    return 0;
  }

  int _firstSessionMatchesStarted = 0;
  bool firstSessionMatchCompleted = false;
  int get firstSessionMatchesStarted => _firstSessionMatchesStarted;
  @visibleForTesting
  set firstSessionMatchesStarted(int value) {
    _firstSessionMatchesStarted = value.clamp(0, 2);
    firstSessionMatchCompleted = value >= 2;
  }

  bool get needsFirstSessionMatch => !firstSessionMatchCompleted;
  String get firstSessionPhase =>
      firstSessionMatchCompleted
          ? (_firstSessionMatchesStarted >= 2
              ? 'secondStarted'
              : 'firstCompleted')
          : (_firstSessionMatchesStarted > 0 ? 'firstStarted' : 'none');
  int? practiceStage;
  bool get needsPractice => practiceStage != null && practiceStage! < 4;
  int? _readPracticeStage(Map<String, dynamic>? snapshot) {
    final stage = snapshot?['practiceStage'];
    return stage is int && stage >= 0 && stage <= 4 ? stage : null;
  }

  int _readIntroductionStep(Map<String, dynamic>? snapshot) {
    if (snapshot?['introductionSchema'] != introductionSchema) return 0;
    final step = snapshot?['introductionStep'];
    return step is int ? step.clamp(0, introductionStepCount - 1) : 0;
  }

  String _readUsernameDraft(Map<String, dynamic>? snapshot) {
    final raw = snapshot?['pendingUsernameDraft'];
    if (raw is! String) return '';
    final value = normalizeUsernameValue(raw);
    return isUsernameShapeValid(value) ? value : '';
  }

  int _readFirstSessionMatches(
    Map<String, dynamic>? snapshot,
    PlayerData player,
    bool tutorialCompleted,
  ) {
    final count = snapshot?['firstSessionMatchesStarted'];
    if (count is int) return count.clamp(player.gamesPlayed > 0 ? 1 : 0, 2);
    return tutorialCompleted || player.gamesPlayed > 0 ? 2 : 0;
  }

  bool _readFirstSessionCompleted(
    Map<String, dynamic>? snapshot,
    PlayerData player,
    bool tutorialCompleted,
  ) {
    final completed = snapshot?['firstSessionMatchCompleted'];
    if (completed is bool) return completed || player.gamesPlayed > 0;
    // A V214 start count is not evidence that any of those attempts ended.
    if (snapshot?['firstSessionMatchesStarted'] is int) {
      return player.gamesPlayed > 0;
    }
    return player.gamesPlayed > 0 || tutorialCompleted;
  }

  BattleV1Rank? _readBattleRank(Map<String, dynamic>? snapshot, String? uid) {
    if (uid == null || snapshot?['battleV1Rank'] == null) return null;
    try {
      return BattleV1Rank.fromJson(snapshot!['battleV1Rank'], expectedUid: uid);
    } on FormatException {
      return null;
    }
  }

  /// Local journey bookkeeping only; never a reward, rating or match authority.
  int recordFirstSessionMatchStart(int revision) {
    if (!loaded ||
        revision != _accountBindingRevision ||
        (firstSessionMatchCompleted && _firstSessionMatchesStarted >= 2)) {
      return 0;
    }
    _firstSessionMatchesStarted = firstSessionMatchCompleted ? 2 : 1;
    _commit();
    return firstSessionMatchesStarted;
  }

  /// Journey state only. Permanent rewards are exclusively server-owned.
  bool recordFirstSessionMatchCompletion(int revision) {
    if (!loaded ||
        revision != _accountBindingRevision ||
        firstSessionMatchCompleted ||
        _firstSessionMatchesStarted == 0) {
      return false;
    }
    firstSessionMatchCompleted = true;
    _commit();
    return true;
  }

  String? accountUid;
  bool _accountOwnerKnown = false;
  static const serverStateOwnerKey = '_lunoLocalOwner';
  static const serverStateEpochKey = '_lunoLocalEpoch';
  int _serverStateEpoch = 0;
  int? _lastServerStateRevision;
  int? _lastServerStateObservedAt;
  int _accountBindingRevision = 0;
  final _erasedAccountUids = <String>{};
  final _pendingAccountErasures = <String, _LocalAccountErasure>{};
  int get accountBindingRevision => _accountBindingRevision;
  int get serverStateEpoch => _serverStateEpoch;

  /// Invalidate responses already delivered to a screen but not yet applied.
  void invalidateServerStates() {
    _serverStateEpoch++;
    _lastServerStateRevision = null;
    _lastServerStateObservedAt = null;
  }

  Future<void> _accountQueue = Future<void>.value();
  final Random _rng = Random();
  Future<void>? _loadFuture;
  String? _pendingSnapshot;
  bool _hasUnsavedSnapshot = false;
  Completer<void>? _saveCompleter;
  bool _drainingSaves = false;
  Future<void> _auxiliaryWriteQueue = Future<void>.value();

  Future<void> load() => _loadFuture ??= _loadInternal();

  @visibleForTesting
  static GameStore createForTesting() => GameStore._();

  Future<void> _loadInternal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      final rawSchema = prefs.get(_schemaVersionKey);
      final storedSchema = rawSchema is int ? rawSchema : 1;
      Map<String, dynamic>? decoded;
      var needsRepair = storedSchema != _schemaVersion;
      if (raw != null) {
        try {
          final value = jsonDecode(raw);
          if (value is Map) {
            decoded = Map<String, dynamic>.from(value);
            _accountOwnerKnown = decoded.containsKey('accountUid');
            accountUid =
                decoded['accountUid'] is String
                    ? decoded['accountUid'] as String
                    : null;
            data = PlayerData.fromJson(decoded);
          } else {
            needsRepair = true;
          }
        } catch (_) {
          needsRepair = true;
          // Keep one bounded forensic copy before replacing a damaged file.
          if (raw.length <= 200000) {
            try {
              await prefs.setString(_corruptSnapshotBackupKey, raw);
            } catch (_) {}
          }
        }
      }
      if (raw == null || decoded == null) data = PlayerData.initial();

      _restoreAccountErasures(prefs);
      if (accountUid != null && _isAccountErased(prefs, accountUid!)) {
        final erasedUid = accountUid!;
        _erasedAccountUids.add(erasedUid);
        _pendingAccountErasures.putIfAbsent(
          erasedUid,
          _LocalAccountErasure.new,
        );
        data = PlayerData.initial();
        accountUid = null;
        _accountOwnerKnown = true;
        decoded = {
          ...data.toJson(),
          'accountUid': null,
          'usernameChosen': false,
          'tutorialCompleted': false,
          'tutorialStep': 0,
        };
        needsRepair = true;
      }

      hasChosenUsername = _readChosenUsername(prefs, decoded);
      pendingUsernameDraft = _readUsernameDraft(decoded);
      hasCompletedTutorial = _readTutorialCompleted(prefs, decoded);
      tutorialStep = _readTutorialStep(prefs, decoded);
      introductionStep = _readIntroductionStep(decoded);
      welcomeStep = _readWelcomeStep(decoded);
      guidedLearning = BattleLearningCheckpoint.fromJson(
        decoded?['guidedLearning'],
      );
      onboardingBattleStage = _readOnboardingBattleStage(decoded);
      _firstSessionMatchesStarted = _readFirstSessionMatches(
        decoded,
        data,
        hasCompletedTutorial,
      );
      firstSessionMatchCompleted = _readFirstSessionCompleted(
        decoded,
        data,
        hasCompletedTutorial,
      );
      practiceStage = _readPracticeStage(decoded);
      _battleRank = _readBattleRank(decoded, accountUid);
      if (decoded != null) {
        needsRepair = needsRepair || jsonEncode(_localSnapshot()) != raw;
      }

      // A clean install keeps untouched defaults. An update gets one
      // idempotent migration write, preserving the user's progress.
      if (needsRepair && raw != null) await _persistSnapshot(prefs);
    } catch (_) {
      // A broken/temporarily unavailable local store must never block guest
      // startup. The next successful save repairs the local snapshot.
      data = PlayerData.initial();
      _battleRank = null;
      hasChosenUsername = false;
      pendingUsernameDraft = '';
      accountUid = null;
      _accountOwnerKnown = false;
      hasCompletedTutorial = false;
      tutorialStep = 0;
      introductionStep = 0;
      welcomeStep = 0;
      guidedLearning = const BattleLearningCheckpoint();
      onboardingBattleStage = 0;
      firstSessionMatchesStarted = 0;
      practiceStage = null;
    }
    loaded = true;
    notifyListeners();
  }

  bool _readChosenUsername(
    SharedPreferences prefs,
    Map<String, dynamic>? snapshot,
  ) {
    if (snapshot?.containsKey('accountUid') == true) {
      return snapshot?['usernameChosen'] == true;
    }
    final auxiliary = prefs.get(_usernameChosenKey);
    if (auxiliary is bool) return auxiliary;
    final stored =
        snapshot?['usernameChosen'] ?? snapshot?['hasChosenUsername'];
    if (stored is bool) return stored;
    final username = snapshot?['username'];
    if (username is! String) return false;
    return normalizeUsernameValue(username) !=
        normalizeUsernameValue(PlayerData.initial().username);
  }

  bool _readTutorialCompleted(
    SharedPreferences prefs,
    Map<String, dynamic>? snapshot,
  ) {
    if (snapshot?.containsKey('accountUid') == true) {
      return snapshot?['tutorialCompleted'] == true;
    }
    final auxiliary = prefs.get(_tutorialCompletedKey);
    if (auxiliary is bool) return auxiliary;
    return snapshot?['tutorialCompleted'] == true ||
        snapshot?['tutorialDone'] == true;
  }

  int _readTutorialStep(
    SharedPreferences prefs,
    Map<String, dynamic>? snapshot,
  ) {
    final fromSnapshot = snapshot?['tutorialStep'];
    final auxiliary = prefs.get(_tutorialStepKey);
    final stored =
        snapshot?.containsKey('accountUid') == true
            ? fromSnapshot
            : auxiliary is num && auxiliary.isFinite
            ? auxiliary
            : fromSnapshot;
    return _parseTutorialStep(stored);
  }

  static int _parseTutorialStep(Object? stored) =>
      (stored is num && stored.isFinite ? stored.toInt() : 0)
          .clamp(0, tutorialStepCount - 1)
          .toInt();

  Future<void> _persistSnapshot(SharedPreferences prefs) async {
    try {
      _hasUnsavedSnapshot =
          !(await prefs.setString(_key, jsonEncode(_localSnapshot())) &&
              await prefs.setInt(_schemaVersionKey, _schemaVersion) &&
              await prefs.setBool(_usernameChosenKey, hasChosenUsername) &&
              await prefs.setBool(
                _tutorialCompletedKey,
                hasCompletedTutorial,
              ) &&
              await prefs.setInt(_tutorialStepKey, tutorialStep));
    } catch (_) {
      // Persistence is best-effort; the next successful state change retries.
      _hasUnsavedSnapshot = true;
    }
  }

  Map<String, dynamic> _localSnapshot() => {
    ...data.toJson(),
    // Match the reload parser so clean defaults do not need another repair.
    'username': normalizeUsernameValue(data.username),
    'schemaVersion': _schemaVersion,
    if (_accountOwnerKnown) 'accountUid': accountUid,
    if (_battleRank != null) 'battleV1Rank': _battleRank!.toJson(),
    'usernameChosen': hasChosenUsername,
    'pendingUsernameDraft': pendingUsernameDraft,
    'tutorialCompleted': hasCompletedTutorial,
    'tutorialStep': tutorialStep,
    'introductionSchema': introductionSchema,
    'introductionStep': introductionStep,
    'welcomeStep': welcomeStep,
    'guidedLearning': guidedLearning.toJson(),
    'onboardingBattleStage': onboardingBattleStage,
    'firstSessionMatchesStarted': firstSessionMatchesStarted,
    'firstSessionMatchCompleted': firstSessionMatchCompleted,
    'practiceStage': practiceStage,
  };

  static String _accountKey(String uid) =>
      'luno_account_v1_${base64Url.encode(utf8.encode(uid))}';
  static String _erasedAccountKey(String uid) => '${_accountKey(uid)}_erased';

  bool _isAccountErased(SharedPreferences prefs, String uid) =>
      _erasedAccountUids.contains(uid) ||
      prefs.get(_erasedAccountKey(uid)) == true;

  void _restoreAccountErasures(SharedPreferences prefs) {
    const prefix = 'luno_account_v1_';
    const suffix = '_erased';
    for (final key in prefs.getKeys()) {
      if (!key.startsWith(prefix) ||
          !key.endsWith(suffix) ||
          key.length <= prefix.length + suffix.length ||
          prefs.get(key) != true) {
        continue;
      }
      String uid;
      try {
        uid = utf8.decode(
          base64Url.decode(
            key.substring(prefix.length, key.length - suffix.length),
          ),
        );
      } on FormatException {
        continue;
      }
      if (uid.trim().isEmpty ||
          uid.length > 128 ||
          _erasedAccountKey(uid) != key) {
        continue;
      }
      _erasedAccountUids.add(uid);
      final keys = _accountErasureKeys(prefs, uid);
      if (keys.any(prefs.containsKey)) {
        _pendingAccountErasures
            .putIfAbsent(uid, _LocalAccountErasure.new)
            .cleanupKeys
            .addAll(keys);
      }
    }
  }

  static const _chestKinds = {'common', 'rare', 'legendary', 'royal'};
  static String _chestRequestKey(
    String uid,
    String chestId, {
    required bool fromPass,
  }) =>
      '${_accountKey(uid)}_pending_${fromPass ? 'pass' : 'shop'}_chest_$chestId';

  Future<List<String>> pendingPassChestRequestKinds(String uid) =>
      _pendingChestRequestKinds(uid, fromPass: true);

  Future<List<String>> pendingShopChestRequestKinds(String uid) =>
      _pendingChestRequestKinds(uid, fromPass: false);

  Future<List<String>> _pendingChestRequestKinds(
    String uid, {
    required bool fromPass,
  }) {
    if (uid.trim().isEmpty || uid.length > 128) {
      return Future.error(ArgumentError('Invalid Pass chest account'));
    }
    final operation = _accountQueue.then((_) async {
      if (!loaded) await load();
      final prefs = await SharedPreferences.getInstance();
      if (accountUid != uid || _isAccountErased(prefs, uid)) {
        return <String>[];
      }
      final pending = <String>[];
      for (final kind in _chestKinds) {
        final requestId = prefs.getString(
          _chestRequestKey(uid, kind, fromPass: fromPass),
        );
        if (requestId == null) continue;
        if (!RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(requestId)) {
          throw StateError('Invalid pending Pass chest request');
        }
        pending.add(kind);
      }
      return pending;
    });
    _accountQueue = operation.then<void>((_) {}, onError: (Object _) {});
    return operation;
  }

  Future<String> stagePassChestRequest(
    String uid,
    String chestId,
    String candidate,
  ) => _stageChestRequest(uid, chestId, candidate, fromPass: true);

  Future<String> stageShopChestRequest(
    String uid,
    String chestId,
    String candidate, {
    bool requireExisting = false,
  }) => _stageChestRequest(
    uid,
    chestId,
    candidate,
    fromPass: false,
    requireExisting: requireExisting,
  );

  Future<String> _stageChestRequest(
    String uid,
    String chestId,
    String candidate, {
    required bool fromPass,
    bool requireExisting = false,
  }) {
    final validId = RegExp(r'^[a-zA-Z0-9_-]{1,128}$');
    if (uid.trim().isEmpty ||
        uid.length > 128 ||
        !_chestKinds.contains(chestId) ||
        !validId.hasMatch(candidate)) {
      return Future.error(ArgumentError('Invalid Pass chest request'));
    }
    final operation = _accountQueue.then((_) async {
      await load();
      final prefs = await SharedPreferences.getInstance();
      if (accountUid != uid || _isAccountErased(prefs, uid)) {
        throw StateError('Pass chest account changed');
      }
      final key = _chestRequestKey(uid, chestId, fromPass: fromPass);
      final existing = prefs.getString(key);
      if (existing != null) {
        if (!validId.hasMatch(existing)) {
          throw StateError('Invalid pending Pass chest request');
        }
        return existing;
      }
      if (requireExisting) {
        throw StateError('Pending shop chest receipt no longer exists');
      }
      if (!await prefs.setString(key, candidate)) {
        throw StateError('Could not persist Pass chest request');
      }
      return candidate;
    });
    _accountQueue = operation.then<void>((_) {}, onError: (Object _) {});
    return operation;
  }

  Future<void> clearPassChestRequest(
    String uid,
    String chestId,
    String requestId,
  ) => _clearChestRequest(uid, chestId, requestId, fromPass: true);

  Future<void> clearShopChestRequest(
    String uid,
    String chestId,
    String requestId,
  ) => _clearChestRequest(uid, chestId, requestId, fromPass: false);

  Future<void> _clearChestRequest(
    String uid,
    String chestId,
    String requestId, {
    required bool fromPass,
  }) {
    if (uid.trim().isEmpty ||
        uid.length > 128 ||
        !_chestKinds.contains(chestId) ||
        !RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(requestId)) {
      return Future.error(ArgumentError('Invalid Pass chest request'));
    }
    final operation = _accountQueue.then((_) async {
      await load();
      final prefs = await SharedPreferences.getInstance();
      if (accountUid != uid || _isAccountErased(prefs, uid)) {
        throw StateError('Pass chest account changed');
      }
      final key = _chestRequestKey(uid, chestId, fromPass: fromPass);
      if (prefs.getString(key) == requestId && !await prefs.remove(key)) {
        throw StateError('Could not clear Pass chest request');
      }
    });
    _accountQueue = operation.catchError((Object _) {});
    return operation;
  }

  static String _permanentPurchaseKey(String uid) =>
      '${_accountKey(uid)}_pending_permanent_purchases';

  Map<String, String> _permanentPurchaseRequests(
    SharedPreferences prefs,
    String uid,
  ) {
    final raw = prefs.getString(_permanentPurchaseKey(uid));
    if (raw == null) return <String, String>{};
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      throw StateError('Invalid pending purchase journal');
    }
    if (decoded is! Map || decoded.length > 128) {
      throw StateError('Invalid pending purchase journal');
    }
    final requests = <String, String>{};
    for (final entry in decoded.entries) {
      final item = entry.key, request = entry.value;
      if (item is! String ||
          permanentPurchaseIdentity(item) == null ||
          request is! String ||
          !RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(request)) {
        throw StateError('Invalid pending purchase journal');
      }
      requests[item] = request;
    }
    return requests;
  }

  Future<List<String>> pendingPermanentPurchaseItems(String uid) {
    if (uid.trim().isEmpty || uid.length > 128) {
      return Future.error(ArgumentError('Invalid purchase account'));
    }
    final operation = _accountQueue.then((_) async {
      if (!loaded) await load();
      final prefs = await SharedPreferences.getInstance();
      if (accountUid != uid || _isAccountErased(prefs, uid)) {
        return <String>[];
      }
      return _permanentPurchaseRequests(prefs, uid).keys.toList()..sort();
    });
    _accountQueue = operation.then<void>((_) {}, onError: (Object _) {});
    return operation;
  }

  Future<String> stagePermanentPurchase(
    String uid,
    String itemId,
    String candidate,
  ) {
    if (uid.trim().isEmpty ||
        uid.length > 128 ||
        permanentPurchaseIdentity(itemId) == null ||
        !RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(candidate)) {
      return Future.error(ArgumentError('Invalid permanent purchase'));
    }
    final operation = _accountQueue.then((_) async {
      await load();
      final prefs = await SharedPreferences.getInstance();
      if (accountUid != uid || _isAccountErased(prefs, uid)) {
        throw StateError('Purchase account changed');
      }
      final requests = _permanentPurchaseRequests(prefs, uid);
      final existing = requests[itemId];
      if (existing != null) return existing;
      if (requests.length >= 128) throw StateError('Purchase journal is full');
      requests[itemId] = candidate;
      if (!await prefs.setString(
        _permanentPurchaseKey(uid),
        jsonEncode(requests),
      )) {
        throw StateError('Could not persist purchase request');
      }
      return candidate;
    });
    _accountQueue = operation.then<void>((_) {}, onError: (Object _) {});
    return operation;
  }

  Future<void> clearPermanentPurchase(
    String uid,
    String itemId,
    String requestId,
  ) {
    if (uid.trim().isEmpty ||
        uid.length > 128 ||
        permanentPurchaseIdentity(itemId) == null ||
        !RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(requestId)) {
      return Future.error(ArgumentError('Invalid permanent purchase'));
    }
    final operation = _accountQueue.then((_) async {
      await load();
      final prefs = await SharedPreferences.getInstance();
      if (accountUid != uid || _isAccountErased(prefs, uid)) {
        throw StateError('Purchase account changed');
      }
      final requests = _permanentPurchaseRequests(prefs, uid);
      if (requests[itemId] != requestId) return;
      requests.remove(itemId);
      final persisted =
          requests.isEmpty
              ? await prefs.remove(_permanentPurchaseKey(uid))
              : await prefs.setString(
                _permanentPurchaseKey(uid),
                jsonEncode(requests),
              );
      if (!persisted) throw StateError('Could not clear purchase request');
    });
    _accountQueue = operation.catchError((Object _) {});
    return operation;
  }

  static String _passPremiumPurchaseKey(String uid) =>
      '${_accountKey(uid)}_pending_pass_premium_purchase';

  PassPremiumPurchase? _readPassPremiumPurchase(
    SharedPreferences prefs,
    String uid,
  ) {
    final raw = prefs.getString(_passPremiumPurchaseKey(uid));
    if (raw == null) return null;
    try {
      if (raw.length > 1024) {
        throw const FormatException('Oversized Premium journal');
      }
      return PassPremiumPurchase.fromJson(jsonDecode(raw));
    } catch (_) {
      throw StateError('Invalid Premium purchase journal');
    }
  }

  Future<PassPremiumPurchase?> pendingPassPremiumPurchase(String uid) {
    if (uid.trim().isEmpty || uid.length > 128) {
      return Future.error(ArgumentError('Invalid purchase account'));
    }
    final operation = _accountQueue.then((_) async {
      if (!loaded) await load();
      final prefs = await SharedPreferences.getInstance();
      if (accountUid != uid || _isAccountErased(prefs, uid)) {
        return null;
      }
      return _readPassPremiumPurchase(prefs, uid);
    });
    _accountQueue = operation.then<void>((_) {}, onError: (Object _) {});
    return operation;
  }

  Future<PassPremiumPurchase> stagePassPremiumPurchase(
    String uid,
    PassPremiumPurchase candidate,
  ) {
    if (uid.trim().isEmpty || uid.length > 128 || !candidate.isValid) {
      return Future.error(ArgumentError('Invalid Premium purchase'));
    }
    final operation = _accountQueue.then((_) async {
      await load();
      final prefs = await SharedPreferences.getInstance();
      if (accountUid != uid || _isAccountErased(prefs, uid)) {
        throw StateError('Purchase account changed');
      }
      final existing = _readPassPremiumPurchase(prefs, uid);
      if (existing != null) return existing;
      if (!await prefs.setString(
        _passPremiumPurchaseKey(uid),
        jsonEncode(candidate.toJson()),
      )) {
        throw StateError('Could not persist Premium purchase');
      }
      return candidate;
    });
    _accountQueue = operation.then<void>((_) {}, onError: (Object _) {});
    return operation;
  }

  Future<void> clearPassPremiumPurchase(
    String uid,
    PassPremiumPurchase confirmed,
  ) {
    if (uid.trim().isEmpty || uid.length > 128 || !confirmed.isValid) {
      return Future.error(ArgumentError('Invalid Premium purchase'));
    }
    final operation = _accountQueue.then((_) async {
      await load();
      final prefs = await SharedPreferences.getInstance();
      if (accountUid != uid || _isAccountErased(prefs, uid)) {
        throw StateError('Purchase account changed');
      }
      final existing = _readPassPremiumPurchase(prefs, uid);
      if (existing?.seasonId != confirmed.seasonId ||
          existing?.requestId != confirmed.requestId) {
        return;
      }
      if (!await prefs.remove(_passPremiumPurchaseKey(uid))) {
        throw StateError('Could not clear Premium purchase');
      }
    });
    _accountQueue = operation.catchError((Object _) {});
    return operation;
  }

  Future<String?> readGoogleLinkAttempt(String uid) async {
    await load();
    final prefs = await SharedPreferences.getInstance();
    if (accountUid != uid || _isAccountErased(prefs, uid)) {
      return null;
    }
    final value = prefs.getString('${_accountKey(uid)}_google_link');
    return value != null && RegExp(r'^[a-f0-9]{32}$').hasMatch(value)
        ? value
        : null;
  }

  Future<void> writeGoogleLinkAttempt(String uid, String? attemptId) {
    if (uid.trim().isEmpty ||
        uid.length > 128 ||
        (attemptId != null && !RegExp(r'^[a-f0-9]{32}$').hasMatch(attemptId))) {
      return Future.error(
        ArgumentError('Invalid Google link ownership or attempt'),
      );
    }
    final operation = _accountQueue.then((_) async {
      await load();
      final prefs = await SharedPreferences.getInstance();
      if (accountUid != uid || _isAccountErased(prefs, uid)) {
        throw StateError('Google link account changed');
      }
      final key = '${_accountKey(uid)}_google_link';
      final stored =
          attemptId == null
              ? await prefs.remove(key)
              : await prefs.setString(key, attemptId);
      if (!stored) throw StateError('Could not persist Google link attempt');
    });
    _accountQueue = operation.catchError((Object _) {});
    return operation;
  }

  /// Serialize account switches with pending disk writes. Never transplant a
  /// known account's local inventory or onboarding flags into another account.
  /// Restoring an existing account also quarantines unowned local guest data.
  Future<void> bindAccount(String? uid, {bool restoreExisting = false}) {
    if (uid != null && (uid.trim().isEmpty || uid.length > 128)) {
      return Future.error(ArgumentError.value(uid, 'uid'));
    }
    final operation = _accountQueue.then((_) async {
      await load();
      await _flushWrites();
      await _retryAccountErasures();
      final prefs = await SharedPreferences.getInstance();
      if (uid != null && _isAccountErased(prefs, uid)) {
        throw const LocalAccountErasedException();
      }
      if ((_accountOwnerKnown && accountUid == uid) ||
          (!_accountOwnerKnown && uid == null)) {
        return;
      }
      final previous = jsonEncode(_localSnapshot());
      if (_accountOwnerKnown &&
          accountUid != null &&
          !_isAccountErased(prefs, accountUid!)) {
        if (!await prefs.setString(_accountKey(accountUid!), previous)) {
          throw StateError('Could not preserve the previous account');
        }
      } else if (!_accountOwnerKnown &&
          !prefs.containsKey('luno_unowned_account_backup_v1')) {
        if (!await prefs.setString(
          'luno_unowned_account_backup_v1',
          previous,
        )) {
          throw StateError('Could not preserve the unowned legacy snapshot');
        }
        if (uid != null &&
            !restoreExisting &&
            !await prefs.setString(
              'luno_unowned_account_backup_owner_v1',
              uid,
            )) {
          throw StateError('Could not preserve recovery ownership');
        }
      }
      BattleV1Rank? restoredRank;
      if (_accountOwnerKnown || restoreExisting) {
        Map<String, dynamic>? restored;
        final raw = uid == null ? null : prefs.getString(_accountKey(uid));
        if (raw != null) {
          try {
            final decoded = jsonDecode(raw);
            if (decoded is Map && decoded['accountUid'] == uid) {
              restored = Map<String, dynamic>.from(decoded);
            }
          } catch (_) {
            // Keep the damaged account archive intact for recovery.
          }
          if (restored == null && raw.length <= 200000) {
            final recoveryKey = '${_accountKey(uid!)}_recovery';
            if (!prefs.containsKey(recoveryKey) &&
                !await prefs.setString(recoveryKey, raw)) {
              throw StateError(
                'Could not preserve the invalid account archive',
              );
            }
          }
        }
        final restoredData =
            restored == null
                ? PlayerData.initial()
                : PlayerData.fromJson(restored);
        final restoredChosenUsername = restored?['usernameChosen'] == true;
        final restoredUsernameDraft = _readUsernameDraft(restored);
        final restoredTutorialCompleted =
            restored?['tutorialCompleted'] == true;
        final restoredIntroductionStep = _readIntroductionStep(restored);
        final restoredWelcomeStep = _readWelcomeStep(restored);
        final restoredLearning = BattleLearningCheckpoint.fromJson(
          restored?['guidedLearning'],
        );
        final restoredOnboardingBattleStage = _readOnboardingBattleStage(
          restored,
        );
        final restoredFirstSessionMatches = _readFirstSessionMatches(
          restored,
          restoredData,
          restoredTutorialCompleted,
        );
        final restoredFirstSessionCompleted = _readFirstSessionCompleted(
          restored,
          restoredData,
          restoredTutorialCompleted,
        );
        final restoredPracticeStage = _readPracticeStage(restored);
        final restoredTutorialStep = _parseTutorialStep(
          restored?['tutorialStep'],
        );
        restoredRank = _readBattleRank(restored, uid);

        // Finish candidate parsing before the synchronous owner commit so a
        // rejected archive cannot mix one account's data with another's UID.
        data = restoredData;
        hasChosenUsername = restoredChosenUsername;
        pendingUsernameDraft = restoredUsernameDraft;
        hasCompletedTutorial = restoredTutorialCompleted;
        introductionStep = restoredIntroductionStep;
        welcomeStep = restoredWelcomeStep;
        guidedLearning = restoredLearning;
        onboardingBattleStage = restoredOnboardingBattleStage;
        _firstSessionMatchesStarted = restoredFirstSessionMatches;
        firstSessionMatchCompleted = restoredFirstSessionCompleted;
        practiceStage = restoredPracticeStage;
        tutorialStep = restoredTutorialStep;
      }
      // Legacy data has no provable owner. Preserve it on first association,
      // retain a separate recovery copy, and use server state as authority.
      invalidateServerStates();
      _accountBindingRevision++;
      accountUid = uid;
      _battleRank = restoredRank;
      _accountOwnerKnown = true;
      notifyListeners();
      await save();
    });
    _accountQueue = operation.catchError((Object _) {});
    return operation;
  }

  /// Called only after authoritative deletion. Serialize against writes and
  /// binding so the erased archive cannot be recreated by a later sign-out.
  Future<void> eraseLocalAccount(String uid) {
    if (uid.trim().isEmpty || uid.length > 128) {
      return Future.error(ArgumentError.value(uid, 'uid'));
    }
    // Server authority cannot depend on an optimistic preference cache or a
    // successful tombstone write. Keep this UID blocked for this store's life.
    _erasedAccountUids.add(uid);
    final operation = _accountQueue.then((_) async {
      await load();
      final erasure = _pendingAccountErasures.putIfAbsent(
        uid,
        _LocalAccountErasure.new,
      );
      if (accountUid == uid) {
        invalidateServerStates();
        _accountBindingRevision++;
        accountUid = null;
        _accountOwnerKnown = true;
        data = PlayerData.initial();
        _battleRank = null;
        hasChosenUsername = false;
        pendingUsernameDraft = '';
        hasCompletedTutorial = false;
        tutorialStep = 0;
        introductionStep = 0;
        welcomeStep = 0;
        guidedLearning = const BattleLearningCheckpoint();
        onboardingBattleStage = 0;
        firstSessionMatchesStarted = 0;
        practiceStage = null;
        _hasUnsavedSnapshot = true;
        erasure.departureRevision = _accountBindingRevision;
        // The server already erased this owner. Drop account-owned UI even when
        // the local sanitized write fails and cleanup must be retried.
        notifyListeners();
        // Queue the new owner even if an older in-flight save later clears the
        // dirty flag. Tombstone failure must not leave that old snapshot last.
        await save();
      }
      await _flushWrites();
      await _persistAccountErasure(uid, erasure);
    });
    _accountQueue = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> _persistAccountErasure(
    String uid,
    _LocalAccountErasure erasure,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    // Capture ownership before any remove: SharedPreferences removes its cache
    // entry even when the backend rejects the removal.
    erasure.cleanupKeys.addAll(_accountErasureKeys(prefs, uid));
    if (!await prefs.setBool(_erasedAccountKey(uid), true)) {
      throw StateError('Could not record account erasure');
    }
    if (accountUid == null &&
        erasure.departureRevision == _accountBindingRevision) {
      // Use the same drain as newer guest saves; a separate direct write can
      // finish last and replace a newer snapshot with the erased defaults.
      await save();
      if (_hasUnsavedSnapshot) {
        throw StateError('Could not clear the active account snapshot');
      }
      for (final key in [
        _usernameChosenKey,
        _tutorialCompletedKey,
        _tutorialStepKey,
      ]) {
        if (!await prefs.remove(key)) {
          throw StateError('Could not clear account onboarding data');
        }
      }
    }
    for (final key in erasure.cleanupKeys) {
      if (!await prefs.remove(key)) {
        throw StateError('Could not clear an account archive');
      }
    }
    _pendingAccountErasures.remove(uid);
  }

  Set<String> _accountErasureKeys(SharedPreferences prefs, String uid) {
    final keys = <String>{
      _accountKey(uid),
      '${_accountKey(uid)}_recovery',
      '${_accountKey(uid)}_google_link',
      _permanentPurchaseKey(uid),
      _passPremiumPurchaseKey(uid),
      for (final kind in _chestKinds) ...[
        _chestRequestKey(uid, kind, fromPass: true),
        _chestRequestKey(uid, kind, fromPass: false),
      ],
    };
    if (prefs.get('luno_unowned_account_backup_owner_v1') == uid) {
      keys.addAll([
        'luno_unowned_account_backup_v1',
        'luno_unowned_account_backup_owner_v1',
      ]);
    }
    for (final key in [
      _corruptSnapshotBackupKey,
      'luno_unowned_account_backup_v1',
    ]) {
      final raw = prefs.get(key);
      if (raw is! String) continue;
      try {
        final snapshot = jsonDecode(raw);
        if (snapshot is Map && snapshot['accountUid'] == uid) {
          keys.add(key);
        }
      } catch (_) {
        // Unknown-owner recovery data needs separate reconciliation.
      }
    }
    return keys;
  }

  Future<void> _retryAccountErasures() async {
    for (final uid in _pendingAccountErasures.keys.toList()) {
      try {
        await _persistAccountErasure(uid, _pendingAccountErasures[uid]!);
      } catch (_) {
        // One attempt per flush/switch, never an unbounded background loop.
      }
    }
  }

  Future<void> setTutorialStep(int value) async {
    tutorialStep = value.clamp(0, tutorialStepCount - 1).toInt();
    notifyListeners();
    if (_accountOwnerKnown) unawaited(save());
    // Do not make the visible tutorial wait on a platform preference call.
    // The serialized queue is still flushed when the app is backgrounded.
    unawaited(
      _queueAuxiliaryWrite(
        (prefs) => prefs.setInt(_tutorialStepKey, tutorialStep),
      ),
    );
  }

  Future<void> completeTutorial({bool beginPractice = false}) async {
    hasCompletedTutorial = true;
    tutorialStep = 0;
    if (beginPractice && practiceStage == null) practiceStage = 0;
    notifyListeners();
    unawaited(save());
    unawaited(
      _queueAuxiliaryWrite((prefs) async {
        await prefs.setBool(_tutorialCompletedKey, true);
        await prefs.setInt(_tutorialStepKey, 0);
      }),
    );
  }

  Future<void> setIntroductionStep(int value, int accountRevision) async {
    if (accountRevision != _accountBindingRevision || hasCompletedTutorial) {
      return;
    }
    introductionStep = value.clamp(0, introductionStepCount - 1);
    notifyListeners();
    await save();
  }

  Future<bool> advanceWelcomeStep(int expectedStep, int accountRevision) async {
    if (!loaded ||
        accountRevision != _accountBindingRevision ||
        hasCompletedTutorial ||
        onboardingBattleStage != 0 ||
        expectedStep != welcomeStep ||
        expectedStep < 0 ||
        expectedStep >= welcomeStepCount) {
      return false;
    }
    welcomeStep = expectedStep + 1;
    notifyListeners();
    await save();
    return true;
  }

  /// Local learning completion only; no rating, career result or reward grant.
  Future<void> saveGuidedLearning(
    BattleLearningCheckpoint checkpoint,
    int accountRevision,
  ) async {
    if (!loaded ||
        accountRevision != _accountBindingRevision ||
        hasCompletedTutorial) {
      return;
    }
    final next = guidedLearning.merge(checkpoint);
    if (mapEquals(next.toJson(), guidedLearning.toJson())) return;
    guidedLearning = next;
    notifyListeners();
    await save();
  }

  Future<void> skipGuidedOnboarding(int accountRevision) async {
    if (!loaded ||
        accountRevision != _accountBindingRevision ||
        hasCompletedTutorial) {
      return;
    }
    welcomeStep = welcomeStepCount;
    await completeGuidedOnboarding(accountRevision);
  }

  /// Completes local learning bookkeeping, never a career match or reward.
  Future<void> completeGuidedOnboarding(int accountRevision) async {
    if (!loaded ||
        accountRevision != _accountBindingRevision ||
        hasCompletedTutorial ||
        (welcomeStep < welcomeStepCount && onboardingBattleStage == 0)) {
      return;
    }
    _firstSessionMatchesStarted = max(1, _firstSessionMatchesStarted);
    firstSessionMatchCompleted = true;
    await completeTutorial();
  }

  Future<void> completeIntroduction(int accountRevision) async {
    if (accountRevision != _accountBindingRevision || hasCompletedTutorial) {
      return;
    }
    introductionStep = 0;
    await completeTutorial();
  }

  Future<void> completeOnboardingBattle(int stage, int accountRevision) async {
    if (!loaded ||
        accountRevision != _accountBindingRevision ||
        hasCompletedTutorial ||
        stage != onboardingBattleStage ||
        stage < 0 ||
        stage >= onboardingBattleCount) {
      return;
    }
    if (stage == onboardingBattleCount - 1) {
      await completeTutorial();
    } else {
      onboardingBattleStage = stage + 1;
      notifyListeners();
      await save();
    }
  }

  Future<void> beginOptionalAcademy(int accountRevision) async {
    if (accountRevision != _accountBindingRevision ||
        !hasCompletedTutorial ||
        practiceStage != null) {
      return;
    }
    practiceStage = 0;
    notifyListeners();
    await save();
  }

  Future<void> completePracticeStage(int stage, int accountRevision) async {
    if (accountRevision != _accountBindingRevision ||
        practiceStage != stage ||
        stage < 0 ||
        stage >= 4 ||
        !hasCompletedTutorial) {
      return;
    }
    practiceStage = stage + 1;
    notifyListeners();
    await save();
  }

  Future<void> chooseUsername(String username) async {
    data.username = normalizeUsernameValue(username);
    hasChosenUsername = true;
    pendingUsernameDraft = '';
    // The guest can enter the game immediately; persistence may be slower on
    // a cold device while Firebase is booting in parallel.
    notifyListeners();
    try {
      await _queueAuxiliaryWrite(
        (prefs) => prefs.setBool(_usernameChosenKey, true),
      );
      await save();
    } catch (_) {
      // The in-memory guest session remains usable if persistence is down.
    }
  }

  /// A local name is a draft, not a consented public identity or reservation.
  Future<void> requireUsernamePublication(
    String uid,
    int revision,
    String draft,
  ) async {
    if (!loaded || accountUid != uid || revision != _accountBindingRevision) {
      return;
    }
    final value = normalizeUsernameValue(draft);
    pendingUsernameDraft = isUsernameShapeValid(value) ? value : '';
    hasChosenUsername = false;
    notifyListeners();
    await save();
  }

  /// Coalesce rapid mutations into the newest snapshot. A move, reward and
  /// profile edit can all notify the store in one frame; serializing every
  /// intermediate JSON write wastes I/O and can let an older write finish last.
  Future<void> save() async {
    // A lifecycle callback or an early user action can call save while the
    // first load is still in flight. Never let defaults overwrite an update.
    if (!loaded) await load();
    _pendingSnapshot = jsonEncode(_localSnapshot());
    _hasUnsavedSnapshot = true;
    final completer = _saveCompleter ??= Completer<void>();
    if (!_drainingSaves) {
      _drainingSaves = true;
      unawaited(_drainSaves());
    }
    return completer.future;
  }

  Future<void> _drainSaves() async {
    try {
      while (_pendingSnapshot != null) {
        final snapshot = _pendingSnapshot!;
        _pendingSnapshot = null;
        try {
          final prefs = await SharedPreferences.getInstance();
          final written =
              await prefs.setString(_key, snapshot) &&
              await prefs.setInt(_schemaVersionKey, _schemaVersion) &&
              await prefs.setBool(_usernameChosenKey, hasChosenUsername) &&
              await prefs.setBool(
                _tutorialCompletedKey,
                hasCompletedTutorial,
              ) &&
              await prefs.setInt(_tutorialStepKey, tutorialStep);
          if (!written) {
            _hasUnsavedSnapshot = true;
          } else if (_pendingSnapshot == null) {
            _hasUnsavedSnapshot = false;
          }
        } catch (_) {
          // Persistence is best-effort; gameplay and the online source of
          // truth must remain available when the device store is unavailable.
          _hasUnsavedSnapshot = true;
        }
      }
    } finally {
      _drainingSaves = false;
      final completer = _saveCompleter;
      _saveCompleter = null;
      if (completer != null && !completer.isCompleted) completer.complete();
      // A new save cannot interleave between the loop check and this block on
      // Dart's single event loop, but keep the guard for future refactors.
      if (_pendingSnapshot != null && !_drainingSaves) {
        _drainingSaves = true;
        unawaited(_drainSaves());
      }
    }
  }

  /// Waits for the latest queued local snapshot before the app is suspended.
  Future<void> flush() {
    final operation = _accountQueue.then((_) async {
      await _flushWrites();
      await _retryAccountErasures();
    });
    _accountQueue = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> _flushWrites() async {
    final saveFuture = _saveCompleter?.future;
    if (saveFuture != null) await saveFuture;
    await _auxiliaryWriteQueue;
    // Retry once per flush, using current state rather than an old failed owner.
    if (_hasUnsavedSnapshot) await save();
  }

  Future<void> _queueAuxiliaryWrite(
    Future<void> Function(SharedPreferences prefs) write,
  ) {
    _auxiliaryWriteQueue = _auxiliaryWriteQueue.then<void>((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await write(prefs);
      } catch (_) {
        // Keep the current session usable if persistence is temporarily
        // unavailable; the next state change can retry the write.
      }
    });
    return _auxiliaryWriteQueue;
  }

  void _commit() {
    notifyListeners();
    unawaited(save());
  }

  /// Sunucunun doğruladığı ilerlemeyi yerel mağazaya yansıtır.
  /// Yerel AI modu, ağ yokken çalışmaya devam eder; ağ geldiğinde bu kayıt
  /// tekrar sunucu gerçeğiyle eşitlenir.
  void applyServerState(Map<String, dynamic> state) {
    if ((state.containsKey(serverStateOwnerKey) ||
            state.containsKey(serverStateEpochKey)) &&
        (state[serverStateOwnerKey] != accountUid ||
            accountUid == null ||
            state[serverStateEpochKey] != _serverStateEpoch)) {
      return;
    }
    final revision = state['stateRevision'];
    final observedAt = state['stateObservedAt'];
    final versioned =
        state.containsKey('stateRevision') ||
        state.containsKey('stateObservedAt');
    if (versioned) {
      const maxSafeInteger = 9007199254740991;
      if (revision is! int ||
          revision < 0 ||
          revision > maxSafeInteger ||
          observedAt is! int ||
          observedAt < 0 ||
          observedAt > maxSafeInteger ||
          (accountUid != null && state['uid'] != accountUid)) {
        return;
      }
      final previous = _lastServerStateRevision;
      if (previous != null &&
          (revision < previous ||
              (revision == previous &&
                  observedAt < _lastServerStateObservedAt!))) {
        return;
      }
    } else if (_lastServerStateRevision != null) {
      // An older backend response cannot replace versioned authority.
      return;
    }
    int number(dynamic value, int fallback) =>
        value is num && value.isFinite
            ? value.toInt().clamp(0, 1000000000).toInt()
            : fallback;
    String string(dynamic value, String fallback) =>
        value is String && value.isNotEmpty ? value : fallback;
    final profile =
        state['profile'] is Map
            ? Map<String, dynamic>.from(state['profile'] as Map)
            : const <String, dynamic>{};
    final stats =
        state['stats'] is Map
            ? Map<String, dynamic>.from(state['stats'] as Map)
            : const <String, dynamic>{};

    if (state.containsKey('battleV1Rank') && accountUid != null) {
      try {
        _battleRank = BattleV1Rank.fromJson(
          state['battleV1Rank'],
          expectedUid: accountUid!,
        );
      } on FormatException {
        // An incomplete or foreign response cannot replace confirmed rank.
      }
    }

    final remoteUsername = usernameFromMap(profile, fallback: data.username);
    // The server is the source of truth. This also repairs a stale local name
    // after the account was renamed on another device.
    if (remoteUsername.isNotEmpty) data.username = remoteUsername;
    data.playerCode = string(profile['playerCode'], data.playerCode);
    data.country = string(profile['country'], data.country);
    // An empty bio is a valid edit: do not treat it as a missing server field.
    if (profile['bio'] is String) data.bio = profile['bio'] as String;
    data.avatar = string(profile['avatar'], data.avatar);
    data.avatarEmoji = string(profile['avatarEmoji'], data.avatarEmoji);
    data.gold = number(state['gold'], data.gold);
    data.gems = number(state['gems'], data.gems);
    data.trophies = number(state['trophies'], data.trophies);
    data.arenaIdx = number(
      state['arenaIdx'],
      data.arenaIdx,
    ).clamp(0, kArenaCatalog.length - 1);
    data.lvl = max(1, number(state['lvl'], data.lvl));
    data.xp = number(state['xp'], data.xp);
    data.wins = number(stats['wins'], data.wins);
    data.losses = number(stats['losses'], data.losses);
    final draws = number(stats['draws'], data.draws);
    data.draws = draws;
    data.gamesPlayed = data.wins + data.losses + draws;
    // A settled career result can arrive without the battle screen ever seeing
    // its terminal snapshot. Reconcile only the local journey, not rewards.
    if (!firstSessionMatchCompleted &&
        [
          'wins',
          'losses',
          'draws',
        ].any((key) => stats[key] is int && (stats[key] as int) > 0)) {
      _firstSessionMatchesStarted = max(1, _firstSessionMatchesStarted);
      firstSessionMatchCompleted = true;
    }
    data.bestStreak = number(stats['bestStreak'], data.bestStreak);
    data.streak = number(stats['winStreak'], data.streak);
    data.cardsPlayed = number(stats['cardsPlayed'], data.cardsPlayed);
    data.chestsOpened = number(stats['chestsOpened'], data.chestsOpened);

    final unlocked = state['unlockedCards'];
    if (unlocked is Map) {
      final owned =
          unlocked.entries
              .where((entry) => entry.value == true)
              .map((entry) => ownershipKeyForCard(entry.key.toString()))
              .where(isKnownOwnableKey)
              .toSet();
      // A server snapshot with fewer than six valid cards is incomplete; it
      // must not replace a usable local collection with a partial one.
      if (owned.length >= 6) {
        data.ownedCards = owned;
        data.deck = normalizeDeck(data.deck, owned, fallback: kStarterOwned);
      }
    }
    final levels = state['cardLevel'];
    if (levels is Map) {
      final normalized = <String, int>{
        for (final family in kFamilies)
          family: (data.cardLevel[family] ?? 1).clamp(1, 3).toInt(),
      };
      for (final entry in levels.entries) {
        final family = entry.key.toString();
        if (isFamily(family) &&
            entry.value is num &&
            (entry.value as num).isFinite) {
          normalized[family] = number(entry.value, 1).clamp(1, 3).toInt();
        }
      }
      data.cardLevel = normalized;
    }
    final serverDeck = state['deck'];
    if (serverDeck is List && serverDeck.length == 6) {
      final deck = normalizeDeck(
        serverDeck,
        data.ownedCards,
        fallback: data.deck,
      );
      if (deck.length == 6) data.deck = deck;
    }
    final pass = state['passState'];
    final membership = state['membership'];
    if (membership is Map &&
        membership['active'] is bool &&
        membership['expiresAt'] is int &&
        (membership['expiresAt'] as int) >= 0 &&
        (membership['expiresAt'] as int) <= 8640000000000000) {
      data.premiumUntil = membership['expiresAt'] as int;
      data.membershipActive =
          membership['active'] == true && data.premiumUntil > 0;
    }
    if (pass is Map) {
      data.passRewardVersion = normalizePassRewardVersion(
        pass['rewardVersion'],
      );
      // The server stores Pass progress as (level, remainder). Preserve both
      // parts locally; using only the remainder made every completed level
      // disappear from the Pass screen after a ranked match.
      final serverLevel =
          pass['level'] is num && (pass['level'] as num).isFinite
              ? number(pass['level'], data.passLevel()).clamp(0, kPassMaxLevel)
              : data.passLevel();
      final serverRemainder =
          pass['xp'] is num && (pass['xp'] as num).isFinite
              ? number(pass['xp'], 0).clamp(0, kPassXpPerLevel - 1)
              : data.passXp % kPassXpPerLevel;
      data.passXp = serverLevel * kPassXpPerLevel + serverRemainder;
      data.premium = pass['premium'] == true;
      final unlocks = pass['unlocks'];
      if (unlocks is List) {
        final normalized = <String>{};
        for (final entry in unlocks) {
          final token = entry.toString();
          normalized.add(token);
          final separator = token.indexOf(':');
          if (separator > 0 && separator < token.length - 1) {
            normalized.add(token.substring(separator + 1));
          }
        }
        data.passUnlocks = normalized;
      }
      final claimed = pass['claimed'];
      if (claimed is Map) {
        final free = claimed['free'];
        final premium = claimed['premium'];
        if (free is Map || free is List) {
          data.passFreeClaimed = passClaimedLevels(free);
        }
        if (premium is Map || premium is List) {
          data.passPremClaimed = passClaimedLevels(premium);
        }
      }
    }
    final economy = state['economy'];
    if (economy is Map) {
      final daily = economy['daily'];
      if (daily is Map) {
        data.dailyStreak = number(daily['streak'], data.dailyStreak);
        final lastClaimDay = daily['lastClaimDay'];
        data.lastDailyDay = number(lastClaimDay, data.lastDailyDay);
      }
    }
    final inventory = state['inventory'];
    if (inventory is Map) {
      if (inventory['ownedSkins'] case final List owned) {
        data.ownedSkins = owned.whereType<String>().toSet()..add('classic');
      }
      if (inventory.containsKey('skinPieces')) {
        data.skinPieces = normalizeSkinPieces(inventory['skinPieces']);
      }
      if (inventory['activeSkin'] case final String active) {
        data.activeSkin = data.ownedSkins.contains(active) ? active : 'classic';
      }
      if (!data.ownedSkins.contains(data.activeSkin)) {
        data.activeSkin = 'classic';
      }
      const supportedPieceSets = {
        'luno',
        'ottoman',
        'roma',
        'brit',
        'viking',
        'tasdevri',
        'samuray',
        'ice',
        'dragon',
        'neon',
      };
      final ownedEmojis = inventory['ownedEmojis'];
      if (ownedEmojis is List) {
        final normalized =
            ownedEmojis
                .map((entry) => entry.toString().trim())
                .where(kEmojiIds.contains)
                .toSet();
        normalized.add('smile');
        data.ownedEmojis = normalized;
      }
      final ownedSets = inventory['ownedSets'];
      if (ownedSets is List) {
        final normalized =
            ownedSets
                .map((entry) => entry.toString().trim())
                .map((entry) => entry == 'std' ? 'luno' : entry)
                .where(supportedPieceSets.contains)
                .toSet();
        normalized.add('luno');
        data.ownedPieceSets = normalized;
      }
      final pendingChests = inventory['pendingChests'];
      if (pendingChests is List) {
        data.pendingChests =
            pendingChests
                .map((entry) => entry.toString().trim())
                .where((entry) => entry.isNotEmpty)
                .toList();
      }
      final activePieceSet = inventory['activePieceSet'];
      if (activePieceSet is String && activePieceSet.isNotEmpty) {
        final clientPieceSet =
            activePieceSet == 'std' ? 'luno' : activePieceSet;
        if (supportedPieceSets.contains(clientPieceSet) &&
            data.ownedPieceSets.contains(clientPieceSet)) {
          data.pieceSet = clientPieceSet;
        }
      }
      if (!data.ownedPieceSets.contains(data.pieceSet)) data.pieceSet = 'luno';
    }
    // Ownership can change independently of a partial loadout response.
    data.emojiLoadout =
        data.emojiLoadout.where(data.ownedEmojis.contains).toList();
    final serverEmojiLoadout = state['emojiLoadout'];
    if (serverEmojiLoadout is List) {
      final normalized = <String>[];
      for (final entry in serverEmojiLoadout) {
        final id = entry.toString().trim();
        if (kEmojiIds.contains(id) &&
            data.ownedEmojis.contains(id) &&
            !normalized.contains(id)) {
          normalized.add(id);
        }
        if (normalized.length == 4) break;
      }
      // An empty server loadout is meaningful: it clears a stale local one.
      data.emojiLoadout = normalized;
    }
    if (versioned) {
      _lastServerStateRevision = revision as int;
      _lastServerStateObservedAt = observedAt as int;
    }
    _commit();
  }

  // ── Para ──
  void addGold(int g) {
    if (g <= 0) return;
    data.gold += g;
    _commit();
  }

  bool spendGold(int g) {
    if (g <= 0) return false;
    if (data.gold < g) return false;
    data.gold -= g;
    _commit();
    return true;
  }

  void addGems(int g) {
    if (g <= 0) return;
    data.gems += g;
    _commit();
  }

  bool spendGems(int g) {
    if (g <= 0) return false;
    if (data.gems < g) return false;
    data.gems -= g;
    _commit();
    return true;
  }

  // ── Deste ──
  Set<String> get _ownedCardKeys =>
      data.ownedCards.map(ownershipKeyForCard).where(isKnownOwnableKey).toSet();

  void setPieceSet(String set) {
    if (!kPieceSetIds.contains(set) || !data.ownedPieceSets.contains(set)) {
      return;
    }
    data.pieceSet = set;
    _commit();
  }

  void setEmojiLoadout(List<String> ids) {
    final next = <String>[];
    for (final rawId in ids) {
      final id = rawId.trim();
      if (!kEmojiIds.contains(id) ||
          !data.ownedEmojis.contains(id) ||
          next.contains(id)) {
        continue;
      }
      next.add(id);
      if (next.length == 4) break;
    }
    data.emojiLoadout = next;
    _commit();
  }

  List<String> get resolvedDeck {
    final deck = normalizeDeck(
      data.deck,
      data.ownedCards,
      fallback: kStarterOwned,
    );
    return deck
        .map((k) => resolvedKey(k, data.cardLevel[k] ?? 1))
        .toList(growable: false);
  }

  int collectionScore() {
    int s = 0;
    for (final k
        in data.ownedCards
            .map(ownershipKeyForCard)
            .where(isKnownOwnableKey)
            .toSet()) {
      // The server score is based on one canonical family slot. An upgraded
      // family must not change ranking score merely because its art level did.
      final def = tryCardForOwned(k, isFamily(k) ? 1 : data.cardLevel[k] ?? 1);
      if (def != null) s += kCollectionPts[def.rarity] ?? 0;
    }
    return s;
  }

  /// [i]. yuvaya bir sahiplik anahtarı koy (zaten destedeyse yer değiştirir).
  void setDeckSlot(int i, String ownedKey) {
    final canonical = ownershipKeyForCard(ownedKey);
    if (!isKnownOwnableKey(canonical) || !_ownedCardKeys.contains(canonical)) {
      return;
    }
    final deck = normalizeDeck(
      data.deck,
      data.ownedCards,
      fallback: kStarterOwned,
    );
    if (deck.length != 6 || i < 0 || i >= deck.length) return;
    final existing = deck.indexOf(canonical);
    if (existing >= 0 && existing != i) {
      // takas
      deck[existing] = deck[i];
    }
    deck[i] = canonical;
    data.deck = deck;
    _commit();
  }

  void replaceDeck(List<String> deck) {
    if (deck.length != 6) return;
    final normalized = normalizeDeck(deck, data.ownedCards);
    if (normalized.length != 6) return;
    data.deck = normalized;
    _commit();
  }

  /// Destedeki karti, destede olmayan ilk sahip olunan kartla degistirir.
  /// Deste alti kartta tutuldugu icin mac baslangici eksik el olusturmaz.
  bool removeFromDeck(String ownedKey) {
    final canonical = ownershipKeyForCard(ownedKey);
    final deck = normalizeDeck(
      data.deck,
      data.ownedCards,
      fallback: kStarterOwned,
    );
    if (deck.length != 6) return false;
    final index = deck.indexOf(canonical);
    if (index < 0) return false;
    String? replacement;
    for (final candidate in kAllOwnable.where(_ownedCardKeys.contains)) {
      if (!deck.contains(candidate)) {
        replacement = candidate;
        break;
      }
    }
    if (replacement == null) return false;
    deck[index] = replacement;
    data.deck = deck;
    _commit();
    return true;
  }

  bool canUpgrade(String family) {
    final canonical = ownershipKeyForCard(family);
    if (!isFamily(canonical) || !_ownedCardKeys.contains(canonical)) {
      return false;
    }
    final lvl = data.cardLevel[canonical] ?? 1;
    final requiredArena = upgradeRequiredArena(canonical, lvl);
    if (requiredArena == null ||
        arenaIndexForPlayer(data.trophies, data.arenaIdx) < requiredArena) {
      return false;
    }
    return data.gold >= upgradeGoldCost(lvl);
  }

  bool upgradeCard(String family) {
    if (!canUpgrade(family)) return false;
    final canonical = ownershipKeyForCard(family);
    final lvl = data.cardLevel[canonical] ?? 1;
    data.gold -= upgradeGoldCost(lvl);
    data.cardLevel[canonical] = lvl + 1;
    _commit();
    return true;
  }

  // ── Sandık ──
  ChestResult? openChest({required int cost, required bool gem}) {
    if (cost <= 0) return null;
    if (gem) {
      if (!spendGems(cost)) return null;
    } else {
      if (!spendGold(cost)) return null;
    }
    final pool = chestPoolForArena(data.arenaIdx, excludeOwned: _ownedCardKeys);
    final pick = pool[_rng.nextInt(pool.length)];
    data.chestsOpened++;
    if (_ownedCardKeys.contains(ownershipKeyForCard(pick))) {
      const refund = 250;
      data.gold += refund;
      _commit();
      return ChestResult(pick, false, refund);
    }
    data.ownedCards.add(pick);
    if (isFamily(pick)) data.cardLevel[pick] = 1;
    _commit();
    return ChestResult(pick, true, 0);
  }

  // ── Günlük ödül ──
  int _today() => DateTime.now().toUtc().millisecondsSinceEpoch ~/ 86400000;

  bool canClaimDaily() => _today() > data.lastDailyDay;

  int _dailyStreakForDay(int today) =>
      data.lastDailyDay == 0 || today - data.lastDailyDay > 1
          ? 0
          : data.dailyStreak;

  int dailyPreview() =>
      kDailyGold[_dailyStreakForDay(_today()) % kDailyGold.length];

  int? claimDaily() {
    if (!canClaimDaily()) return null;
    final today = _today();
    data.dailyStreak = _dailyStreakForDay(today);
    final reward = kDailyGold[data.dailyStreak % kDailyGold.length];
    data.gold += reward;
    data.lastDailyDay = today;
    data.dailyStreak++;
    _commit();
    return reward;
  }

  // ── Luno Pass ──
  int passLevel() => data.passLevel();

  /// The pass screen exposes one claim action per unlocked track. Keeping the
  /// count here makes the home badge use the same rules as the claim buttons.
  int get claimablePassRewardCount {
    final level = passLevel();
    var count = 0;
    for (var tier = 1; tier <= level; tier++) {
      if (canClaimPassFree(tier)) count++;
      if (canClaimPassPrem(tier)) count++;
    }
    return count;
  }

  int get claimableRewardCount =>
      (canClaimDaily() ? 1 : 0) + claimablePassRewardCount;

  bool canClaimPassFree(int level) =>
      level >= 1 &&
      level <= passLevel() &&
      !data.passFreeClaimed.contains(level);

  bool canClaimPassPrem(int level) =>
      data.premium &&
      level >= 1 &&
      level <= passLevel() &&
      !data.passPremClaimed.contains(level);

  void claimPassFree(int level) {
    if (!canClaimPassFree(level)) return;
    final t = passFree(level);
    _grantPassTier(t);
    data.passFreeClaimed.add(level);
    _commit();
  }

  void claimPassPrem(int level) {
    if (!canClaimPassPrem(level)) return;
    final t = passPrem(level, rewardVersion: data.passRewardVersion);
    _grantPassTier(t);
    data.passPremClaimed.add(level);
    _commit();
  }

  void _grantPassTier(PassTier tier) {
    data.gold += tier.gold;
    data.gems += tier.gems;
    if (tier.key != null) {
      data.passUnlocks.add(tier.key!);
      switch (tier.kind) {
        case PassRewardKind.chest:
          data.pendingChests.add(tier.key!);
        case PassRewardKind.emoji:
          data.ownedEmojis.add(tier.key!);
        case PassRewardKind.costume:
          data.ownedPieceSets.add(tier.key!);
        case null:
          break;
      }
    }
  }

  bool buyPremium() {
    if (data.premium) return false;
    if (!spendGems(kPassPremiumCost)) return false;
    data.premium = true;
    _commit();
    return true;
  }

  // ── Maç sonucu (AI antrenmanı: altın evet, kupa hayır) ──
  int recordResult({
    required bool win,
    required AiLevel level,
    int cardsPlayed = 0,
    bool draw = false,
    bool grantProgress = true,
  }) {
    data.gamesPlayed++;
    data.cardsPlayed += cardsPlayed.clamp(0, 1000).toInt();
    int reward;
    if (draw) {
      data.draws++;
      data.streak = 0;
      reward = 20;
    } else if (win) {
      data.wins++;
      data.streak++;
      if (data.streak > data.bestStreak) data.bestStreak = data.streak;
      reward = (120 * level.rewardMult).round();
    } else {
      data.losses++;
      data.streak = 0;
      reward = 20;
    }
    // Same-device games may update the local career summary, but must not be
    // farmable for currency or Pass progress.
    if (grantProgress) {
      data.gold += reward;
      data.passXp += win ? 40 : 15;
    } else {
      reward = 0;
    }
    _commit();
    return reward;
  }
}
