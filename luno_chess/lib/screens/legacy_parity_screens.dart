import 'dart:async';

import 'package:flutter/material.dart' hide Text;
import '../widgets/luno_polish.dart';
import '../engine/ai.dart';

import '../i18n/luno_text.dart';
import '../match/match_state.dart';
import '../models/game_store.dart';
import '../models/profile_match_stats.dart';
import '../i18n/luno_localizations.dart';
import '../i18n/battle_learning_copy.dart';
import '../widgets/battle_lesson_stage.dart';
import '../battle_ui/mentor.dart';
import '../navigation/luno_account_scope.dart';
import '../navigation/luno_route.dart';
import '../services/luno_online_service.dart';
import '../services/luno_billing_service.dart';
import '../services/legal_link_service.dart';
import '../services/reward_claim_result.dart';
import '../services/account_operation_guard.dart';
import '../services/screen_request_timeouts.dart';
import '../theme/luno_assets.dart';
import '../theme/luno_theme.dart';
import '../widgets/luno_surface.dart';
import 'battle_practice_campaign.dart';
import 'battle_v1_screen.dart';

/// HTML sürümündeki tutorial akışının native karşılığı.
class TutorialScreen extends StatefulWidget implements LunoAccountScopedPage {
  final bool onboarding;
  final GameStore? playerStore;

  const TutorialScreen({super.key, this.onboarding = false, this.playerStore});

  @override
  State<TutorialScreen> createState() => _TutorialScreenState();
}

class _TutorialScreenState extends State<TutorialScreen> {
  final _copyScrollController = ScrollController(keepScrollOffset: false);
  int step = 0;
  bool _finishing = false;
  bool _lessonComplete = true;
  late final int _ownerRevision;
  GameStore get store => widget.playerStore ?? GameStore.instance;

  bool get _active =>
      mounted &&
      store.accountBindingRevision == _ownerRevision &&
      ModalRoute.of(context)?.isCurrent == true;

  Future<void> _advance(int expectedStep) async {
    if (!_active || _finishing || !_lessonComplete || step != expectedStep) {
      return;
    }
    if (step < 9) {
      setState(() {
        step++;
        _lessonComplete = !BattleLessonStage.requiresInteraction(step);
      });
      if (widget.onboarding) {
        unawaited(store.setTutorialStep(step));
      }
      return;
    }
    await _finish();
  }

  Future<void> _finish() async {
    if (!_active || _finishing) return;
    setState(() => _finishing = true);
    try {
      if (widget.onboarding) {
        await store.completeTutorial();
      } else {
        Navigator.of(context).pushReplacement(
          lunoRoute(BattlePracticeCampaign(replay: true, storeOverride: store)),
        );
      }
    } finally {
      if (mounted) setState(() => _finishing = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _ownerRevision = store.accountBindingRevision;
    if (widget.onboarding) {
      step = store.tutorialStep.clamp(0, 9).toInt();
    }
    _lessonComplete = !BattleLessonStage.requiresInteraction(step);
  }

  @override
  void dispose() {
    _copyScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = LunoLocalizations.of(context);
    final steps = l.battleLessons;
    final current = steps[step];
    final renderedStep = step;
    final last = step == steps.length - 1;
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const Opacity(
            opacity: .88,
            child: LunoArt(
              LunoAssets.phase2TutorialAcademy,
              fit: BoxFit.cover,
              alignment: Alignment.center,
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  LunoColors.bgDeep.withValues(alpha: .52),
                  LunoColors.bgDeep.withValues(alpha: .78),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 360;
                      final headingStyle =
                          compact
                              ? LunoType.sectionTitle.copyWith(
                                fontSize: 12,
                                letterSpacing: 0,
                              )
                              : LunoType.sectionTitle;
                      return Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${l.learning('REHBER', 'GUIDE')}  ${step + 1}/${steps.length}',
                              style: headingStyle,
                            ),
                          ),
                          if (!widget.onboarding)
                            IconButton(
                              key: const ValueKey('replay-guided-basics'),
                              tooltip: l.learning('Temel eğitimi tekrar aç', 'Replay the basics'),
                              onPressed: () {
                                if (!_active || _finishing) return;
                                Navigator.of(context).push(lunoRoute(
                                  BattlePracticeCampaign(guidedReplay: true, storeOverride: store),
                                ));
                              },
                              icon: const Icon(Icons.play_lesson_rounded),
                            ),
                          if (!widget.onboarding)
                            IconButton(
                              tooltip: l.learning(
                                'Luno Akademisi',
                                'Luno Academy',
                              ),
                              onPressed: () {
                                if (!_active || _finishing) return;
                                Navigator.of(context).push(
                                  lunoRoute(
                                    BattlePracticeCampaign(
                                      replay: true,
                                      storeOverride: store,
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.school_rounded),
                            ),
                          TextButton(
                            onPressed:
                                _finishing
                                    ? null
                                    : () {
                                      if (!_active) return;
                                      if (widget.onboarding) {
                                        unawaited(_finish());
                                      } else {
                                        Navigator.of(context).maybePop();
                                      }
                                    },
                            style:
                                compact
                                    ? TextButton.styleFrom(
                                      minimumSize: const Size(48, 48),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                      ),
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    )
                                    : null,
                            child: Text(l.learning('ATLA', 'SKIP')),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
                  child: LinearProgressIndicator(
                    value: (step + 1) / steps.length,
                    color: LunoColors.cyan,
                    backgroundColor: LunoColors.bgPanel2,
                    minHeight: 3,
                    semanticsLabel: l.learning(
                      'Eğitim ilerlemesi',
                      'Tutorial progress',
                    ),
                  ),
                ),
                Expanded(
                  child: Scrollbar(
                    controller: _copyScrollController,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      controller: _copyScrollController,
                      key: ValueKey('tutorial-copy-$renderedStep'),
                      padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 560),
                          child: LunoEntrance(
                            key: ValueKey('lesson-enter-$renderedStep'),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  current.title,
                                  style: LunoType.screenTitle.copyWith(
                                    fontFamily: 'Nunito',
                                    fontSize: 21,
                                    height: 1.15,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                LunoLessonSpeech(
                                  text: current.body,
                                  cue: renderedStep,
                                ),
                                const SizedBox(height: 12),
                                BattleLessonStage(
                                  key: ValueKey('lesson-stage-$renderedStep'),
                                  step: step,
                                  onCompletionChanged: (complete) {
                                    if (!_active ||
                                        step != renderedStep ||
                                        complete == _lessonComplete) {
                                      return;
                                    }
                                    setState(() => _lessonComplete = complete);
                                  },
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  current.hint,
                                  style: LunoType.bodyMuted.copyWith(
                                    height: 1.3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (!_lessonComplete)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Semantics(
                                liveRegion: true,
                                child: Text(
                                  l.learning(
                                    'Yukarıdaki denemeyi tamamla; sonra birlikte ilerleyelim.',
                                    'Complete the practice above, then we will continue.',
                                  ),
                                  textAlign: TextAlign.center,
                                  style: LunoType.bodyMuted.copyWith(
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ),
                          SizedBox(
                            width: double.infinity,
                            child: LunoButton(
                              backgroundArt:
                                  'assets/native_art/battle-action-face-v212.webp',
                              loading: _finishing,
                              onPressed:
                                  _finishing || !_lessonComplete
                                      ? null
                                      : () => _advance(renderedStep),
                              icon:
                                  last
                                      ? Icons.play_arrow_rounded
                                      : Icons.arrow_forward_rounded,
                              label:
                                  last
                                      ? widget.onboarding
                                          ? l.learning(
                                            'OYUNA GEÇ',
                                            'LET\'S PLAY',
                                          )
                                          : l.learning(
                                            'LUNO AKADEMİSİ',
                                            'LUNO ACADEMY',
                                          )
                                      : l.learning('DEVAM ET', 'CONTINUE'),
                            ),
                          ),
                          if (step > 0) ...[
                            const SizedBox(height: 5),
                            Center(
                              child: TextButton(
                                onPressed: () {
                                  if (!_active ||
                                      _finishing ||
                                      step != renderedStep ||
                                      step <= 0 ||
                                      ModalRoute.of(context)?.isCurrent !=
                                          true) {
                                    return;
                                  }
                                  final previousStep = step - 1;
                                  setState(() {
                                    step = previousStep;
                                    _lessonComplete =
                                        !BattleLessonStage.requiresInteraction(
                                          step,
                                        );
                                  });
                                  if (widget.onboarding) {
                                    unawaited(
                                      store.setTutorialStep(previousStep),
                                    );
                                  }
                                },
                                child: Text(l.learning('ÖNCEKİ', 'PREVIOUS')),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// HTML sonuc ekranındaki zafer, yenilgi ve beraberlik durumları.
class ResultScreen extends StatelessWidget {
  final MatchResult result;
  final AiLevel level;
  final int reward;
  final bool local;
  final int timeControlMinutes;
  final LunoOnlineService? online;

  const ResultScreen({
    super.key,
    required this.result,
    required this.level,
    required this.reward,
    this.local = false,
    this.timeControlMinutes = 10,
    this.online,
  });

  bool get won => result == MatchResult.whiteWins;
  bool get draw => result == MatchResult.draw;
  bool get celebration => won || (local && result == MatchResult.blackWins);

  @override
  Widget build(BuildContext context) {
    final title =
        local
            ? draw
                ? 'BERABERE'
                : result == MatchResult.whiteWins
                ? 'BEYAZ KAZANDI'
                : 'SİYAH KAZANDI'
            : won
            ? 'ZAFER'
            : draw
            ? 'BERABERE'
            : 'YENİLGİ';
    final subtitle =
        local
            ? 'Yüz yüze maç tamamlandı. Kupa ve ödül değişmedi.'
            : won
            ? 'Tahtanın kontrolünü elinde tuttun.'
            : draw
            ? 'İki taraf da avantajı korudu.'
            : 'Bu maç bitti; sıradaki hamle için yeniden dene.';
    final art =
        celebration
            ? LunoAssets.resultVictory
            : draw
            ? LunoAssets.resultDraw
            : LunoAssets.resultDefeat;
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (celebration)
            const LunoArt(LunoAssets.phase2ResultVictory, fit: BoxFit.cover),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xD9263A48), Color(0xF2152331)],
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LunoEntrance(
                      duration: LunoMotion.result,
                      child: LunoArt(art, width: 220, height: 220),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      title,
                      style: TextStyle(
                        color:
                            celebration
                                ? LunoColors.gold
                                : draw
                                ? Colors.white
                                : LunoColors.danger,
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      subtitle,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: LunoColors.textDim,
                        fontSize: 15,
                      ),
                    ),
                    if (!local && won && reward > 0) ...[
                      const SizedBox(height: 16),
                      LunoSurface(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const LunoArt(
                              LunoAssets.coin,
                              width: 38,
                              height: 38,
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                '+$reward altın',
                                style: const TextStyle(
                                  color: LunoColors.gold,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 18,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: LunoButton(
                        onPressed: () {
                          if (!context.mounted ||
                              ModalRoute.of(context)?.isCurrent == false) {
                            return;
                          }
                          Navigator.of(context).pushReplacement(
                            lunoRoute(
                              BattleV1Screen(
                                level: level,
                                local: local,
                                timeControlMinutes: timeControlMinutes,
                                deckOnline: online,
                              ),
                            ),
                          );
                        },
                        leading: const LunoArt(
                          LunoAssets.matchContinue,
                          width: 28,
                          height: 28,
                        ),
                        label: 'TEKRAR OYNA',
                      ),
                    ),
                    const SizedBox(height: 9),
                    SizedBox(
                      width: double.infinity,
                      child: LunoButton(
                        kind: LunoButtonKind.secondary,
                        onPressed: () {
                          if (!context.mounted ||
                              ModalRoute.of(context)?.isCurrent == false) {
                            return;
                          }
                          Navigator.of(
                            context,
                          ).popUntil((route) => route.isFirst);
                        },
                        icon: Icons.home_rounded,
                        label: 'ANA MENÜ',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class LunoPremiumScreen extends StatefulWidget
    implements LunoAccountScopedPage {
  const LunoPremiumScreen({
    super.key,
    this.online,
    this.playerStore,
    this.purchaseMembership,
    this.restoreMembership,
    this.billingService,
    this.membershipPrices = const {},
  });
  final LunoOnlineService? online;
  final GameStore? playerStore;
  final Future<void> Function(String productId)? purchaseMembership;
  final Future<void> Function()? restoreMembership;
  final LunoBillingService? billingService;
  final Map<String, String> membershipPrices;

  @override
  State<LunoPremiumScreen> createState() => _LunoPremiumScreenState();
}

class _LunoPremiumScreenState extends State<LunoPremiumScreen> {
  final _timeouts = ScreenRequestTimeouts();
  bool _busy = false;
  bool _loaded = false;
  bool _active = false;
  int _expiresAt = 0;
  int? _statusRevision;
  String _plan = 'luno_premium_month';
  GameStore get store => widget.playerStore ?? GameStore.instance;
  LunoOnlineService get online => widget.online ?? LunoOnlineService.instance;
  bool get _nativeBilling =>
      widget.billingService != null ||
      ((widget.online == null ||
              identical(widget.online, LunoOnlineService.instance)) &&
          (widget.playerStore == null ||
              identical(widget.playerStore, GameStore.instance)));
  LunoBillingService get billing =>
      widget.billingService ?? LunoBillingService.instance;
  String copy(String tr, String en) =>
      LunoLocalizations.of(context).isEnglish ? en : tr;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_refresh());
    });
  }

  @override
  void dispose() {
    _timeouts.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_busy || !mounted || ModalRoute.of(context)?.isCurrent != true) return;
    final guard = AccountOperationGuard(store, online);
    setState(() => _busy = true);
    try {
      await _timeouts.run(online.start(), const Duration(seconds: 12));
      guard.check();
      if (!online.isOnline) {
        throw const LunoApiException('online-unavailable', 0);
      }
      final result = await _timeouts.run(
        online.getPlayerState(),
        const Duration(seconds: 12),
      );
      guard.check();
      final state = result['state'];
      final membership = state is Map ? state['membership'] : null;
      if (result['ok'] != true ||
          membership is! Map ||
          membership['active'] is! bool ||
          membership['expiresAt'] is! num) {
        throw const FormatException('Missing authoritative membership');
      }
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
      store.applyServerState(Map<String, dynamic>.from(state as Map));
      setState(() {
        _active = membership['active'] == true;
        _expiresAt = (membership['expiresAt'] as num).toInt();
        _statusRevision = store.accountBindingRevision;
        _loaded = true;
      });
      if (_nativeBilling) {
        await _timeouts.run(billing.start(), const Duration(seconds: 20));
      }
    } catch (_) {
      if (mounted &&
          guard.isCurrent &&
          ModalRoute.of(context)?.isCurrent == true) {
        setState(() => _loaded = false);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _billing({bool restore = false}) async {
    if (_busy || !mounted || ModalRoute.of(context)?.isCurrent != true) return;
    final action = restore ? widget.restoreMembership : null;
    if (!_nativeBilling &&
        (restore ? action == null : widget.purchaseMembership == null)) {
      return;
    }
    final guard = AccountOperationGuard(store, online);
    setState(() => _busy = true);
    try {
      // Billing completion is not entitlement authority; refresh the server.
      if (restore) {
        if (action != null) {
          await action();
        } else {
          await billing.restore();
        }
      } else {
        if (widget.purchaseMembership != null) {
          await widget.purchaseMembership!(_plan);
        } else {
          await billing.purchase(_plan);
        }
      }
      guard.check();
    } catch (_) {
      if (mounted &&
          guard.isCurrent &&
          ModalRoute.of(context)?.isCurrent == true) {
        showLunoNotice(
          context,
          copy(
            'Satın alma doğrulanamadı. Tekrar deneyebilirsin.',
            'Purchase could not be verified. You can retry.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted &&
        guard.isCurrent &&
        ModalRoute.of(context)?.isCurrent == true) {
      await _refresh();
    }
  }

  Future<void> _manageSubscription() async {
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
    final guard = AccountOperationGuard(store, online);
    final opened = await LegalLinkService.openPlaySubscriptions();
    if (!opened &&
        mounted &&
        guard.isCurrent &&
        ModalRoute.of(context)?.isCurrent == true) {
      showLunoNotice(
        context,
        copy(
          'Google Play açılamadı. Play Store > Ödemeler ve abonelikler > Abonelikler bölümünü aç.',
          'Google Play could not open. Open Play Store > Payments and subscriptions > Subscriptions.',
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([store, if (_nativeBilling) billing]),
    builder: (context, _) {
      final confirmed =
          _loaded && _statusRevision == store.accountBindingRevision;
      final billingConfirmed = _nativeBilling && billing.latestSnapshot != null;
      final active =
          confirmed && !billingConfirmed
              ? _active
              : store.data.isMembershipActive;
      final expiresAt =
          confirmed && !billingConfirmed ? _expiresAt : store.data.premiumUntil;
      final product = _nativeBilling ? billing.products[_plan] : null;
      final billingBusy =
          _nativeBilling &&
          const {
            LunoBillingStatus.loading,
            LunoBillingStatus.purchasing,
            LunoBillingStatus.pending,
            LunoBillingStatus.verifying,
          }.contains(billing.status);
      final expiry =
          expiresAt > 0 ? DateTime.fromMillisecondsSinceEpoch(expiresAt) : null;
      return Scaffold(
        appBar: AppBar(title: const Text('LUNO PREMIUM')),
        body: LunoBackdrop(
          art: LunoAssets.phase2ShopShowcase,
          overlay: const Color(0xED111A25),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
            children: [
              const Center(
                child: LunoArt(
                  'assets/native_art/premium-crest-v30.png',
                  width: 112,
                  height: 112,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'LUNO PREMIUM',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: LunoColors.gold,
                  fontSize: 23,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                copy('Luno üyeliği', 'Luno membership'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: LunoColors.ivory, fontSize: 16),
              ),
              const SizedBox(height: 16),
              Text(
                active
                    ? copy('ÜYELİK AKTİF', 'MEMBERSHIP ACTIVE')
                    : confirmed
                    ? copy('ÜYELİK YOK', 'NO MEMBERSHIP')
                    : copy('ÜYELİK DOĞRULANMADI', 'MEMBERSHIP UNCONFIRMED'),
                key: const ValueKey('membership-status'),
                style: TextStyle(
                  color: active ? LunoColors.success : LunoColors.textDim,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (active && expiry != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    copy('Geçerlilik: ', 'Valid until: ') +
                        MaterialLocalizations.of(
                          context,
                        ).formatMediumDate(expiry),
                  ),
                ),
              const SizedBox(height: 18),
              for (final benefit in [
                (
                  Icons.workspace_premium_rounded,
                  copy(
                    'Üyelik profil çerçeveleri',
                    'Membership profile frames',
                  ),
                  copy(
                    'Premium ve Elit Taç profil çerçeveleri ile Premium biyografi çerçevesi.',
                    'Premium and Elite Crown profile frames, plus the Premium bio frame.',
                  ),
                ),
                (
                  Icons.verified_user_rounded,
                  copy('Hesabına bağlı üyelik', 'Account-bound membership'),
                  copy(
                    'Durum ve geçerlilik süresi sunucudan doğrulanır. Hesap değiştirdiğinde üyelik diğer hesaba aktarılmaz.',
                    'Status and expiry are server-verified. Switching accounts does not transfer membership.',
                  ),
                ),
                (
                  Icons.balance_rounded,
                  copy('Eşit rekabet', 'Fair competition'),
                  copy(
                    'Daha güçlü taş veya rekabetçi kart avantajı vermez.',
                    'No stronger pieces or competitive card advantage.',
                  ),
                ),
              ])
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(benefit.$1, color: LunoColors.gold, size: 26),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              benefit.$2,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              benefit.$3,
                              style: const TextStyle(
                                color: LunoColors.textDim,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              const Divider(height: 28),
              Text(
                copy(
                  'Luno Pass ayrı bir sezon ürünüdür. Üyeliğe dahil değildir.',
                  'Luno Pass is a separate seasonal product. It is not included in membership.',
                ),
                key: const ValueKey('membership-not-pass'),
                style: const TextStyle(color: LunoColors.ivory, height: 1.3),
              ),
              const SizedBox(height: 16),
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(
                    value: 'luno_premium_month',
                    label: Text(copy('Aylık', 'Monthly')),
                  ),
                  ButtonSegment(
                    value: 'luno_premium_year',
                    label: Text(copy('Yıllık', 'Yearly')),
                  ),
                ],
                selected: {_plan},
                onSelectionChanged:
                    _busy
                        ? null
                        : (value) => setState(() => _plan = value.single),
              ),
              const SizedBox(height: 12),
              if (widget.membershipPrices[_plan]?.isNotEmpty == true)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    widget.membershipPrices[_plan]!,
                    key: const ValueKey('membership-catalog-price'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: LunoColors.ivory,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              if (product != null) ...[
                Text(
                  '${product.localizedPrice} / ${copy(_plan.endsWith('month') ? 'ay' : 'yıl', _plan.endsWith('month') ? 'month' : 'year')}',
                  key: const ValueKey('membership-store-price'),
                  style: LunoType.screenTitle.copyWith(fontSize: 20),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  copy(
                    'Abonelik iptal edilmedikçe yenilenir. Ödemeyi ve iptali Google Play hesabından yönetebilirsin.',
                    'The subscription renews unless canceled. Manage payment and cancellation in your Google Play account.',
                  ),
                  style: LunoType.bodyMuted,
                ),
                const SizedBox(height: 12),
              ],
              LunoButton(
                key: const ValueKey('membership-purchase'),
                loading: _busy || billingBusy,
                onPressed:
                    _busy ||
                            billingBusy ||
                            active ||
                            (widget.purchaseMembership == null &&
                                (!_nativeBilling || product == null))
                        ? null
                        : () => unawaited(_billing()),
                label: copy('ABONELİK SEÇENEKLERİ', 'SUBSCRIPTION OPTIONS'),
              ),
              if (widget.purchaseMembership == null && product == null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    copy(
                      'Bu cihazda abonelik mağazası kullanılamıyor.',
                      'The subscription store is unavailable on this device.',
                    ),
                    style: const TextStyle(color: LunoColors.textDim),
                  ),
                ),
              Wrap(
                spacing: 12,
                children: [
                  TextButton.icon(
                    key: const ValueKey('membership-manage-subscription'),
                    onPressed: () => unawaited(_manageSubscription()),
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: Text(
                      copy(
                        'ABONELİĞİ YÖNET / İPTAL ET',
                        'MANAGE / CANCEL SUBSCRIPTION',
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _busy ? null : () => unawaited(_refresh()),
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(copy('DURUMU YENİLE', 'REFRESH STATUS')),
                  ),
                  TextButton.icon(
                    onPressed:
                        _busy ||
                                billingBusy ||
                                (widget.restoreMembership == null &&
                                    !_nativeBilling)
                            ? null
                            : () => unawaited(_billing(restore: true)),
                    icon: const Icon(Icons.restore_rounded),
                    label: Text(
                      copy('SATIN ALIMLARI GERİ YÜKLE', 'RESTORE PURCHASES'),
                    ),
                  ),
                ],
              ),
              if (_nativeBilling && billing.status == LunoBillingStatus.queued)
                TextButton.icon(
                  onPressed:
                      _busy ? null : () => unawaited(_billing(restore: true)),
                  icon: const Icon(Icons.sync),
                  label: Text(
                    copy('DOĞRULAMAYI TEKRAR DENE', 'RETRY VERIFICATION'),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

/// Başarımlar backend kataloğuyla aynı kimlikleri kullanır. İlerleme ve ödül
/// claim'i cihazdaki tahmini değerlerden değil, sunucunun döndürdüğü state'ten
/// okunur.
class AchievementsScreen extends StatefulWidget
    implements LunoAccountScopedPage {
  const AchievementsScreen({super.key, this.online, this.playerStore});
  final LunoOnlineService? online;
  final GameStore? playerStore;

  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen> {
  GameStore get store => widget.playerStore ?? GameStore.instance;
  LunoOnlineService get online => widget.online ?? LunoOnlineService.instance;
  late final AccountOperationGuard _entryOwner;
  AccountOperationGuard? _loadedOwner;
  bool _loadingRequest = false;
  final Map<Timer, void Function()> _pendingDeadlines = {};
  bool get _ownsSession => mounted && _entryOwner.isCurrent;
  bool get _canAct => _ownsSession && ModalRoute.of(context)?.isCurrent == true;

  Future<T> _bounded<T>(Future<T> operation, Duration duration) {
    final result = Completer<T>();
    late final Timer timer;
    void finish(void Function() complete) {
      if (result.isCompleted) return;
      timer.cancel();
      _pendingDeadlines.remove(timer);
      complete();
    }

    timer = Timer(duration, () {
      finish(
        () => result.completeError(TimeoutException('Achievements request')),
      );
    });
    _pendingDeadlines[timer] = () {
      result.completeError(StateError('Achievements screen disposed'));
    };
    operation.then(
      (value) => finish(() => result.complete(value)),
      onError:
          (Object error, StackTrace trace) =>
              finish(() => result.completeError(error, trace)),
    );
    return result.future;
  }

  @override
  void dispose() {
    for (final entry in _pendingDeadlines.entries) {
      entry.key.cancel();
      entry.value();
    }
    _pendingDeadlines.clear();
    super.dispose();
  }

  static const _items = <(String, String, String, int, String, int, int)>[
    ('first_win', 'İlk Zafer', 'İlk maçını kazan.', 1, 'wins', 100, 0),
    (
      'first_card',
      'Kart Ustası',
      'İlk kartını kullan.',
      1,
      'cardsPlayed',
      50,
      0,
    ),
    ('win_10', 'Acemi Savaşçı', '10 maç kazan.', 10, 'wins', 300, 0),
    ('win_50', 'Tahta Ustası', '50 maç kazan.', 50, 'wins', 1500, 0),
    ('win_100', 'Şampiyon', '100 maç kazan.', 100, 'wins', 3000, 15),
    ('win_500', 'Luno Efsanesi', '500 maç kazan.', 500, 'wins', 20000, 40),
    (
      'streak_3',
      'Sıcak Eller',
      '3 maç üst üste kazan.',
      3,
      'bestStreak',
      200,
      0,
    ),
    ('streak_5', 'Durmak Yok', '5 maçlık seri yap.', 5, 'bestStreak', 800, 0),
    (
      'streak_10',
      'Kesintisiz Taht',
      '10 maçlık seri yap.',
      10,
      'bestStreak',
      3000,
      10,
    ),
    ('arena_3', 'Hükümdar', '3. arenaya ulaş.', 3, 'arenaIdx', 500, 0),
    ('arena_5', 'İmparator', '5. arenaya ulaş.', 5, 'arenaIdx', 1500, 0),
    (
      'arena_7',
      'Luno Kraliyeti',
      'Luno Kraliyeti arenasına ulaş.',
      7,
      'arenaIdx',
      4000,
      15,
    ),
    (
      'arena_8',
      'Luno Legend',
      'Luno Legend arenasına ulaş.',
      8,
      'arenaIdx',
      10000,
      30,
    ),
    (
      'arena_9',
      'Luno Mythic',
      'Luno Mythic arenasına ulaş.',
      9,
      'arenaIdx',
      25000,
      75,
    ),
    ('draw_10', 'Denge Ustası', '10 beraberlik tamamla.', 10, 'draws', 400, 0),
    (
      'captures_100',
      'Tahta Temizleyici',
      '100 taş ele geçir.',
      100,
      'captures',
      700,
      0,
    ),
    (
      'checks_50',
      'Şah Ustası',
      '50 şah tehdidi oluştur.',
      50,
      'checks',
      900,
      0,
    ),
    (
      'promotions_5',
      'Terfi Ustası',
      '5 piyonu terfi ettir.',
      5,
      'promotions',
      900,
      5,
    ),
    (
      'cards_100',
      'Kart Koleksiyoncusu',
      '100 kart kullan.',
      100,
      'cardsPlayed',
      500,
      0,
    ),
    (
      'cards_500',
      'Kart Stratejisti',
      '500 kart kullan.',
      500,
      'cardsPlayed',
      3000,
      10,
    ),
    (
      'skin_3',
      'Stil Sahibi',
      '3 taş görünümü edin.',
      3,
      'ownedSkinsCount',
      600,
      0,
    ),
    (
      'skin_all',
      'Koleksiyoncu',
      '8 taş görünümünü tamamla.',
      8,
      'ownedSkinsCount',
      12000,
      30,
    ),
    (
      'friends_5',
      'Tahta Dostları',
      '5 arkadaş edin.',
      5,
      'friendsCount',
      300,
      0,
    ),
    ('chests_10', 'Sandık Avcısı', '10 sandık aç.', 10, 'chestsOpened', 800, 0),
    ('games_50', 'Maraton', 'Toplam 50 maç oyna.', 50, 'gamesPlayed', 400, 0),
    (
      'games_200',
      'Tahtanın Sesi',
      'Toplam 200 maç oyna.',
      200,
      'gamesPlayed',
      2000,
      0,
    ),
    (
      'login_7',
      'Sadık Oyuncu',
      '7 günlük giriş serisi yap.',
      7,
      'loginStreak',
      300,
      0,
    ),
    (
      'login_30',
      'Luno Müdavimi',
      '30 günlük giriş serisi yap.',
      30,
      'loginStreak',
      4000,
      15,
    ),
    ('level_10', 'Yükselen Yıldız', '10. seviyeye ulaş.', 10, 'level', 500, 0),
    ('level_25', 'Usta Oyuncu', '25. seviyeye ulaş.', 25, 'level', 2000, 0),
    (
      'daily_7',
      'Her Gün Tahtada',
      '7 günlük ödül serisi yap.',
      7,
      'dailyStreak',
      1000,
      0,
    ),
    (
      'premium_member',
      'Kraliyet Üyesi',
      'Premium üyeliği aç.',
      1,
      'isPremium',
      1000,
      25,
    ),
    (
      'premium_30',
      'Premium Elçisi',
      '30 gün Premium kal.',
      30,
      'premiumDays',
      5000,
      100,
    ),
  ];

  Map<String, dynamic> state = const {};
  List<Map<String, dynamic>> serverAchievements = const [];
  int friendsCount = 0;
  bool loading = true;
  bool refreshing = false;
  String? error;
  String? claiming;

  @override
  void initState() {
    super.initState();
    _entryOwner = AccountOperationGuard(store, online);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_load());
    });
  }

  Future<void> _load() async {
    if (!_canAct || _loadingRequest || claiming != null) return;
    _loadingRequest = true;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      await _bounded(online.start(), const Duration(seconds: 12));
      if (!_ownsSession) return;
      if (!online.isOnline) {
        throw const LunoApiException('online-unavailable', 0);
      }
      final result = await _bounded(
        online.getPlayerState(),
        const Duration(seconds: 12),
      );
      if (!_ownsSession) return;
      final rawState = result['state'];
      if (result['ok'] != true || rawState is! Map) {
        throw const FormatException('Unconfirmed achievements snapshot');
      }
      final nextState = Map<String, dynamic>.from(rawState);
      _snapshotAchievements(nextState);
      var nextFriends = 0;
      try {
        nextFriends =
            (await _bounded(
              online.friends(),
              const Duration(seconds: 5),
            )).length;
      } catch (_) {
        // Claim remains server-authoritative if this optional read fails.
      }
      if (!_ownsSession) return;
      _applySnapshot(nextState);
      setState(() {
        friendsCount = nextFriends;
      });
    } catch (_) {
      if (!_ownsSession) return;
      setState(() {
        _loadedOwner = null;
        state = const {};
        serverAchievements = const [];
        error = 'Başarımlar sunucudan yüklenemedi.';
      });
    } finally {
      _loadingRequest = false;
      if (_ownsSession) {
        setState(() {
          loading = false;
          refreshing = false;
        });
      }
    }
  }

  List<Map<String, dynamic>> _snapshotAchievements(
    Map<String, dynamic> snapshot,
  ) {
    final rewards = snapshot['rewards'];
    final rows = rewards is Map ? rewards['achievements'] : null;
    if (rows is! List) {
      throw const FormatException('Missing achievements snapshot');
    }
    return rows
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  void _applySnapshot(Map<String, dynamic> snapshot) {
    _entryOwner.check();
    final rows = _snapshotAchievements(snapshot);
    if (!mounted) return;
    store.applyServerState(snapshot);
    _entryOwner.check();
    setState(() {
      state = snapshot;
      serverAchievements = rows;
      _loadedOwner = _entryOwner;
    });
  }

  int _number(Object? value) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? 0;

  List<Map<String, dynamic>> get _achievementRows {
    if (serverAchievements.isNotEmpty) return serverAchievements;
    return _items
        .map(
          (item) => <String, dynamic>{
            'id': item.$1,
            'title': item.$2,
            'description': item.$3,
            'target': item.$4,
            'statKey': item.$5,
            'reward': {'gold': item.$6, 'gems': item.$7},
          },
        )
        .toList();
  }

  int _progress(String key, [Map<String, dynamic>? row]) {
    final serverProgress = row?['progress'];
    if (serverProgress is num) {
      return serverProgress.toInt().clamp(0, 1000000000).toInt();
    }
    final data = store.data;
    final stats =
        state['stats'] is Map
            ? Map<String, dynamic>.from(state['stats'] as Map)
            : const <String, dynamic>{};
    final inventory =
        state['inventory'] is Map
            ? Map<String, dynamic>.from(state['inventory'] as Map)
            : const <String, dynamic>{};
    final economy =
        state['economy'] is Map
            ? Map<String, dynamic>.from(state['economy'] as Map)
            : const <String, dynamic>{};
    final daily =
        economy['daily'] is Map
            ? Map<String, dynamic>.from(economy['daily'] as Map)
            : const <String, dynamic>{};
    final wins = _number(stats['wins'] ?? data.wins);
    final losses = _number(stats['losses'] ?? data.losses);
    final draws = _number(stats['draws']);
    return switch (key) {
      'arenaIdx' => _number(state['arenaIdx'] ?? data.arenaIdx) + 1,
      'gamesPlayed' => wins + losses + draws,
      'ownedSkinsCount' =>
        inventory['ownedSkins'] is List
            ? (inventory['ownedSkins'] as List).length
            : 0,
      'friendsCount' => friendsCount,
      'loginStreak' => _number(state['loginStreak']),
      'level' => _number(state['lvl'] ?? data.lvl),
      'dailyStreak' => _number(daily['streak'] ?? data.dailyStreak),
      'isPremium' =>
        state['passState'] is Map &&
                (state['passState'] as Map)['premium'] == true
            ? 1
            : 0,
      'premiumDays' => _number(state['premiumDays']),
      'draws' => _number(stats['draws'] ?? data.draws),
      'captures' => _number(stats['captures']),
      'checks' => _number(stats['checks']),
      'promotions' => _number(stats['promotions']),
      _ => _number(stats[key]),
    };
  }

  bool _claimed(String id, [Map<String, dynamic>? row]) {
    if (row?['claimed'] == true) return true;
    final claimed = state['achievementsClaimed'];
    return claimed is Map && claimed.containsKey(id);
  }

  String _rewardLabel(int gold, int gems) =>
      LunoLocalizations.of(context).translate(
        [if (gold > 0) '$gold altın', if (gems > 0) '$gems elmas'].join(' + '),
      );

  String _achievementAsset(String id) =>
      <String, String>{
        'draw-10': 'first-win',
        'captures-100': 'win-10',
        'checks-50': 'streak-3',
        'promotions-5': 'arena-5',
      }[id] ??
      id;

  Future<void> _claim(String achievementId) async {
    if (!_canAct ||
        loading ||
        _loadingRequest ||
        _loadedOwner?.isCurrent != true ||
        claiming != null ||
        achievementId.trim().isEmpty) {
      return;
    }
    final eligible = _achievementRows.any((row) {
      if (row['id'] != achievementId || _claimed(achievementId, row)) {
        return false;
      }
      final target = _number(row['target']);
      return target > 0 &&
          _progress(row['statKey']?.toString() ?? '', row) >= target;
    });
    if (!eligible) return;
    setState(() => claiming = achievementId);
    try {
      final result = await _bounded(
        online.claimAchievementReward(achievementId),
        const Duration(seconds: 12),
      );
      if (!_ownsSession) return;
      validateRewardClaimResult(result);
      _applySnapshot(Map<String, dynamic>.from(result['state'] as Map));
    } catch (_) {
      if (!mounted || !_canAct) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'İşlem doğrulanamadı. Bağlantı yenilendiğinde durumunu kontrol et.',
          ),
        ),
      );
    } finally {
      if (_ownsSession) setState(() => claiming = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('BAŞARIMLAR'),
        actions: [
          IconButton(
            onPressed:
                loading || refreshing || _loadingRequest || claiming != null
                    ? null
                    : () {
                      setState(() => refreshing = true);
                      unawaited(_load());
                    },
            tooltip: LunoLocalizations.of(context).translate('Yenile'),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: LunoBackdrop(
        art: 'assets/native_art/achievements-scene-v34.png',
        overlay: const Color(0x6611201A),
        focalPoint: const Alignment(0, -.18),
        child:
            loading
                ? const Center(
                  child: CircularProgressIndicator(color: LunoColors.gold),
                )
                : error != null
                ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const LunoArt(
                          LunoAssets.profileAchievements,
                          width: 80,
                          height: 80,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          error!,
                          textAlign: TextAlign.center,
                          style: LunoType.body,
                        ),
                        const SizedBox(height: 16),
                        LunoButton(
                          label: 'TEKRAR DENE',
                          icon: Icons.refresh_rounded,
                          backgroundArt: LunoAssets.actionSurfaceV27,
                          onPressed: () => unawaited(_load()),
                        ),
                      ],
                    ),
                  ),
                )
                : ListView.separated(
                  padding: const EdgeInsets.all(14),
                  itemCount: _achievementRows.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 9),
                  itemBuilder:
                      (_, index) => _achievementTile(_achievementRows[index]),
                ),
      ),
    );
  }

  Widget _achievementTile(Map<String, dynamic> item) {
    final id = item['id']?.toString() ?? '';
    final title = item['title']?.toString() ?? id;
    final description = item['description']?.toString() ?? '';
    final target = _number(item['target']);
    final statKey = item['statKey']?.toString() ?? '';
    final reward = item['reward'];
    final gold = reward is Map ? _number(reward['gold']) : 0;
    final gems = reward is Map ? _number(reward['gems']) : 0;
    final progress = _progress(statKey, item);
    final unlocked = id.trim().isNotEmpty && target > 0 && progress >= target;
    final claimed = _claimed(id, item);
    final assetId = _achievementAsset(id.replaceAll('_', '-'));
    return LunoSurface(
      color: unlocked ? LunoColors.bgRaised : LunoColors.bgPanel,
      borderRadius: BorderRadius.circular(8),
      child: Row(
        children: [
          SizedBox(
            width: 58,
            height: 58,
            child: Opacity(
              opacity: unlocked ? 1 : .72,
              child: LunoArt(LunoAssets.achievement(assetId)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: const TextStyle(
                    color: LunoColors.textDim,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                TweenAnimationBuilder<double>(
                  tween: Tween(
                    begin: 0,
                    end:
                        target > 0
                            ? (progress / target).clamp(0, 1).toDouble()
                            : 0,
                  ),
                  duration: LunoMotion.adaptive(context, LunoMotion.reward),
                  builder:
                      (context, value, _) => LinearProgressIndicator(
                        value: value,
                        minHeight: 5,
                        borderRadius: BorderRadius.circular(4),
                        backgroundColor: LunoColors.bgPanel,
                        color: claimed ? LunoColors.teal : LunoColors.gold,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  '$progress / $target  ·  ${_rewardLabel(gold, gems)}',
                  style: const TextStyle(
                    color: LunoColors.gold,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          if (claimed)
            Tooltip(
              message: LunoLocalizations.of(context).translate('Alındı'),
              child: const ClipOval(
                child: LunoArt(
                  'assets/native_art/arena-unlocked-v41.png',
                  width: 28,
                  height: 28,
                ),
              ),
            )
          else if (unlocked)
            IconButton.filledTonal(
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xFFDBBD68),
              ),
              onPressed: claiming == null ? () => unawaited(_claim(id)) : null,
              tooltip: LunoLocalizations.of(context).translate('Ödülü al'),
              icon: const Icon(Icons.redeem_rounded, color: Color(0xFF21382F)),
            )
          else
            Tooltip(
              message: LunoLocalizations.of(context).translate('Kilitli'),
              child: const ClipOval(
                child: LunoArt(
                  'assets/native_art/arena-lock-v41.png',
                  width: 28,
                  height: 28,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class MatchHistoryScreen extends StatelessWidget
    implements LunoAccountScopedPage {
  const MatchHistoryScreen({super.key, this.playerStore});
  final GameStore? playerStore;

  @override
  Widget build(BuildContext context) {
    final store = playerStore ?? GameStore.instance;
    final english = LunoLocalizations.of(context).isEnglish;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final data = store.data;
        final stats = ProfileMatchStats(
          wins: data.wins,
          losses: data.losses,
          draws: data.draws,
          games: data.gamesPlayed,
        );
        final bestStreak = data.bestStreak < 0 ? 0 : data.bestStreak;
        return Scaffold(
          appBar: AppBar(
            title: Text(english ? 'MATCH HISTORY' : 'MAÇ GEÇMİŞİ'),
          ),
          body: LunoBackdrop(
            art: LunoAssets.profileSceneV29,
            overlay: const Color(0x881C191D),
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LunoArt(
                      stats.games == 0
                          ? LunoAssets.menuLunoThink
                          : LunoAssets.resultVictory,
                      width: 140,
                      height: 140,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      stats.games == 0
                          ? (english
                              ? 'No completed matches yet'
                              : 'Henüz tamamlanmış maç yok')
                          : (english
                              ? '${stats.games} matches in your career'
                              : '${stats.games} maçlık kariyer özeti'),
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 7),
                    Text(
                      stats.games == 0
                          ? (english
                              ? 'Your results and streaks will appear after your first match.'
                              : 'İlk maçından sonra zaferlerini ve serilerini burada takip edeceksin.')
                          : (english
                              ? '${stats.wins} wins · ${stats.draws} draws · ${stats.losses} losses · best streak $bestStreak'
                              : '${stats.wins} galibiyet · ${stats.draws} beraberlik · ${stats.losses} mağlubiyet · en iyi seri $bestStreak'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: LunoColors.textDim,
                        height: 1.35,
                      ),
                    ),
                    if (stats.unclassified > 0) ...[
                      const SizedBox(height: 8),
                      Text(
                        english
                            ? '${stats.unclassified} matches have no recorded result.'
                            : '${stats.unclassified} maçın kayıtlı sonucu yok.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
