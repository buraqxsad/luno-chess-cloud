import 'dart:async';
import '../widgets/card_level_sheet.dart';
import '../widgets/promotion_sheet.dart';
import '../widgets/match_confirmation.dart';
import '../widgets/match_menu_sheet.dart';

import 'package:flutter/material.dart' hide Text;

import '../cards/card_catalog.dart';
import '../cards/card_def.dart';
import '../data/rank_catalog.dart';
import '../engine/ai.dart';
import '../engine/piece.dart';
import '../engine/square.dart';
import '../i18n/luno_text.dart';
import '../match/match_ai.dart';
import '../match/match_state.dart';
import '../models/game_store.dart';
import '../services/luno_audio_service.dart';
import '../navigation/luno_route.dart';
import '../theme/luno_assets.dart';
import '../theme/luno_theme.dart';
import '../widgets/card_info.dart';
import '../widgets/luno_clock.dart';
import '../widgets/luno_surface.dart';
import '../widgets/match_board.dart';
import '../widgets/resource_amount.dart';
import 'legacy_parity_screens.dart';
export '../widgets/game_time_control_picker.dart';

/// Kart + mana destekli maç ekranı.
///
/// Varsayılan akışta oyuncu beyaz, Luno eğitmeni siyahtır. [local] akışında
/// aynı motor iki insanın sırayla oynadığı yüz yüze maça dönüşür; böylece
/// HTML'deki yerel maç seçeneği de native akışta gerçek bir maça bağlıdır.
class GameScreen extends StatefulWidget {
  final AiLevel level;
  final bool local;
  final int timeControlMinutes;
  @visibleForTesting
  final DateTime Function()? clockNow;
  @visibleForTesting
  final MatchAi? aiOverride;

  const GameScreen({
    super.key,
    required this.level,
    this.local = false,
    this.timeControlMinutes = 10,
    this.clockNow,
    this.aiOverride,
  });

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with WidgetsBindingObserver {
  DateTime _now() => widget.clockNow?.call() ?? DateTime.now();
  late MatchState m;
  late final MatchAi ai = widget.aiOverride ?? MatchAi();

  int? selected;
  Set<int> moveTargets = {};
  String? armedKey;
  Set<int> cardTargets = {};
  int? gluePendingFirst;
  bool busy = false;
  bool _recorded = false;
  bool _resultOpened = false;
  int _lastReward = 0;
  int _myCards = 0;
  Timer? _clockTimer;
  int _whiteMs = 10 * 60 * 1000;
  int _blackMs = 10 * 60 * 1000;
  final ValueNotifier<int> _clockRevision = ValueNotifier(0);
  bool _clockPaused = false;
  bool _leaveDialogOpen = false;
  bool _restartDialogOpen = false;
  DateTime? _clockAnchor;
  int _lastClockSecond = -1;
  int _aiRunToken = 0;
  bool _aiRunning = false;
  bool _humanActionRunning = false;

  static const PieceColor me = PieceColor.white;

  @override
  void initState() {
    super.initState();
    unawaited(LunoAudioService.instance.setScene(LunoMusicScene.battle));
    final deck = GameStore.instance.resolvedDeck;
    m = MatchState.newGame(white: deck, black: deck);
    _whiteMs = _durationMs;
    _blackMs = _durationMs;
    WidgetsBinding.instance.addObserver(this);
    _startClock();
  }

  @override
  void dispose() {
    unawaited(LunoAudioService.instance.setScene(LunoMusicScene.menu));
    WidgetsBinding.instance.removeObserver(this);
    _stopClock();
    _clockRevision.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _clockPaused = false;
      _clockAnchor = _now();
      _startClock();
      _maybeAi();
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _consumeClockElapsed();
      _clockPaused = true;
      _stopClock();
      // An AI search may still be waiting or running when Android backgrounds
      // the activity. Invalidate it so resume can start a fresh decision and
      // avoid burning CPU while the game is not visible.
      _aiRunToken++;
      _aiRunning = false;
      if (mounted && busy) setState(() => busy = false);
    }
  }

  void _startClock() {
    _clockTimer?.cancel();
    if (m.over || _clockPaused) return;
    _clockAnchor ??= _now();
    _clockTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted || _clockPaused || m.over) return;
      _consumeClockElapsed();
    });
  }

  /// Deduct wall-clock time instead of assuming timer callbacks arrive on
  /// schedule. This keeps the AI's thinking time and frame stalls fair.
  bool _consumeClockElapsed() {
    if (m.over || _clockPaused) return false;
    final anchor = _clockAnchor ?? _now();
    final now = _now();
    final elapsed = now.difference(anchor).inMilliseconds;
    if (elapsed <= 0) return true;
    _clockAnchor = now;

    final isWhite = m.turn == PieceColor.white;
    final remaining = isWhite ? _whiteMs : _blackMs;
    final previousSecond = (remaining / 1000).ceil();
    final next = (remaining - elapsed).clamp(0, _durationMs).toInt();
    if (isWhite) {
      _whiteMs = next;
    } else {
      _blackMs = next;
    }
    if (next == 0) {
      _stopClock();
      if (mounted) {
        setState(() {
          if (!m.over) {
            m.result = isWhite ? MatchResult.blackWins : MatchResult.whiteWins;
          }
        });
        _recordIfNeeded();
      }
      return false;
    }
    final nextSecond = (next / 1000).ceil();
    if (nextSecond != previousSecond || nextSecond != _lastClockSecond) {
      _lastClockSecond = nextSecond;
      _clockRevision.value++;
    }
    return true;
  }

  bool _playCard(String key, {int? idx, int? idx2}) {
    if (!_consumeClockElapsed() || m.over) return false;
    final ok = m.playCard(key, idx: idx, idx2: idx2);
    _clockAnchor = _now();
    return ok;
  }

  int get _durationMs =>
      widget.timeControlMinutes.clamp(1, 30).toInt() * 60 * 1000;

  void _stopClock() {
    _clockTimer?.cancel();
    _clockTimer = null;
  }

  String _clockLabel(PieceColor color) {
    final totalSeconds =
        ((color == PieceColor.white ? _whiteMs : _blackMs) / 1000).ceil();
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  void _recordIfNeeded() {
    if (m.over && !_recorded) {
      _stopClock();
      _recorded = true;
      _lastReward = GameStore.instance.recordResult(
        win: m.result == MatchResult.whiteWins,
        level: widget.level,
        cardsPlayed: _myCards,
        draw: m.result == MatchResult.draw,
        grantProgress: !widget.local,
      );
      unawaited(
        LunoAudioService.instance.playEffect(
          widget.local
              ? LunoSound.uiClick
              : m.result == MatchResult.whiteWins
              ? LunoSound.victory
              : m.result == MatchResult.blackWins
              ? LunoSound.defeat
              : LunoSound.uiClick,
        ),
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _resultOpened) return;
        _resultOpened = true;
        final navigator = Navigator.of(context);
        final gameRoute = ModalRoute.of(context);
        if (gameRoute == null || !gameRoute.isActive) return;
        // A clock can expire while promotion or a match dialog is open.
        // Replace the game itself, never just the modal above it.
        navigator.popUntil((route) => route == gameRoute);
        navigator.pushReplacement(
          lunoRoute(
            ResultScreen(
              result: m.result,
              level: widget.level,
              reward: _lastReward,
              local: widget.local,
              timeControlMinutes: widget.timeControlMinutes,
            ),
          ),
        );
      });
    }
  }

  PieceColor get _activeColor => widget.local ? m.turn : me;
  bool get _myTurn =>
      mounted &&
      !_clockPaused &&
      ModalRoute.of(context)?.isCurrent == true &&
      !m.over &&
      !busy &&
      !_humanActionRunning &&
      (widget.local || m.turn == me);

  // ── Tahta dokunma ──
  void _onBoardTap(int idx) {
    if (!_myTurn) return;

    if (armedKey != null) {
      _handleCardTargetTap(idx);
      return;
    }

    // Hamle
    if (selected != null && moveTargets.contains(idx)) {
      final from = selected!;
      setState(() {
        selected = null;
        moveTargets = {};
      });
      unawaited(_playHumanMove(from, idx));
      return;
    }
    final p = m.board[idx];
    setState(() {
      if (p != null && p.color == _activeColor) {
        selected = idx;
        moveTargets = m.legalFrom(idx).toSet();
      } else {
        selected = null;
        moveTargets = {};
      }
    });
  }

  Future<void> _playHumanMove(int from, int to) async {
    if (!_myTurn) return;
    final pendingMatch = m;
    final pendingMove = m.moveCount;
    final pendingTurn = m.turn;
    _humanActionRunning = true;
    try {
      final piece = m.board[from];
      PieceType? promotion;
      if (piece?.type == PieceType.pawn &&
          (Square.rankOf(to) == 0 || Square.rankOf(to) == 7)) {
        promotion = await _choosePromotion();
        if (!mounted || promotion == null) return;
      }
      if (!mounted ||
          _clockPaused ||
          ModalRoute.of(context)?.isCurrent != true ||
          !identical(m, pendingMatch) ||
          m.moveCount != pendingMove ||
          m.turn != pendingTurn) {
        return;
      }
      if (!_consumeClockElapsed() || m.over) return;
      final captured = m.board[to] != null;
      var applied = false;
      setState(() {
        applied = m.makeMove(from, to, promotion: promotion);
      });
      _clockAnchor = _now();
      if (!applied) return;
      unawaited(
        LunoAudioService.instance.playEffect(
          captured ? LunoSound.capture : LunoSound.move,
        ),
      );
      _recordIfNeeded();
      _maybeAi();
    } finally {
      _humanActionRunning = false;
    }
  }

  Future<PieceType?> _choosePromotion() {
    return showPromotionSheet(
      context,
      color: _activeColor,
      pieceSet: GameStore.instance.data.pieceSet,
    );
  }

  void _handleCardTargetTap(int idx) {
    final key = armedKey!;
    if (key == 'glue') {
      if (gluePendingFirst == null) {
        if (cardTargets.contains(idx)) {
          setState(() {
            gluePendingFirst = idx;
            cardTargets = _gluePartners(idx);
          });
        } else {
          _disarm();
        }
      } else {
        if (cardTargets.contains(idx)) {
          final ok = _playCard('glue', idx: gluePendingFirst, idx2: idx);
          _afterCard(ok, false);
        } else {
          _disarm();
        }
      }
      return;
    }
    if (cardTargets.contains(idx)) {
      final skip = kCards[key]!.skipMove;
      final ok = _playCard(key, idx: idx);
      _afterCard(ok, skip);
    } else {
      _disarm();
    }
  }

  // ── Kart eline dokunma ──
  void _onCardTap(String key) {
    if (!_myTurn) return;
    if (m.cardUsed) {
      _toast('Bu tur kartını oynadın');
      return;
    }
    final actor = _activeColor;
    if ((m.cardBlock[actor] ?? 0) > 0) {
      _toast('Kartların engellendi');
      return;
    }
    final c = kCards[key]!;
    final minimumMana = minimumManaFor(c);
    if (m.manaOf(actor) < minimumMana) {
      _toast('Mana yetersiz ($minimumMana gerekli)');
      return;
    }
    if (c.upgradeable && c.level > 1) {
      _showLevelChooser(c);
    } else {
      _armOrPlay(key);
    }
  }

  Future<void> _showLevelChooser(CardDef c) async {
    final moveCount = m.moveCount;
    final actor = _activeColor;
    final key = await showCardLevelSheet(context, c, m.manaOf(actor));
    if (!mounted ||
        key == null ||
        !_myTurn ||
        m.moveCount != moveCount ||
        _activeColor != actor ||
        m.cardUsed ||
        (m.cardBlock[actor] ?? 0) > 0 ||
        m.manaOf(actor) < kCards[key]!.mana) {
      return;
    }
    _armOrPlay(key);
  }

  void _armOrPlay(String key) {
    final c = kCards[key]!;
    if (c.skipMove && m.inCheck(_activeColor)) {
      _toast('Şahtayken bu kartı oynayamazsın');
      return;
    }
    if (c.target == CardTarget.none) {
      final ok = _playCard(key);
      _afterCard(ok, c.skipMove);
      return;
    }
    setState(() {
      armedKey = key;
      selected = null;
      moveTargets = {};
      gluePendingFirst = null;
      cardTargets =
          key == 'glue' ? _glueFirstTargets() : m.cardTargets(key).toSet();
    });
    if (cardTargets.isEmpty) {
      _toast('Uygun hedef yok');
      _disarm();
    }
  }

  void _afterCard(bool ok, bool skip) {
    if (!ok) {
      _toast('Kart oynanamadı');
      _disarm();
      return;
    }
    _myCards++;
    unawaited(LunoAudioService.instance.playEffect(LunoSound.move));
    setState(() {
      armedKey = null;
      cardTargets = {};
      gluePendingFirst = null;
    });
    _recordIfNeeded();
    if (!widget.local && m.turn != me) {
      _maybeAi(); // skipMove sırayı geçirdi
    }
  }

  void _disarm() {
    setState(() {
      armedKey = null;
      cardTargets = {};
      gluePendingFirst = null;
    });
  }

  // ── Tutkal hedefleri ──
  Set<int> _glueFirstTargets() {
    final out = <int>{};
    for (int i = 0; i < 64; i++) {
      final p = m.board[i];
      if (p != null &&
          p.color == _activeColor &&
          p.type == PieceType.pawn &&
          p.linkTo == null) {
        if (_gluePartners(i).isNotEmpty) out.add(i);
      }
    }
    return out;
  }

  Set<int> _gluePartners(int idx) {
    final out = <int>{};
    final f = Square.fileOf(idx), r = Square.rankOf(idx);
    for (final df in const [-1, 1]) {
      final nf = f + df;
      if (nf < 0 || nf > 7) continue;
      final j = Square.of(nf, r);
      final p = m.board[j];
      if (p != null &&
          p.color == _activeColor &&
          p.type == PieceType.pawn &&
          p.linkTo == null) {
        out.add(j);
      }
    }
    return out;
  }

  // ── AI ──
  void _maybeAi() {
    if (!widget.local && !m.over && m.turn != me && !_aiRunning) {
      final token = ++_aiRunToken;
      unawaited(_runAi(token));
    }
  }

  Future<void> _runAi(int token) async {
    if (widget.local || _aiRunning) return;
    _aiRunning = true;
    if (mounted) setState(() => busy = true);
    try {
      while (token == _aiRunToken && mounted && !m.over && m.turn != me) {
        while (_clockPaused && mounted && token == _aiRunToken) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        if (!mounted || token != _aiRunToken || m.over || m.turn == me) break;
        await Future<void>.delayed(const Duration(milliseconds: 420));
        if (!mounted || token != _aiRunToken || m.over || m.turn == me) break;
        if (!_consumeClockElapsed() || m.over) break;

        final card = ai.maybeCard(m, widget.level);
        if (card != null) {
          _clockAnchor = _now();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Rakip: ${kCards[card]!.name}'),
                duration: const Duration(milliseconds: 900),
              ),
            );
            setState(() {});
          }
          if (m.over || m.turn == me) break; // skipMove sırayı geçirdi
          await Future<void>.delayed(const Duration(milliseconds: 420));
          if (!mounted || token != _aiRunToken || m.over || m.turn == me) break;
          if (!_consumeClockElapsed() || m.over) break;
        }

        final mv = await ai.chooseMoveAsync(m, widget.level);
        if (!mounted || token != _aiRunToken || m.over || m.turn == me) break;
        if (mv == null) {
          m.resolveTurnIfNoLegalMoves();
          if (mounted) setState(() {});
          continue;
        }
        if (!_consumeClockElapsed() || m.over) break;
        final aiPiece = m.board[mv[0]];
        final promotion =
            aiPiece?.type == PieceType.pawn &&
                    (Square.rankOf(mv[1]) == 0 || Square.rankOf(mv[1]) == 7)
                ? PieceType.queen
                : null;
        var applied = false;
        if (mounted) {
          final captured = m.board[mv[1]] != null;
          setState(() {
            applied = m.makeMove(mv[0], mv[1], promotion: promotion);
          });
          _clockAnchor = _now();
          if (applied) {
            unawaited(
              LunoAudioService.instance.playEffect(
                captured ? LunoSound.capture : LunoSound.move,
              ),
            );
          }
        }
        if (!applied) {
          final fallback = m.allLegal(m.turn);
          if (fallback.isEmpty) {
            m.resolveTurnIfNoLegalMoves();
          } else if (mounted) {
            final from = fallback.first[0], to = fallback.first[1];
            final piece = m.board[from];
            final fallbackPromotion =
                piece?.type == PieceType.pawn &&
                        (Square.rankOf(to) == 0 || Square.rankOf(to) == 7)
                    ? PieceType.queen
                    : null;
            setState(() {
              m.makeMove(from, to, promotion: fallbackPromotion);
            });
            _clockAnchor = _now();
            unawaited(LunoAudioService.instance.playEffect(LunoSound.move));
          }
        }
      }
      _recordIfNeeded();
    } catch (_) {
      // A failed AI turn must not leave the board locked or an unhandled
      // future error in the app. The current position remains authoritative.
      if (mounted && token == _aiRunToken) _toast('Rakip hamlesi yenilenemedi');
    } finally {
      if (token == _aiRunToken) {
        _aiRunning = false;
        if (mounted) setState(() => busy = false);
      }
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(milliseconds: 900)),
    );
  }

  void _reset() {
    _stopClock();
    _aiRunToken++;
    _aiRunning = false;
    setState(() {
      final deck = GameStore.instance.resolvedDeck;
      m = MatchState.newGame(white: deck, black: deck);
      _whiteMs = _durationMs;
      _blackMs = _durationMs;
      selected = null;
      moveTargets = {};
      armedKey = null;
      cardTargets = {};
      gluePendingFirst = null;
      busy = false;
      _humanActionRunning = false;
      _recorded = false;
      _resultOpened = false;
      _lastReward = 0;
      _myCards = 0;
      _clockAnchor = _now();
      _lastClockSecond = -1;
    });
    _clockRevision.value++;
    _startClock();
  }

  void _skipCardPhase() {
    if (!_myTurn) return;
    if (!_consumeClockElapsed() || m.over) return;
    setState(() {
      m.skipCardPhase();
      armedKey = null;
      cardTargets = {};
      gluePendingFirst = null;
      selected = null;
      moveTargets = {};
    });
    _recordIfNeeded();
    _maybeAi();
  }

  // ── Arayüz ──
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: m.over,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !m.over) unawaited(_confirmLeave());
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        backgroundColor: LunoColors.bgStage,
        body: Stack(
          fit: StackFit.expand,
          children: [
            const RepaintBoundary(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  LunoArt(
                    LunoAssets.gameplaySceneV28,
                    fit: BoxFit.cover,
                    alignment: Alignment.center,
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0x22050A13),
                          Color(0x66050810),
                          Color(0xB3050810),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SafeArea(
              top: true,
              bottom: true,
              left: true,
              right: true,
              child: Column(
                children: [
                  _matchTopBar(),
                  AnimatedSwitcher(
                    duration: LunoMotion.adaptive(context, LunoMotion.phase),
                    switchInCurve: LunoMotion.screenCurve,
                    switchOutCurve: LunoMotion.screenExitCurve,
                    transitionBuilder:
                        (child, animation) => FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, -.12),
                              end: Offset.zero,
                            ).animate(animation),
                            child: child,
                          ),
                        ),
                    child: KeyedSubtree(
                      key: ValueKey('${m.cardUsed}:$_myTurn'),
                      child: _phaseBanner(),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: MatchBoardView(
                          match: m,
                          selected: selected,
                          moveTargets: moveTargets,
                          cardTargets: cardTargets,
                          pieceSet: GameStore.instance.data.pieceSet,
                          onTap: _onBoardTap,
                        ),
                      ),
                    ),
                  ),
                  _hand(),
                  _youBar(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _matchTopBar() {
    return SizedBox(
      height: 66,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xF02B484B), Color(0xE6173034)],
          ),
          border: Border(bottom: BorderSide(color: Color(0x887E6130))),
        ),
        child: Row(
          children: [
            Expanded(
              child: _playerStrip(
                name: widget.local ? 'Siyah' : widget.level.name,
                sub: widget.local ? 'YÜZ YÜZE OYNA' : widget.level.persona,
                accent: LunoColors.gold,
                avatar:
                    widget.local
                        ? LunoAssets.avatar('av_pawn')
                        : LunoAssets.aiPortrait(widget.level.id),
                timerColor: PieceColor.black,
              ),
            ),
            _roundBadge(),
            IconButton(
              icon: const LunoArt(
                LunoAssets.matchSettings,
                width: 28,
                height: 28,
              ),
              tooltip: 'Maç menüsü',
              onPressed: _showMatchMenu,
            ),
            IconButton(
              icon: const LunoArt(
                LunoAssets.matchContinue,
                width: 28,
                height: 28,
              ),
              tooltip: 'Yeniden başlat',
              onPressed: _confirmRestart,
            ),
          ],
        ),
      ),
    );
  }

  Widget _roundBadge() {
    return Container(
      width: 34,
      height: 46,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: const Color(0xCC203B3F),
        border: Border.all(color: LunoColors.goldDeep.withValues(alpha: .7)),
        borderRadius: BorderRadius.circular(7),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'TUR',
              style: TextStyle(fontSize: 10, color: LunoColors.textDim),
            ),
            Text(
              '${(m.moveCount ~/ 2) + 1}',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _playerStrip({
    required String name,
    required String sub,
    required Color accent,
    required String avatar,
    required PieceColor timerColor,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 190;
        final avatarSize = compact ? 36.0 : 43.0;
        final gap = compact ? 4.0 : 7.0;
        final clockWidth = compact ? 45.0 : 54.0;
        final clockStyle = LunoType.timer.copyWith(
          fontSize: compact ? 15 : LunoType.timer.fontSize,
        );
        return Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 5 : 8,
            vertical: compact ? 4 : 7,
          ),
          child: Row(
            children: [
              Container(
                width: avatarSize,
                height: avatarSize,
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: const Color(0x662A514B),
                  shape: BoxShape.circle,
                  border: Border.all(color: accent.withValues(alpha: .8)),
                ),
                child: ClipOval(child: LunoArt(avatar, fit: BoxFit.contain)),
              ),
              SizedBox(width: gap),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: compact ? 11 : 13,
                        height: 1.15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: compact ? 9 : 10,
                        height: 1.15,
                        fontWeight: FontWeight.w700,
                        color: accent.withValues(alpha: .9),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              SizedBox(
                width: clockWidth,
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? 2 : 5,
                    vertical: compact ? 5 : 7,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xCC193236),
                    border: Border.all(color: accent.withValues(alpha: .55)),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: LunoClock(
                      revision: _clockRevision,
                      labelBuilder: () => _clockLabel(timerColor),
                      style: clockStyle,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _phaseBanner() {
    final label = m.cardUsed ? 'HAMLE AŞAMASI' : 'KART AŞAMASI';
    return Container(
      constraints: const BoxConstraints(minHeight: 38),
      width: double.infinity,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xEE263F43), Color(0xDD152D31)],
          ),
          border: Border(bottom: BorderSide(color: Color(0x55598378))),
        ),
        child: Row(
          children: [
            Container(
              margin: const EdgeInsets.only(left: 8, right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0x553DDC84),
                border: Border.all(
                  color: LunoColors.success.withValues(alpha: .7),
                ),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _myTurn ? 'Sıra sende' : 'Rakip oynuyor',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: LunoColors.gold,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }

  Widget _manaTrack() {
    final mana = m.manaOf(_activeColor).clamp(0, 10);
    return Semantics(
      label: 'Mana',
      value: '$mana / 10',
      child: ExcludeSemantics(
        child: Container(
          constraints: const BoxConstraints(minHeight: 34),
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              color: Color(0xEE1D383A),
              border: Border(top: BorderSide(color: Color(0xFF385A54))),
            ),
            child: Row(
              children: [
                const SizedBox(width: 8),
                const Text(
                  'MANA',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: LunoColors.gold,
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Row(
                    children: [
                      for (var i = 0; i < 10; i++)
                        Expanded(
                          child: AnimatedContainer(
                            duration: LunoMotion.adaptive(
                              context,
                              LunoMotion.phase,
                            ),
                            curve: Curves.easeOutCubic,
                            height: 12,
                            margin: const EdgeInsets.symmetric(horizontal: 1),
                            decoration: BoxDecoration(
                              color:
                                  i < mana
                                      ? const Color(0xFF5FE0C0)
                                      : const Color(0xFF304F50),
                              border: Border.all(
                                color: const Color(0x667CCFC3),
                              ),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    '$mana/10',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _youBar() {
    return SizedBox(
      height: 60,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xF02B484B), Color(0xE6173034)],
          ),
          border: Border(top: BorderSide(color: Color(0x887E6130))),
        ),
        child: _playerStrip(
          name: widget.local ? 'Beyaz' : 'Sen',
          sub:
              widget.local
                  ? 'Sıra: ${m.turn == PieceColor.white ? 'Beyaz' : 'Siyah'}'
                  : '${arenaForIndex(arenaIndexForPlayer(GameStore.instance.data.trophies, GameStore.instance.data.arenaIdx)).name} · ${GameStore.instance.data.trophies} kupa',
          accent: LunoColors.gold,
          avatar: LunoAssets.avatar(
            widget.local ? 'av_pawn' : GameStore.instance.data.avatarEmoji,
          ),
          timerColor: PieceColor.white,
        ),
      ),
    );
  }

  Future<void> _showMatchMenu() async {
    final pendingMatch = m;
    final action = await showMatchMenuSheet(context, [
      if (!m.over)
        MatchMenuEntry(
          'resign',
          widget.local ? 'Maçı bitir' : 'Teslim ol',
          LunoAssets.matchResign,
        ),
      const MatchMenuEntry(
        'restart',
        'Yeniden başlat',
        LunoAssets.matchContinue,
      ),
      const MatchMenuEntry('leave', 'Menüye dön', LunoAssets.matchSettings),
    ]);
    if (!_canApplyMatchIntent(pendingMatch)) return;
    switch (action) {
      case 'resign':
        await _confirmEndMatch();
      case 'leave':
        await _confirmLeave();
      case 'restart':
        await _confirmRestart();
    }
  }

  bool _canApplyMatchIntent(MatchState pendingMatch) =>
      mounted &&
      !_clockPaused &&
      ModalRoute.of(context)?.isCurrent == true &&
      identical(m, pendingMatch) &&
      !m.over;

  Future<void> _confirmRestart() async {
    if (!_canApplyMatchIntent(m) || _restartDialogOpen) return;
    final pendingMatch = m;
    _restartDialogOpen = true;
    try {
      final confirmed = await showMatchConfirmation(
        context,
        title: 'Yeniden başlat?',
        art: LunoAssets.matchContinue,
        confirmKind: LunoButtonKind.primary,
        message:
            'Bu tahtadaki hamleler sıfırlanacak ve yeni bir maç başlayacak.',
        confirmLabel: 'YENİDEN BAŞLAT',
      );
      if (confirmed && _canApplyMatchIntent(pendingMatch)) _reset();
    } finally {
      _restartDialogOpen = false;
    }
  }

  Future<void> _confirmEndMatch() async {
    if (!_canApplyMatchIntent(m)) return;
    final pendingMatch = m;
    final resigningColor = widget.local ? m.turn : me;
    final confirmed = await showMatchConfirmation(
      context,
      title: widget.local ? 'Maçı bitir?' : 'Teslim ol?',
      message:
          widget.local
              ? 'Sırası gelen oyuncu teslim olacak ve rakibi kazanacak.'
              : 'Teslim olursan bu maç yenilgi olarak kaydedilir.',
      confirmLabel: 'ONAYLA',
    );
    if (!confirmed ||
        !_canApplyMatchIntent(pendingMatch) ||
        (widget.local && m.turn != resigningColor)) {
      return;
    }
    setState(() {
      // In a local game the side that is currently at the board is the one
      // conceding; the other side must be shown as the winner.
      m.result =
          resigningColor == PieceColor.white
              ? MatchResult.blackWins
              : MatchResult.whiteWins;
    });
    _recordIfNeeded();
  }

  Future<void> _confirmLeave() async {
    if (!mounted ||
        _clockPaused ||
        ModalRoute.of(context)?.isCurrent != true ||
        _leaveDialogOpen) {
      return;
    }
    final pendingMatch = m;
    _leaveDialogOpen = true;
    if (m.over) {
      if (mounted) Navigator.of(context).pop();
      _leaveDialogOpen = false;
      return;
    }
    try {
      final confirmed = await showMatchConfirmation(
        context,
        title: 'Maçtan çık?',
        message: 'Bu karşılaşma tamamlanmadan kapanacak.',
        cancelLabel: 'KAL',
        confirmLabel: 'ÇIK',
      );
      if (confirmed && mounted && _canApplyMatchIntent(pendingMatch)) {
        Navigator.of(context).pop();
      }
    } finally {
      _leaveDialogOpen = false;
    }
  }

  Widget _hand() {
    if (m.over) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: LunoColors.gold,
            foregroundColor: LunoColors.bgDeep,
          ),
          onPressed: _reset,
          icon: const LunoArt(LunoAssets.matchContinue, width: 26, height: 26),
          label: const Text('Tekrar Oyna'),
        ),
      );
    }
    final hand = m.handOf(_activeColor);
    return Container(
      height: 200 + (MediaQuery.textScalerOf(context).scale(48) - 48),
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
          _manaTrack(),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                const horizontalPadding = 16.0;
                const gap = 6.0;
                final fittedWidth =
                    (constraints.maxWidth -
                        horizontalPadding -
                        gap * (hand.length - 1)) /
                    (hand.isEmpty ? 1 : hand.length);
                final cardWidth = fittedWidth.clamp(72.0, 84.0).toDouble();
                return ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  itemCount: hand.length,
                  separatorBuilder: (_, _) => const SizedBox(width: gap),
                  itemBuilder:
                      (context, i) => _cardChip(hand[i], width: cardWidth),
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
                label: m.cardUsed ? 'TAŞINI SEÇ' : 'HAMLEYE GEÇ',
                icon: Icons.arrow_forward_rounded,
                backgroundArt: LunoAssets.battleActionV28,
                onPressed: _myTurn && !m.cardUsed ? _skipCardPhase : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cardChip(String key, {required double width}) {
    final c = kCards[key]!;
    final affordable =
        m.manaOf(_activeColor) >= minimumManaFor(c) &&
        !m.cardUsed &&
        (m.cardBlock[_activeColor] ?? 0) == 0 &&
        _myTurn;
    final armed = armedKey == key;
    return GestureDetector(
      onTap: () => _onCardTap(key),
      onLongPress: () => showCardInfo(context, key),
      child: AnimatedOpacity(
        duration: LunoMotion.adaptive(context, LunoMotion.cardSelect),
        opacity: affordable ? 1 : 0.68,
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
                Expanded(child: LunoArt(LunoAssets.card(key, c.level))),
                const SizedBox(height: 1),
                SizedBox(
                  height: MediaQuery.textScalerOf(context).scale(25),
                  child: Center(
                    child: Text(
                      c.name,
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
                ResourceAmount.mana(c.mana, iconSize: 16, fontSize: 11),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
