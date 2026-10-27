import 'package:flutter/material.dart' hide Text;

import '../data/pass_purchase.dart';
import '../i18n/luno_text.dart';
import '../models/game_store.dart';
import '../theme/luno_assets.dart';
import 'luno_surface.dart';

class PassPurchaseRecoveryTile extends StatefulWidget {
  const PassPurchaseRecoveryTile({
    super.key,
    required this.store,
    required this.busy,
    required this.enabled,
    required this.onRetry,
    this.revision = 0,
  });
  final GameStore store;
  final bool busy;
  final bool enabled;
  final VoidCallback onRetry;
  final int revision;

  @override
  State<PassPurchaseRecoveryTile> createState() =>
      _PassPurchaseRecoveryTileState();
}

class _PassPurchaseRecoveryTileState extends State<PassPurchaseRecoveryTile> {
  String? _owner;
  int? _ownerRevision;
  Future<PassPremiumPurchase?>? _pending;

  @override
  void didUpdateWidget(covariant PassPurchaseRecoveryTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.store, widget.store) ||
        oldWidget.revision != widget.revision ||
        (oldWidget.busy && !widget.busy)) {
      _pending = null;
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) {
      final store = widget.store;
      final owner = store.accountUid;
      final revision = store.accountBindingRevision;
      bool ownsSnapshot() =>
          mounted &&
          identical(widget.store, store) &&
          owner == store.accountUid &&
          revision == store.accountBindingRevision;
      if (_pending == null || _owner != owner || _ownerRevision != revision) {
        _owner = owner;
        _ownerRevision = revision;
        _pending =
            owner == null
                ? Future.value(null)
                : store.pendingPassPremiumPurchase(owner);
      }
      return FutureBuilder<PassPremiumPurchase?>(
        future: _pending,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done ||
              !ownsSnapshot() ||
              snapshot.data == null) {
            return const SizedBox.shrink();
          }
          return Padding(
            key: const ValueKey('pending-pass-premium'),
            padding: const EdgeInsets.all(10),
            child: LunoSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Row(
                    children: [
                      LunoArt(LunoAssets.passPremium, width: 42, height: 42),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Bekleyen Premium alımını doğrula.',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LunoButton(
                    label: 'TEKRAR DENE',
                    loading: widget.busy,
                    backgroundArt: LunoAssets.actionSurfaceV27,
                    onPressed:
                        widget.enabled && !widget.busy
                            ? () {
                              final lifecycle =
                                  WidgetsBinding.instance.lifecycleState;
                              if (!ownsSnapshot() ||
                                  !widget.enabled ||
                                  widget.busy ||
                                  (lifecycle != null &&
                                      lifecycle != AppLifecycleState.resumed) ||
                                  ModalRoute.of(context)?.isCurrent != true) {
                                return;
                              }
                              widget.onRetry();
                            }
                            : null,
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}
