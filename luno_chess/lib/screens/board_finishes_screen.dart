import 'dart:async';
import 'package:flutter/material.dart' hide Text;
import '../data/board_finishes.dart';
import '../i18n/luno_localizations.dart';
import '../i18n/luno_text.dart';
import '../models/game_store.dart';
import '../navigation/luno_account_scope.dart';
import '../services/account_operation_guard.dart';
import '../services/luno_online_service.dart';
import '../theme/luno_theme.dart';
import '../widgets/luno_surface.dart';
import 'collection_screens.dart' show CostumeBoardPreview;

class BoardFinishesScreen extends StatefulWidget implements LunoAccountScopedPage {
  const BoardFinishesScreen({super.key, this.online, this.playerStore});
  final LunoOnlineService? online;
  final GameStore? playerStore;
  @override
  State<BoardFinishesScreen> createState() => _BoardFinishesScreenState();
}

class _BoardFinishesScreenState extends State<BoardFinishesScreen> {
  GameStore get store => widget.playerStore ?? GameStore.instance;
  LunoOnlineService get online => widget.online ?? LunoOnlineService.instance;
  String? _saving;
  String? _error;
  Future<void>? _entryRefresh;
  bool get visible => mounted && ModalRoute.of(context)?.isCurrent == true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _entryRefresh = _refresh();
        unawaited(_entryRefresh!);
      }
    });
  }
  Future<void> _refresh() async {
    final guard = AccountOperationGuard(store, online);
    try {
      await online.start().timeout(const Duration(seconds: 12));
      guard.check();
      final result = await online.getPlayerState().timeout(const Duration(seconds: 12));
      guard.check();
      if (!visible || result['ok'] != true || result['state'] is! Map) return;
      store.applyServerState(Map<String, dynamic>.from(result['state'] as Map));
    } catch (_) {
      // Existing confirmed rights remain browsable while offline.
    }
  }
  Future<void> _equip(BoardFinish finish) async {
    if (!visible || _saving != null || !store.data.ownedSkins.contains(finish.id) ||
        store.data.activeSkin == finish.id) {
      return;
    }
    final guard = AccountOperationGuard(store, online);
    final ownerStore = store, ownerOnline = online;
    var previous = store.data.activeSkin;
    var epoch = store.serverStateEpoch;
    bool current() => guard.isCurrent && identical(store, ownerStore) &&
        identical(online, ownerOnline) && store.serverStateEpoch == epoch;
    setState(() { _saving = finish.id; _error = null; });
    try {
      await _entryRefresh;
      guard.check();
      if (!visible || !identical(store, ownerStore) || !identical(online, ownerOnline) ||
          !store.data.ownedSkins.contains(finish.id)) {
        return;
      }
      previous = store.data.activeSkin;
      final bootstrap = online.start();
      epoch = store.serverStateEpoch;
      await bootstrap.timeout(const Duration(seconds: 12));
      guard.check();
      if (!visible || !current()) return;
      final result = await online.updateProfile({'activeSkin': finish.id})
          .timeout(const Duration(seconds: 12));
      guard.check();
      if (!visible || !current() || store.data.activeSkin != previous) return;
      final state = result['state'];
      final inventory = state is Map ? state['inventory'] : null;
      if (result['ok'] != true || inventory is! Map ||
          inventory['activeSkin'] != finish.id || inventory['ownedSkins'] is! List ||
          !(inventory['ownedSkins'] as List).contains(finish.id)) {
        throw const FormatException('Unconfirmed board finish');
      }
      store.applyServerState(Map<String, dynamic>.from(state as Map));
    } catch (_) {
      if (visible && current()) {
        setState(() => _error = LunoLocalizations.of(context).isEnglish
            ? 'Could not confirm the frame. Your previous choice is unchanged.'
            : 'Çerçeve doğrulanamadı. Önceki seçimin değiştirilmedi.');
      }
    } finally {
      if (mounted) setState(() => _saving = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final en = LunoLocalizations.of(context).isEnglish;
    return ListenableBuilder(listenable: store, builder: (context, _) => Scaffold(
      appBar: AppBar(title: Text(en ? 'BOARD FRAMES' : 'TAHTA ÇERÇEVELERİ')),
      body: SafeArea(child: ListView(padding: const EdgeInsets.all(16), children: [
        Text(en ? 'Your original cosmetic collection' : 'Özgün kozmetik koleksiyonun',
            style: LunoType.sectionTitle),
        const SizedBox(height: 8),
        Text(en
            ? 'Chest skin pieces unlock decorative board rims. They are separate from complete piece sets; your pieces and rules stay the same. Past rewards and purchases are preserved.'
            : 'Sandıktaki görünüm parçaları tahta çerçevelerini açar. Tam taş setlerinden ayrıdır; taşların ve kurallar değişmez. Önceki ödül ve satın alımların korunur.',
            style: LunoType.bodyMuted),
        if (_error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(_error!, style: const TextStyle(color: LunoColors.danger))),
        const SizedBox(height: 14),
        for (final finish in boardFinishes) ...[
          LunoSurface(border: Border.all(color: finish.color.withValues(alpha: .6)), child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(finish.title(en), style: LunoType.sectionTitle),
              const SizedBox(height: 10),
              Center(child: SizedBox(width: 180, height: 120,
                child: DecoratedBox(decoration: BoxDecoration(
                  border: Border.all(color: finish.color, width: 4),
                  borderRadius: BorderRadius.circular(5)),
                  child: const Padding(padding: EdgeInsets.all(6),
                    child: CostumeBoardPreview(setId: 'luno', bothSides: true))))),
              const SizedBox(height: 10),
              if (!store.data.ownedSkins.contains(finish.id)) ...[
                Text('${store.data.skinPieces[finish.id] ?? 0} / ${finish.target} ${en ? 'pieces' : 'parça'}',
                    key: ValueKey('finish-progress-${finish.id}')),
                const SizedBox(height: 6),
                LinearProgressIndicator(value: (store.data.skinPieces[finish.id] ?? 0) / finish.target,
                    color: finish.color),
                const SizedBox(height: 8),
                Text(en ? 'Collect the remaining pieces from chests.' : 'Kalan parçaları sandıklardan topla.',
                    style: LunoType.bodyMuted),
              ] else
                LunoButton(key: ValueKey('finish-equip-${finish.id}'),
                  label: store.data.activeSkin == finish.id
                      ? (en ? 'EQUIPPED' : 'KUŞANILDI') : (en ? 'EQUIP FRAME' : 'ÇERÇEVEYİ KUŞAN'),
                  loading: _saving == finish.id,
                  onPressed: _saving != null || store.data.activeSkin == finish.id
                      ? null : () => unawaited(_equip(finish))),
            ],
          )),
          const SizedBox(height: 12),
        ],
      ])),
    ));
  }
}
