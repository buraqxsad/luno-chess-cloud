import 'dart:async';
import '../widgets/card_level_sheet.dart';
import '../widgets/promotion_sheet.dart';
import '../widgets/match_confirmation.dart';
import '../widgets/match_offer_banner.dart';
import '../widgets/match_menu_sheet.dart';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart' hide Text;

import '../cards/card_catalog.dart';
import '../cards/card_def.dart';
import '../engine/piece.dart';
import '../engine/square.dart';
import '../i18n/luno_text.dart';
import '../match/match_state.dart';
import '../match/mpiece.dart';
import '../models/game_store.dart';
import '../services/luno_audio_service.dart';
import '../data/username.dart';
import '../services/luno_online_service.dart';
import '../theme/luno_assets.dart';
import '../theme/luno_theme.dart';
import '../widgets/luno_clock.dart';
import '../widgets/luno_surface.dart';
import '../widgets/match_board.dart';
import '../widgets/resource_amount.dart';
import '../widgets/card_info.dart';

class OnlineMatchScreen extends StatefulWidget {
  final String matchId;
  final Map<String, dynamic> initialView;
  @visibleForTesting
  final Future<Map<String, dynamic>> Function(String, Map<String, dynamic>)?
  requestOverride;
  @visibleForTesting
  final String? Function()? uidOverride;

  const OnlineMatchScreen({
    super.key,
    required this.matchId,
    required this.initialView,
    this.requestOverride,
    this.uidOverride,
  });

  @override
  State<OnlineMatchScreen> createState() => _OnlineMatchScreenState();
}

class _OnlineMatchScreenState extends State<OnlineMatchScreen>
    with WidgetsBindingObserver {
  final online = LunoOnlineService.instance;
  late Map<String, dynamic> view;
  Timer? _pollTimer;
  Timer? _heartbeatTimer;
  Timer? _clockTimer;
  int? selected;
  Set<int> moveTargets = {};
  String? armedCard;
  Set<int> cardTargets = {};
  int? gluePendingFirst;
  bool busy = false;
  String? error;
  String? _lastStateRevision;
  bool _terminalStateSynced = false;
  bool _accountBlocked = false;
  int _clockServerNow = 0;
  int _clockReceivedAt = 0;
  final ValueNotifier<int> _clockRevision = ValueNotifier(0);
  final Stopwatch _monotonicClock = Stopwatch()..start();
  int _clockReceivedElapsed = 0;
  final String _actionInstance = Random.secure()
      .nextInt(0x7fffffff)
      .toRadixString(36);
  int _actionNonce = 0;
  bool _allowPop = false;
  bool _leaveInProgress = false;
  // Polling and heartbeat both write the same view. A single lock prevents an
  // older response from racing in after a newer response and rolling back the
  // rendered board or clock.
  bool _syncing = false;

  String? get _currentUid =>
      widget.uidOverride != null ? widget.uidOverride!() : online.user?.uid;

  bool _sameAccount(String? uid) =>
      mounted &&
      uid != null &&
      uid.isNotEmpty &&
      _currentUid == uid &&
      (view['player'] is Map) &&
      view['player']['uid'] == uid;

  Future<Map<String, dynamic>> _request(
    String path,
    Map<String, dynamic> body,
  ) => widget.requestOverride?.call(path, body) ?? online.api(path, body);

  bool _acceptResponse(String? uid, Map<String, dynamic> result) {
    if (_accountBlocked || !_sameAccount(uid)) return false;
    final next = result['view'];
    return result['ok'] == true &&
        result['matchId'] == widget.matchId &&
        next is Map &&
        next['matchId'] == widget.matchId &&
        next['player'] is Map &&
        next['player']['uid'] == uid &&
        _number(next['sequence']) >= _number(view['sequence']);
  }

  @override
  void initState() {
    super.initState();
    unawaited(LunoAudioService.instance.setScene(LunoMusicScene.battle));
    view = Map<String, dynamic>.from(widget.initialView);
    _captureClockSync(view);
    WidgetsBinding.instance.addObserver(this);
    online.addListener(_onOnlineChanged);
    _startTimers();
  }

  @override
  void dispose() {
    unawaited(LunoAudioService.instance.setScene(LunoMusicScene.menu));
    online.removeListener(_onOnlineChanged);
    WidgetsBinding.instance.removeObserver(this);
    _stopTimers();
    _clockRevision.dispose();
    super.dispose();
  }

  void _onOnlineChanged() {
    if (!mounted || !online.isOnline || _finished) return;
    if (error != null) setState(() => error = null);
    unawaited(_refresh(force: true));
  }

  void _startTimers() {
    if (_accountBlocked) return;
    _pollTimer?.cancel();
    _heartbeatTimer?.cancel();
    _clockTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _heartbeat(),
    );
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && !_finished && view['clock'] is Map) {
        _clockRevision.value++;
      }
    });
  }

  void _stopTimers() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _clockTimer?.cancel();
    _clockTimer = null;
  }

  void _clearInteraction() {
    selected = null;
    moveTargets = {};
    armedCard = null;
    cardTargets = {};
    gluePendingFirst = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startTimers();
      unawaited(_resumeMatch());
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _stopTimers();
    }
  }

  Future<void> _resumeMatch() async {
    await _refresh(force: true);
    if (mounted && !_finished) await _heartbeat();
  }

  // Server snapshots contain totals, never client-calculated reward deltas.
  void _applyResultState(Map<String, dynamic> response) {
    final raw = response['state'];
    if (raw is! Map || raw.isEmpty) return;
    final nextState = Map<String, dynamic>.from(raw);
    final revision = jsonEncode(nextState);
    if (revision != _lastStateRevision) {
      GameStore.instance.applyServerState(nextState);
      _lastStateRevision = revision;
    }
    final next = response['view'];
    if (next is Map &&
        (next['result'] is Map ||
            const {'finished', 'cancelled'}.contains(next['status']))) {
      _terminalStateSynced = true;
    }
  }

  Future<void> _refresh({bool force = false}) async {
    if (!mounted ||
        _accountBlocked ||
        _syncing ||
        (_finished && _terminalStateSynced) ||
        (!force && busy)) {
      return;
    }
    final uid = _currentUid;
    if (!_sameAccount(uid)) return;
    _syncing = true;
    try {
      final result = await _request('/getRankedMatch', {
        'matchId': widget.matchId,
      });
      if (!_acceptResponse(uid, result)) return;
      final nextView = result['view'];
      _applyResultState(result);
      if (!mounted || nextView is! Map) return;
      final next = Map<String, dynamic>.from(nextView);
      if (_number(next['sequence']) < _number(view['sequence'])) return;
      if (_viewRevision(next) == _viewRevision(view)) {
        _captureClockSync(next);
        if (error != null) setState(() => error = null);
        return;
      }
      setState(() {
        view = next;
        _captureClockSync(next);
        error = null;
        _clearInteraction();
      });
    } catch (e) {
      if (_handleAccountFailure(e, uid)) return;
      if (mounted) setState(() => error = 'Bağlantı yenileniyor...');
    } finally {
      _syncing = false;
    }
  }

  Future<void> _heartbeat() async {
    if (!mounted || _accountBlocked || _syncing || busy || _finished) return;
    final uid = _currentUid;
    if (!_sameAccount(uid)) return;
    _syncing = true;
    try {
      final result = await _request('/heartbeatRankedMatch', {
        'matchId': widget.matchId,
      });
      if (!_acceptResponse(uid, result)) return;
      _applyResultState(result);
      final nextView = result['view'];
      if (mounted && nextView is Map) {
        final next = Map<String, dynamic>.from(nextView);
        if (_number(next['sequence']) < _number(view['sequence'])) return;
        if (_viewRevision(next) != _viewRevision(view)) {
          setState(() {
            view = next;
            _captureClockSync(next);
            error = null;
            _clearInteraction();
          });
        } else {
          _captureClockSync(next);
          if (error != null) setState(() => error = null);
        }
      }
    } catch (e) {
      if (_handleAccountFailure(e, uid)) return;
      if (mounted) setState(() => error = 'Bağlantı yeniden kuruluyor...');
    } finally {
      _syncing = false;
    }
  }

  Future<bool> _sendAction(
    String type, {
    int? from,
    int? to,
    String? promotion,
    String? cardKey,
    int? target,
    int? secondaryTarget,
  }) async {
    final uid = _currentUid;
    if (_accountBlocked ||
        !_sameAccount(uid) ||
        busy ||
        _syncing ||
        _finished) {
      return false;
    }
    final sequence = _number(view['sequence']);
    final capturedMove = type == 'move' && to != null && _hasPieceAt(to);
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final action = <String, dynamic>{
        'matchId': widget.matchId,
        'type': type,
        // Action identity is independent of the device wall clock. A manual
        // date change must never turn a new move into an old idempotent retry.
        'actionId': 'flutter-action-$_actionInstance-${_actionNonce++}',
        'expectedSequence': sequence,
        'from': from,
        'to': to,
        'promotion': promotion,
      };
      if (type == 'card') {
        action['cardKey'] = cardKey;
        if (target != null) action['target'] = target;
        if (secondaryTarget != null) {
          action['secondaryTarget'] = secondaryTarget;
        }
      }
      final result = await _request('/submitMatchAction', action);
      if (!_acceptResponse(uid, result)) return false;
      _applyResultState(result);
      final nextView = result['view'];
      var refreshRequired = nextView is! Map;
      if (mounted && nextView is Map) {
        final next = Map<String, dynamic>.from(nextView);
        if (_number(next['sequence']) < _number(view['sequence'])) {
          refreshRequired = true;
        } else if (_viewRevision(next) != _viewRevision(view)) {
          setState(() {
            view = next;
            _captureClockSync(next);
            _clearInteraction();
          });
        }
      }
      if (refreshRequired && mounted) {
        await _refresh(force: true);
      }
    } catch (e) {
      if (!mounted) return false;
      if (_handleAccountFailure(e, uid)) return false;
      setState(() => error = _actionError(e));
      await _refresh(force: true);
      return false;
    } finally {
      if (mounted) setState(() => busy = false);
    }
    if (type == 'move') {
      unawaited(
        LunoAudioService.instance.playEffect(
          capturedMove ? LunoSound.capture : LunoSound.move,
        ),
      );
    } else if (type == 'card') {
      unawaited(LunoAudioService.instance.playEffect(LunoSound.move));
    }
    return true;
  }

  bool _hasPieceAt(int index) {
    final board = view['board'];
    if (board is! List || index < 0 || index >= board.length) return false;
    return board[index] is Map;
  }

  void _fireAction(Future<bool> action) {
    unawaited(action.then<void>((_) {}));
  }

  bool _handleAccountFailure(Object cause, String? uid) {
    if (cause is! LunoApiException || cause.accountAccessMessage == null) {
      return false;
    }
    if (!_sameAccount(uid)) return true;
    _stopTimers();
    setState(() {
      _accountBlocked = true;
      error = cause.accountAccessMessage;
      _clearInteraction();
    });
    return true;
  }

  String _actionError(Object cause) {
    if (cause is LunoApiException) {
      switch (cause.code) {
        case 'stale-sequence':
          return 'Tahta güncellendi, hamleni yeniden seç.';
        case 'match-finished':
          return 'Maç zaten sona erdi.';
        case 'disconnect-forfeit':
          return 'Bağlantı süresi dolduğu için maç sona erdi.';
        case 'not-a-participant':
        case 'match-not-found':
          return 'Bu maç artık hesabınla bağlı değil.';
        case 'draw-offer-pending':
          return 'Önce gelen beraberlik teklifine cevap ver.';
        case 'draw-offer-already-active':
          return 'Beraberlik teklifin hâlâ bekliyor.';
        case 'cancel-offer-pending':
          return 'Önce gelen iptal teklifine cevap ver.';
        case 'cancel-window-closed':
          return 'Maç iptali için başlangıç süresi geçti.';
      }
      if (cause.status == 0 || cause.code.contains('network')) {
        return 'Bağlantı koptu; yeniden bağlanılıyor.';
      }
    }
    return 'İşlem sunucu tarafından kabul edilmedi.';
  }

  bool _requiresPromotion(int from, int to) {
    final board = view['board'];
    if (board is! List || from >= board.length) return false;
    final piece = board[from];
    if (piece is! Map || piece['t'] != 'P') return false;
    final rank = Square.rankOf(to);
    return rank == 0 || rank == 7;
  }

  String _viewRevision(Map<String, dynamic> candidate) => jsonEncode({
    'sequence': candidate['sequence'],
    'turn': candidate['turn'],
    'phase': candidate['phase'],
    'status': candidate['status'],
    'result': candidate['result'],
    'lastEvent': candidate['lastEvent'],
    'clock': candidate['clock'],
    'whiteClock': candidate['whiteClock'],
    'blackClock': candidate['blackClock'],
    'board': candidate['board'],
    'hand': candidate['hand'],
    'mana': candidate['mana'],
    'cardUsed': candidate['cardUsed'],
    'cardBlock': candidate['cardBlock'],
    'traps': candidate['traps'],
    'shields': candidate['shields'],
    'fog': candidate['fog'],
    'drawOffer': candidate['drawOffer'],
    'cancelOffer': candidate['cancelOffer'],
    'connection': candidate['connection'],
  });

  void _onBoardTap(int idx) {
    if (busy || _syncing || _finished || !_myTurn) return;
    if (_phase == 'card' && armedCard != null) {
      _handleCardTargetTap(idx);
      return;
    }
    if (_phase != 'move') return;
    final snapshot = _snapshot();
    final piece = snapshot.board[idx];
    if (selected != null && moveTargets.contains(idx)) {
      final from = selected!;
      setState(() {
        selected = null;
        moveTargets = {};
      });
      unawaited(_sendMove(from, idx));
      return;
    }
    setState(() {
      if (piece != null && piece.color == _viewer) {
        selected = idx;
        moveTargets = snapshot.legalFrom(idx).toSet();
      } else {
        selected = null;
        moveTargets = {};
      }
    });
  }

  Future<void> _sendMove(int from, int to) async {
    final moveCount = view['moveCount'];
    String? promotion;
    if (_requiresPromotion(from, to)) {
      promotion = await _choosePromotion();
      if (!mounted || promotion == null) return;
    }
    if (!mounted || _finished || !_myTurn || view['moveCount'] != moveCount) {
      return;
    }
    await _sendAction('move', from: from, to: to, promotion: promotion);
  }

  Future<String?> _choosePromotion() async {
    final choice = await showPromotionSheet(
      context,
      color: _viewer,
      pieceSet: GameStore.instance.data.pieceSet,
    );
    return switch (choice) {
      PieceType.queen => 'Q',
      PieceType.rook => 'R',
      PieceType.bishop => 'B',
      PieceType.knight => 'N',
      _ => null,
    };
  }

  void _onCardTap(String key, {bool chooseLevel = true}) {
    if (busy || _syncing || _finished || !_myTurn || _phase != 'card') return;
    final card = kCards[key];
    if (card == null) return;
    if (view['cardUsed'] == true) {
      setState(() => error = 'Bu turda zaten bir kart oynadın.');
      return;
    }
    if (_number(_cardBlockFor(_viewer)) > 0) {
      setState(() => error = 'Kartların bu tur engellendi.');
      return;
    }
    final minimumMana = minimumManaFor(card);
    if (_viewerMana < minimumMana) {
      setState(() => error = 'Mana yetersiz ($minimumMana gerekli).');
      return;
    }
    if (chooseLevel && card.upgradeable && card.level > 1) {
      unawaited(_showOnlineLevelChooser(card));
      return;
    }
    if (card.target == CardTarget.none) {
      _fireAction(_sendAction('card', cardKey: key));
      return;
    }
    final snapshot = _snapshot();
    final targets =
        key == 'glue'
            ? _glueFirstTargets(snapshot)
            : snapshot.cardTargets(key).toSet();
    if (targets.isEmpty) {
      setState(() => error = 'Bu kart için uygun hedef yok.');
      return;
    }
    setState(() {
      error = null;
      selected = null;
      moveTargets = {};
      armedCard = key;
      cardTargets = targets;
      gluePendingFirst = null;
    });
  }

  Future<void> _showOnlineLevelChooser(CardDef held) async {
    final moveCount = view['moveCount'];
    final key = await showCardLevelSheet(context, held, _viewerMana);
    if (!mounted || key == null || view['moveCount'] != moveCount) return;
    if (_viewerMana < kCards[key]!.mana) return;
    _onCardTap(key, chooseLevel: false);
  }

  void _handleCardTargetTap(int idx) {
    final key = armedCard;
    if (key == null) return;
    if (key == 'glue') {
      if (gluePendingFirst == null) {
        if (!cardTargets.contains(idx)) return;
        setState(() {
          gluePendingFirst = idx;
          cardTargets = _gluePartners(_snapshot(), idx);
        });
        return;
      }
      if (!cardTargets.contains(idx)) return;
      _fireAction(
        _sendAction(
          'card',
          cardKey: key,
          target: gluePendingFirst,
          secondaryTarget: idx,
        ),
      );
      return;
    }
    if (!cardTargets.contains(idx)) return;
    _fireAction(_sendAction('card', cardKey: key, target: idx));
  }

  Set<int> _glueFirstTargets(MatchState snapshot) {
    final out = <int>{};
    for (var i = 0; i < 64; i++) {
      final piece = snapshot.board[i];
      if (piece?.color == _viewer &&
          piece?.type == PieceType.pawn &&
          piece?.linkTo == null) {
        if (_gluePartners(snapshot, i).isNotEmpty) out.add(i);
      }
    }
    return out;
  }

  Set<int> _gluePartners(MatchState snapshot, int idx) {
    final out = <int>{};
    final file = Square.fileOf(idx), rank = Square.rankOf(idx);
    for (final delta in const [-1, 1]) {
      final nextFile = file + delta;
      if (nextFile < 0 || nextFile > 7) continue;
      final next = Square.of(nextFile, rank);
      final piece = snapshot.board[next];
      if (piece?.color == _viewer &&
          piece?.type == PieceType.pawn &&
          piece?.linkTo == null) {
        out.add(next);
      }
    }
    return out;
  }

  MatchState _snapshot() {
    final snapshot = MatchState.newGame();
    for (var i = 0; i < 64; i++) {
      snapshot.board[i] = null;
    }
    final board = view['board'];
    if (board is List) {
      for (var i = 0; i < 64 && i < board.length; i++) {
        final raw = board[i];
        if (raw is! Map) continue;
        final type = _pieceType(raw['t']?.toString());
        if (type == null) continue;
        snapshot.board[i] = MPiece(
          raw['c']?.toString() == 'B' ? PieceColor.black : PieceColor.white,
          type,
          frozen: _number(raw['frozen']),
          resist: _number(raw['resist']),
          barbarian: raw['barbarian'] == true,
          poisoned: raw['poisoned'] == true,
          poisonedDur: _number(raw['poisonedDur']),
          plagueUntil: _number(raw['plagueUntil']),
          trapped: _number(raw['trapped']),
          moved: raw['moved'] == true,
          resistLock: raw['resistLock'] == true,
          linkTo: _numberOrNull(raw['linkTo']),
          angryN: raw['angryN'] == true,
          angryB: raw['angryB'] == true,
          ghost: raw['ghost'] == true,
          ghostDur: _number(raw['ghostDur']),
        );
      }
    }
    snapshot.turn =
        view['turn']?.toString() == 'B' ? PieceColor.black : PieceColor.white;
    final ep = _number(view['epTarget'], fallback: -1);
    snapshot.epTarget = ep >= 0 && ep < 64 ? ep : null;
    snapshot.moveCount = _number(view['moveCount']);
    snapshot.halfmoveClock = _number(view['halfMove']);
    snapshot.cardUsed = view['cardUsed'] == true;
    final viewerHand = view['hand'];
    final hand =
        viewerHand is List
            ? viewerHand
                .map((value) => value.toString())
                .where((key) => kCards.containsKey(key))
                .toList()
            : <String>[];
    if (_viewer == PieceColor.white) {
      snapshot.whiteHand = hand;
    } else {
      snapshot.blackHand = hand;
    }
    final mana = view['mana'];
    if (mana is Map) {
      snapshot.mana[_viewer] = _number(
        mana[_viewer == PieceColor.white ? 'W' : 'B'],
      );
    }
    final blocks = view['blocks'];
    if (blocks is Map) {
      blocks.forEach((key, value) {
        snapshot.blocks[int.tryParse(key.toString()) ?? -1] = _number(value);
      });
      snapshot.blocks.remove(-1);
    }
    final cardBlocks = view['cardBlock'];
    if (cardBlocks is Map) {
      snapshot.cardBlock[PieceColor.white] = _number(cardBlocks['W']);
      snapshot.cardBlock[PieceColor.black] = _number(cardBlocks['B']);
    }
    final fog = view['fog'];
    if (fog is Map) {
      snapshot.fog[PieceColor.white] = _number(fog['W']);
      snapshot.fog[PieceColor.black] = _number(fog['B']);
    }
    final traps = view['traps'];
    if (traps is Map) {
      traps.forEach((rawKey, rawValue) {
        final index = int.tryParse(rawKey.toString());
        if (index == null || index < 0 || index >= 64 || rawValue is! Map) {
          return;
        }
        final owner =
            rawValue['by']?.toString() == 'B'
                ? PieceColor.black
                : PieceColor.white;
        final duration = _number(rawValue['duration'] ?? rawValue['dur']);
        final level = _number(
          rawValue['level'] ?? rawValue['lvl'],
          fallback: 1,
        );
        final revealedFor = <PieceColor>{};
        final rawRevealedBy = rawValue['revealedBy'];
        if (rawRevealedBy?.toString() == 'W') {
          revealedFor.add(PieceColor.white);
        } else if (rawRevealedBy?.toString() == 'B') {
          revealedFor.add(PieceColor.black);
        }
        snapshot.traps[index] = Trap(
          owner,
          duration,
          level,
          _number(rawValue['life'], fallback: duration),
          revealed: rawValue['revealed'] == true,
          revealedFor: revealedFor,
        );
      });
    }
    final shields = view['shields'];
    if (shields is Map) {
      shields.forEach((rawKey, rawValue) {
        final index = int.tryParse(rawKey.toString());
        if (index == null || index < 0 || index >= 64 || rawValue is! Map) {
          return;
        }
        final owner =
            rawValue['by']?.toString() == 'B'
                ? PieceColor.black
                : PieceColor.white;
        snapshot.shields[index] = Shield(
          owner,
          _number(rawValue['duration'] ?? rawValue['dur']),
        );
      });
    }
    final lastEvent = view['lastEvent'];
    if (lastEvent is Map) {
      snapshot.lastFrom = _numberOrNull(lastEvent['from']);
      snapshot.lastTo = _numberOrNull(lastEvent['to']);
    }
    final result = view['result'];
    if (result is Map) {
      switch (result['winner']?.toString()) {
        case 'W':
          snapshot.result = MatchResult.whiteWins;
          break;
        case 'B':
          snapshot.result = MatchResult.blackWins;
          break;
        case 'draw':
          snapshot.result = MatchResult.draw;
          break;
      }
    }
    return snapshot;
  }

  PieceType? _pieceType(String? value) {
    switch (value) {
      case 'P':
        return PieceType.pawn;
      case 'N':
        return PieceType.knight;
      case 'B':
        return PieceType.bishop;
      case 'R':
        return PieceType.rook;
      case 'Q':
        return PieceType.queen;
      case 'K':
        return PieceType.king;
      default:
        return null;
    }
  }

  int _number(dynamic value, {int fallback = 0}) =>
      value is num ? value.toInt() : fallback;

  int? _numberOrNull(dynamic value) => value is num ? value.toInt() : null;

  void _captureClockSync(Map<String, dynamic> candidate) {
    final serverNow = _number(candidate['serverNow']);
    if (serverNow <= 0) return;
    _clockServerNow = serverNow;
    _clockReceivedAt = _monotonicClock.elapsedMilliseconds;
    _clockReceivedElapsed = _clockReceivedAt;
  }

  String _clockLabel(PieceColor color) {
    final clock = view['clock'];
    if (clock is! Map) return '--:--';
    final key = color == PieceColor.white ? 'W' : 'B';
    var remaining = _number(clock[key]);
    if (clock['activeColor']?.toString() == key &&
        _clockServerNow > 0 &&
        _clockReceivedAt > 0) {
      final startedAt = _number(clock['startedAt']);
      final serverElapsed =
          startedAt > 0
              ? (_clockServerNow - startedAt)
                  .clamp(0, 24 * 60 * 60 * 1000)
                  .toInt()
              : 0;
      final clientElapsed =
          (_monotonicClock.elapsedMilliseconds - _clockReceivedElapsed)
              .clamp(0, 24 * 60 * 60 * 1000)
              .toInt();
      remaining =
          (remaining - serverElapsed - clientElapsed)
              .clamp(0, remaining)
              .toInt();
    }
    final totalSeconds = (remaining / 1000).ceil();
    return '${totalSeconds ~/ 60}:${(totalSeconds % 60).toString().padLeft(2, '0')}';
  }

  PieceColor get _viewer =>
      view['viewerColor']?.toString() == 'B'
          ? PieceColor.black
          : PieceColor.white;
  bool get _myTurn =>
      (view['turn']?.toString() == 'B') == (_viewer == PieceColor.black);
  String get _phase => view['phase']?.toString() ?? 'card';
  bool get _finished =>
      view['result'] is Map ||
      const {'finished', 'cancelled'}.contains(view['status']?.toString());

  String get _status {
    if (_finished) {
      final rawResult = view['result'];
      final result =
          rawResult is Map ? Map<String, dynamic>.from(rawResult) : null;
      if (view['status']?.toString() == 'cancelled' ||
          result?['type']?.toString() == 'cancelled') {
        return 'MAÇ İPTAL';
      }
      final winner = result?['winner']?.toString();
      if (winner == 'draw') return 'BERABERE';
      final viewer = view['viewerColor']?.toString();
      if (!const {'W', 'B'}.contains(winner) ||
          !const {'W', 'B'}.contains(viewer)) {
        return 'MAÇ TAMAMLANDI';
      }
      return winner == viewer ? 'ZAFER' : 'YENİLGİ';
    }
    if (_opponentDisconnected) return 'RAKİP YENİDEN BAĞLANIYOR';
    if (_drawOffer != null && _drawOffer!['bySelf'] != true) {
      return 'RAKİP BERABERLİK TEKLİF ETTİ';
    }
    if (_cancelOffer != null && _cancelOffer!['bySelf'] != true) {
      return 'RAKİP MAÇI İPTAL ETMEK İSTİYOR';
    }
    if (!_myTurn) return 'RAKİP OYNUYOR';
    return _phase == 'card' ? 'KART FAZI' : 'SIRA SENDE';
  }

  int get _viewerMana {
    final mana = view['mana'];
    if (mana is! Map) return 0;
    return _number(mana[_viewer == PieceColor.white ? 'W' : 'B']);
  }

  dynamic _cardBlockFor(PieceColor color) {
    final blocks = view['cardBlock'];
    if (blocks is! Map) return 0;
    return blocks[color == PieceColor.white ? 'W' : 'B'];
  }

  Map<String, dynamic>? _offer(String key) {
    final raw = view[key];
    return raw is Map ? Map<String, dynamic>.from(raw) : null;
  }

  Map<String, dynamic>? get _drawOffer => _offer('drawOffer');
  Map<String, dynamic>? get _cancelOffer => _offer('cancelOffer');
  bool get _openingCancellationAvailable => _number(view['moveCount']) < 3;

  bool get _opponentDisconnected {
    final connection = view['connection'];
    if (connection is! Map) return false;
    final opponent = connection['opponent'];
    if (opponent is! Map) return false;
    return opponent['state']?.toString() == 'TEMP_DISCONNECTED';
  }

  Future<bool> _confirmResign() async {
    final answer = await showMatchConfirmation(
      context,
      title: 'Maçtan ayrıl?',
      message:
          'Teslim olursan bu maç yenilgi olarak kaydedilir. Devam etmek istiyor musun?',
      confirmLabel: 'TESLİM OL',
    );
    return answer && mounted && !_finished;
  }

  Future<void> _resignFromBack() async {
    if (_leaveInProgress) return;
    _leaveInProgress = true;
    try {
      if (!await _confirmResign() || !mounted) return;
      final accepted = await _sendAction('resign');
      if (accepted && mounted && _finished) {
        setState(() => _allowPop = true);
        Navigator.of(context).pop();
      }
    } finally {
      _leaveInProgress = false;
    }
  }

  Future<void> _resignFromMenu() async {
    if (!await _confirmResign() || !mounted) return;
    _fireAction(_sendAction('resign'));
  }

  Future<void> _showMenu() async {
    if (!mounted || _accountBlocked || busy || _syncing || _finished) return;
    final drawOffer = _drawOffer;
    final cancelOffer = _cancelOffer;
    final action = await showMatchMenuSheet(context, [
      const MatchMenuEntry('resign', 'Teslim ol', LunoAssets.matchResign),
      if (drawOffer == null)
        const MatchMenuEntry(
          'offer_draw',
          'Beraberlik teklif et',
          LunoAssets.matchDraw,
        )
      else if (drawOffer['bySelf'] == true)
        const MatchMenuEntry(
          'cancel_draw',
          'Beraberlik teklifini geri çek',
          LunoAssets.matchDraw,
        ),
      if (_openingCancellationAvailable && cancelOffer == null)
        const MatchMenuEntry(
          'offer_cancel',
          'Maç iptali teklif et',
          LunoAssets.matchSettings,
        )
      else if (cancelOffer?['bySelf'] == true)
        const MatchMenuEntry(
          'cancel_cancel',
          'İptal teklifini geri çek',
          LunoAssets.matchSettings,
        ),
    ]);
    if (!mounted || action == null || busy || _syncing || _finished) return;
    if (action == 'resign') {
      await _resignFromMenu();
      return;
    }
    if (action == 'offer_draw' && _drawOffer != null) return;
    if (action == 'cancel_draw' && _drawOffer?['bySelf'] != true) return;
    if (action == 'offer_cancel' &&
        (!_openingCancellationAvailable || _cancelOffer != null)) {
      return;
    }
    if (action == 'cancel_cancel' && _cancelOffer?['bySelf'] != true) return;
    _fireAction(_sendAction(action));
  }

  Widget? _offerBanner() {
    if (_finished) return null;
    final drawOffer = _drawOffer;
    if (drawOffer != null) {
      final incoming = drawOffer['bySelf'] != true;
      return _proposalBanner(
        title:
            incoming
                ? 'Rakip beraberlik teklif etti.'
                : 'Beraberlik teklifin bekliyor.',
        firstLabel: incoming ? 'KABUL ET' : 'GERİ ÇEK',
        secondLabel: incoming ? 'REDDET' : null,
        onFirst:
            () => _fireAction(
              _sendAction(incoming ? 'accept_draw' : 'cancel_draw'),
            ),
        onSecond:
            incoming ? () => _fireAction(_sendAction('reject_draw')) : null,
      );
    }
    final cancelOffer = _cancelOffer;
    if (cancelOffer != null) {
      final incoming = cancelOffer['bySelf'] != true;
      return _proposalBanner(
        title:
            incoming
                ? 'Rakip maçın iptal edilmesini teklif ediyor.'
                : 'İptal teklifin bekliyor.',
        firstLabel: incoming ? 'KABUL ET' : 'GERİ ÇEK',
        secondLabel: incoming ? 'REDDET' : null,
        onFirst:
            () => _fireAction(
              _sendAction(incoming ? 'accept_cancel' : 'cancel_cancel'),
            ),
        onSecond:
            incoming ? () => _fireAction(_sendAction('reject_cancel')) : null,
      );
    }
    return null;
  }

  Widget _proposalBanner({
    required String title,
    required String firstLabel,
    required String? secondLabel,
    required VoidCallback onFirst,
    required VoidCallback? onSecond,
  }) {
    return MatchOfferBanner(
      title: title,
      firstLabel: firstLabel,
      secondLabel: secondLabel,
      onFirst: onFirst,
      onSecond: onSecond,
      enabled: !busy && !_syncing && !_finished,
    );
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot();
    return PopScope(
      canPop: _accountBlocked || _finished || _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_finished) unawaited(_resignFromBack());
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          title: const Text('SIRALI MAÇ'),
          actions: [
            IconButton(
              onPressed: _showMenu,
              tooltip: 'Maç menüsü',
              icon: const LunoArt(
                LunoAssets.matchSettings,
                width: 28,
                height: 28,
              ),
            ),
          ],
        ),
        body: Stack(
          fit: StackFit.expand,
          children: [
            const Opacity(
              opacity: .68,
              child: LunoArt(LunoAssets.gameplaySceneV28, fit: BoxFit.cover),
            ),
            SafeArea(
              child: Column(
                children: [
                  _players(),
                  AnimatedSwitcher(
                    duration: LunoMotion.adaptive(context, LunoMotion.phase),
                    child: Container(
                      key: ValueKey(_status),
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      color: const Color(0xEE263F43),
                      child: Text(
                        _status,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _finished ? LunoColors.gold : Colors.white,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                      child: Text(
                        error!,
                        style: const TextStyle(
                          color: LunoColors.danger,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  if (_offerBanner() case final banner?) banner,
                  Expanded(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: MatchBoardView(
                          match: snapshot,
                          viewer: _viewer,
                          selected: selected,
                          moveTargets: moveTargets,
                          cardTargets: cardTargets,
                          pieceSet: GameStore.instance.data.pieceSet,
                          onTap: _onBoardTap,
                        ),
                      ),
                    ),
                  ),
                  _bottomActions(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _players() {
    final player =
        view['player'] is Map
            ? Map<String, dynamic>.from(view['player'] as Map)
            : const <String, dynamic>{};
    final opponent =
        view['opponent'] is Map
            ? Map<String, dynamic>.from(view['opponent'] as Map)
            : const <String, dynamic>{};
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
      child: Row(
        children: [
          Expanded(
            child: _playerPill(
              usernameFromMap(player, fallback: 'Sen'),
              player['trophies'],
              LunoColors.gold,
              _viewer,
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              'VS',
              style: TextStyle(
                color: LunoColors.textDim,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Expanded(
            child: _playerPill(
              usernameFromMap(opponent, fallback: 'Rakip'),
              opponent['trophies'],
              const Color(0xFF8AD6C6),
              _viewer == PieceColor.white ? PieceColor.black : PieceColor.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _playerPill(
    String name,
    dynamic trophies,
    Color color,
    PieceColor clockColor,
  ) {
    return LunoSurface(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      borderRadius: BorderRadius.circular(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 3),
          Wrap(
            spacing: 8,
            runSpacing: 5,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const LunoArt(LunoAssets.statusTrophy, width: 28, height: 28),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      '${max(0, _number(trophies))}',
                      style: TextStyle(
                        color: color,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              LunoClock(
                revision: _clockRevision,
                labelBuilder: () => _clockLabel(clockColor),
                styleBuilder:
                    (label) => TextStyle(
                      color:
                          label.startsWith('0:')
                              ? LunoColors.danger
                              : Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bottomActions() {
    if (_finished) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
        child: SizedBox(
          width: double.infinity,
          child: LunoButton(
            onPressed: () {
              if (!mounted || ModalRoute.of(context)?.isCurrent == false) {
                return;
              }
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
            leading: const LunoArt(
              LunoAssets.matchContinue,
              width: 26,
              height: 26,
            ),
            label: 'ANA MENÜ',
          ),
        ),
      );
    }
    if (_phase == 'card') {
      return _onlineHand();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
      child: Row(
        children: [
          Expanded(
            child: _manaPill(
              'Mana',
              view['mana'] is Map
                  ? (view['mana'] as Map)[view['viewerColor']]
                  : 0,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'Tur ${max(0, _number(view['moveCount'])) ~/ 2 + 1}',
            style: const TextStyle(
              color: LunoColors.textDim,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _manaPill(String label, dynamic value) {
    return LunoSurface(
      color: const Color(0xEE1D383A),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      borderRadius: BorderRadius.circular(8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.water_drop_rounded,
            color: LunoColors.gold,
            size: 17,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              '$label ${_number(value).clamp(0, 10)}/10',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _onlineHand() {
    final rawHand = view['hand'];
    final hand =
        rawHand is List
            ? rawHand
                .map((value) => value.toString())
                .where((key) => kCards.containsKey(key))
                .toList()
            : <String>[];
    return Container(
      height: 216 + (MediaQuery.textScalerOf(context).scale(48) - 48),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xF0254548), Color(0xF012282B)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        border: Border(top: BorderSide(color: Color(0x665D8A7D))),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 2),
            child: Row(
              children: [
                Expanded(child: _manaPill('Mana', _viewerMana)),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    _myTurn ? 'Kartını seç' : 'Rakip kart seçiyor',
                    textAlign: TextAlign.end,
                    style: const TextStyle(
                      color: LunoColors.textDim,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                const gap = 6.0;
                final cardWidth =
                    ((constraints.maxWidth - 16 - gap * (hand.length - 1)) /
                            (hand.isEmpty ? 1 : hand.length))
                        .clamp(72.0, 84.0)
                        .toDouble();
                return ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  itemCount: hand.length,
                  separatorBuilder: (_, _) => const SizedBox(width: gap),
                  itemBuilder:
                      (context, i) =>
                          _onlineCardChip(hand[i], width: cardWidth),
                );
              },
            ),
          ),
          SizedBox(
            height: 54,
            width: double.infinity,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              child: LunoButton(
                label:
                    !_myTurn
                        ? 'RAKİP OYNUYOR'
                        : view['cardUsed'] == true
                        ? 'TAŞINI SEÇ'
                        : 'HAMLEYE GEÇ',
                icon: Icons.arrow_forward_rounded,
                backgroundArt: LunoAssets.battleActionV28,
                onPressed:
                    _myTurn && !busy && !_syncing && view['cardUsed'] != true
                        ? () => _fireAction(_sendAction('skip_card'))
                        : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _onlineCardChip(String key, {required double width}) {
    final card = kCards[key];
    if (card == null) return SizedBox(width: width);
    final affordable =
        !busy &&
        !_syncing &&
        _viewerMana >= minimumManaFor(card) &&
        view['cardUsed'] != true &&
        _number(_cardBlockFor(_viewer)) == 0 &&
        _myTurn;
    final armed = armedCard == key;
    return GestureDetector(
      onTap: affordable ? () => _onCardTap(key) : null,
      onLongPress: () => showCardInfo(context, key),
      child: AnimatedOpacity(
        duration: LunoMotion.adaptive(context, LunoMotion.cardSelect),
        opacity: affordable ? 1 : .68,
        child: AnimatedScale(
          scale: armed ? 1.025 : 1,
          duration: LunoMotion.adaptive(context, LunoMotion.cardSelect),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: LunoMotion.adaptive(context, LunoMotion.cardSelect),
            width: width,
            decoration: BoxDecoration(
              gradient:
                  armed
                      ? const LinearGradient(
                        colors: [Color(0xFFF3C957), Color(0xFFB77C28)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      )
                      : const LinearGradient(
                        colors: [Color(0xFF385A5D), Color(0xFF203B3F)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color:
                    armed ? const Color(0xFFFFF0A6) : const Color(0x7782ADA0),
                width: armed ? 2 : 1,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x55000000),
                  blurRadius: 6,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            padding: const EdgeInsets.all(3),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(child: LunoArt(LunoAssets.card(key, card.level))),
                const SizedBox(height: 1),
                SizedBox(
                  height: MediaQuery.textScalerOf(context).scale(25),
                  child: Center(
                    child: Text(
                      card.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 11,
                        height: 1.1,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                ResourceAmount.mana(card.mana, iconSize: 16, fontSize: 11),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
