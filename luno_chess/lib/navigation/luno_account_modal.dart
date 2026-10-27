import 'package:flutter/material.dart';

import '../services/luno_online_service.dart';
import '../models/game_store.dart';

void dismissLunoAccountModal<T>(BuildContext context, [T? result]) {
  if (!context.mounted || ModalRoute.of(context)?.isCurrent != true) return;
  Navigator.of(context).pop<T>(result);
}

class _ModalSession {
  _ModalSession(
    this.service, {
    this.allowAccountDeletion = false,
    this.playerStore,
  }) : revision = service.accountRevision,
       uid = service.user?.uid,
       storeUid = playerStore?.accountUid,
       storeRevision = playerStore?.accountBindingRevision;

  final LunoOnlineService service;
  final int revision;
  final String? uid;
  final bool allowAccountDeletion;
  final GameStore? playerStore;
  final String? storeUid;
  final int? storeRevision;
  late final Listenable changes = Listenable.merge([
    service,
    if (playerStore != null) playerStore!,
  ]);

  bool get isCurrent =>
      service.accountRevision == revision &&
      service.user?.uid == uid &&
      (playerStore == null ||
          (playerStore!.accountUid == storeUid &&
              playerStore!.accountBindingRevision == storeRevision)) &&
      (service.accountFailure == null ||
          (allowAccountDeletion &&
              {
                'account-deleted',
                'account-deletion-in-progress',
              }.contains(service.accountFailure?.code)));
}

Future<T?> showLunoAccountDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  LunoOnlineService? service,
  bool allowAccountDeletion = false,
  GameStore? playerStore,
  bool barrierDismissible = true,
}) async {
  final session = _ModalSession(
    service ?? LunoOnlineService.instance,
    allowAccountDeletion: allowAccountDeletion,
    playerStore: playerStore,
  );
  final result = await showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (_) => _AccountModal(session: session, builder: builder),
  );
  return session.isCurrent ? result : null;
}

Future<T?> showLunoAccountBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color? backgroundColor,
  LunoOnlineService? service,
  GameStore? playerStore,
}) async {
  final session = _ModalSession(
    service ?? LunoOnlineService.instance,
    playerStore: playerStore,
  );
  final result = await showModalBottomSheet<T>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: backgroundColor,
    builder: (_) => _AccountModal(session: session, builder: builder),
  );
  return session.isCurrent ? result : null;
}

class _AccountModal extends StatefulWidget {
  const _AccountModal({required this.session, required this.builder});

  final _ModalSession session;
  final WidgetBuilder builder;

  @override
  State<_AccountModal> createState() => _AccountModalState();
}

class _AccountModalState extends State<_AccountModal> {
  bool _dismissScheduled = false;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.session.changes,
    builder: (context, _) {
      if (widget.session.isCurrent) return widget.builder(context);
      if (!_dismissScheduled) {
        _dismissScheduled = true;
        final route = ModalRoute.of(context);
        final navigator = route?.navigator;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          // Remove this exact modal, never an unrelated route pushed above it.
          if (mounted &&
              route != null &&
              route.isActive &&
              navigator != null &&
              route.navigator == navigator) {
            navigator.removeRoute(route);
          }
        });
      }
      return const SizedBox.shrink();
    },
  );
}
