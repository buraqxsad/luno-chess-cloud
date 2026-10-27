import 'package:shared_preferences/shared_preferences.dart';

class BattleV1PendingStorageException implements Exception {
  final String operation;
  const BattleV1PendingStorageException(this.operation);

  @override
  String toString() => 'Pending action storage failed: $operation';
}

class _PendingState {
  String? json;
  bool persisted;
  Future<void> tail = Future<void>.value();

  _PendingState(this.json) : persisted = json != null;
}

/// Keeps failed preference operations from losing their identity in its cache.
class BattleV1PendingStore {
  static final _states = Expando<Map<String, _PendingState>>();
  final String _key;
  final Future<bool> Function(String, String) _write;
  final Future<bool> Function(String) _remove;
  final _PendingState _state;
  String? _ownedJson;

  BattleV1PendingStore(
    SharedPreferences preferences, {
    required String uid,
    required String matchId,
  }) : this.forTesting(
         storageIdentity: preferences,
         uid: uid,
         matchId: matchId,
         read: preferences.getString,
         write: preferences.setString,
         remove: preferences.remove,
       );

  BattleV1PendingStore.forTesting({
    required Object storageIdentity,
    required String uid,
    required String matchId,
    required String? Function(String) read,
    required Future<bool> Function(String, String) write,
    required Future<bool> Function(String) remove,
  }) : _key = 'battle_v1_pending:$uid:$matchId',
       _write = write,
       _remove = remove,
       _state = (_states[storageIdentity] ??= {}).putIfAbsent(
         'battle_v1_pending:$uid:$matchId',
         () => _PendingState(read('battle_v1_pending:$uid:$matchId')),
       ) {
    _ownedJson = _state.json;
  }

  String? get pendingJson => _state.json;
  bool get pendingPersisted => _state.persisted;

  Future<void> persist(String? value) {
    if (value != null) {
      if (_state.json != null && _state.json != value) {
        return Future<void>.error(
          const BattleV1PendingStorageException('unresolved action'),
        );
      }
      if (_state.json == null) {
        _state.json = value;
        _state.persisted = false;
      }
      _ownedJson = value;
    }
    final expected = _ownedJson;
    final operation = _state.tail.then((_) async {
      // Another owner may already have completed this action's cleanup.
      if (value == null && _state.json == null) {
        _ownedJson = null;
        return;
      }
      if (_state.json != expected) {
        throw const BattleV1PendingStorageException('action changed');
      }
      if (value == null) {
        if (expected == null) return;
        if (!await _remove(_key)) {
          throw const BattleV1PendingStorageException('remove');
        }
        _state.json = null;
        _state.persisted = false;
        _ownedJson = null;
      } else if (!_state.persisted) {
        if (!await _write(_key, value)) {
          throw const BattleV1PendingStorageException('write');
        }
        _state.persisted = true;
      }
    });
    _state.tail = operation.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return operation;
  }
}
