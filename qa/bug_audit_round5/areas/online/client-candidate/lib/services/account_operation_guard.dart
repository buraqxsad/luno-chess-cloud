import '../models/game_store.dart';
import 'luno_online_service.dart';

/// Keep optimistic edits, rollback and notices attached to their starting account.
class AccountOperationGuard {
  AccountOperationGuard(this.store, this.online)
    : _storeUid = store.accountUid,
      _storeRevision = store.accountBindingRevision,
      _authUid = online.user?.uid,
      _authRevision = online.accountRevision;

  final GameStore store;
  final LunoOnlineService online;
  final String? _storeUid;
  final int _storeRevision;
  final String? _authUid;
  final int _authRevision;

  bool get isCurrent =>
      store.accountUid == _storeUid &&
      store.accountBindingRevision == _storeRevision &&
      online.user?.uid == _authUid &&
      online.accountRevision == _authRevision &&
      online.accountFailure == null;

  void check() {
    if (!isCurrent) {
      throw const LunoApiException('session-changed', 409);
    }
  }
}
