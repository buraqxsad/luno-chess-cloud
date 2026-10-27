import 'package:flutter/material.dart';

import '../battle_ui/art.dart';
import '../battle_ui/cards.dart';
import '../battle_ui/mentor.dart';
import '../battle_ui/primitives.dart';
import '../battle_ui/tokens.dart';
import '../battle_v1/model.dart';
import '../i18n/battle_v1_copy.dart';
import '../i18n/luno_localizations.dart';
import '../models/game_store.dart';
import '../navigation/luno_account_scope.dart';
import '../navigation/luno_account_modal.dart';
import '../services/first_session_telemetry.dart';
import '../theme/luno_assets.dart';
import '../theme/luno_theme.dart';
import '../widgets/tutorial_coach.dart';

class BattleWelcomeScreen extends StatefulWidget
    implements LunoAccountScopedPage {
  const BattleWelcomeScreen({super.key, this.playerStore});

  final GameStore? playerStore;

  @override
  State<BattleWelcomeScreen> createState() => _BattleWelcomeScreenState();
}

class _BattleWelcomeScreenState extends State<BattleWelcomeScreen>
    with WidgetsBindingObserver {
  late final GameStore _ownerStore;
  late final int _ownerRevision;
  bool _foreground = true;
  bool _advancing = false;

  GameStore get store => widget.playerStore ?? GameStore.instance;
  bool get _ownsScreen =>
      identical(store, _ownerStore) &&
      store.accountBindingRevision == _ownerRevision;
  bool get _active =>
      mounted &&
      _ownsScreen &&
      _foreground &&
      store.loaded &&
      !store.hasCompletedTutorial &&
      store.onboardingBattleStage == 0 &&
      store.welcomeStep >= 0 &&
      store.welcomeStep < GameStore.welcomeStepCount &&
      TickerMode.valuesOf(context).enabled &&
      ModalRoute.of(context)?.isCurrent == true;

  @override
  void initState() {
    super.initState();
    _ownerStore = store;
    _ownerRevision = store.accountBindingRevision;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (mounted) {
      setState(() => _foreground = state == AppLifecycleState.resumed);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _advance(int expectedStep) async {
    if (!_active || _advancing || store.welcomeStep != expectedStep) return;
    setState(() => _advancing = true);
    try {
      final accepted = await _ownerStore.advanceWelcomeStep(
        expectedStep,
        _ownerRevision,
      );
      if (accepted && _ownsScreen) {
        final telemetry = FirstSessionTelemetry.forStore(_ownerStore);
        telemetry.record(
          FirstSessionEvent.introStepCompleted,
          _ownerRevision,
          step: expectedStep,
        );
        if (expectedStep == GameStore.welcomeStepCount - 1) {
          telemetry.record(FirstSessionEvent.introFinished, _ownerRevision);
        }
      }
    } finally {
      // The campaign can replace this screen synchronously on the last step.
      if (mounted) setState(() => _advancing = false);
    }
  }

  Future<void> _skip() async {
    if (!_active || _advancing) return;
    final en = LunoLocalizations.of(context).isEnglish;
    final confirmed = await showLunoAccountDialog<bool>(
      context: context,
      playerStore: store,
      builder:
          (dialogContext) => AlertDialog(
            title: Text(
              en ? 'Skip training for now?' : 'Eğitimi şimdilik geç?',
            ),
            content: Text(
              en
                  ? 'You can replay the basics from the Guide. No rewards or trophies are granted.'
                  : 'Temel eğitimi rehberden tekrar açabilirsin. Ödül veya kupa verilmez.',
            ),
            actions: [
              TextButton(
                onPressed: () => dismissLunoAccountModal(dialogContext, false),
                child: Text(en ? 'Keep learning' : 'Öğrenmeye devam'),
              ),
              FilledButton(
                onPressed: () => dismissLunoAccountModal(dialogContext, true),
                child: Text(en ? 'Skip for now' : 'Şimdilik geç'),
              ),
            ],
          ),
    );
    if (confirmed == true && _active && !_advancing) {
      setState(() => _advancing = true);
      try {
        await store.skipGuidedOnboarding(_ownerRevision);
      } finally {
        if (mounted) setState(() => _advancing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _ownerStore,
    builder: (context, _) {
      if (!_ownsScreen ||
          store.hasCompletedTutorial ||
          store.onboardingBattleStage != 0 ||
          store.welcomeStep < 0 ||
          store.welcomeStep >= GameStore.welcomeStepCount) {
        return const SizedBox.shrink();
      }
      final l = LunoLocalizations.of(context);
      if (!store.loaded) {
        return Scaffold(
          backgroundColor: BattleTokens.background,
          body: Center(
            child: CircularProgressIndicator(semanticsLabel: l.preparing),
          ),
        );
      }
      final step = store.welcomeStep;
      final en = l.isEnglish;
      final title = switch (step) {
        0 => en ? "Hi, I'm Luno!" : 'Merhaba, ben Luno!',
        1 => en ? 'A card, then a move' : 'Önce kart, sonra hamle',
        _ => en ? 'Your first match is ready' : 'İlk maçın hazır',
      };
      final greeting = switch (step) {
        0 =>
          en
              ? "Let's learn together. I'll be beside you in your first match."
              : 'Birlikte öğrenelim. İlk maçında da yanında olacağım.',
        1 =>
          en
              ? 'Your first turn is a chess move only. On later turns, start with a card choice.'
              : 'İlk turunda yalnızca taş hamlesi yaparsın. Sonraki turlarda önce kartını seçersin.',
        _ =>
          en
              ? "Let's try a few moves with Baby Luno. We will practise cards together; no win is required."
              : 'Bebek Luno ile birkaç hamle deneyelim. Kartları birlikte kullanacağız; kazanmak şart değil.',
      };
      final cta = switch (step) {
        0 => en ? "Let's learn together" : 'Birlikte öğrenelim',
        1 => en ? "Let's meet the cards" : 'Kartları tanıyalım',
        _ => en ? 'Play with Baby Luno' : 'Bebek Luno ile oyna',
      };
      return PopScope(
        canPop: false,
        child: Scaffold(
          backgroundColor: BattleTokens.background,
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Luno Chess',
                              style: LunoType.screenTitle,
                            ),
                          ),
                          const SizedBox(width: 12),
                          IconButton(
                            key: const ValueKey('welcome-skip'),
                            tooltip:
                                en
                                    ? 'Skip training for now'
                                    : 'Eğitimi şimdilik geç',
                            onPressed: _active && !_advancing ? _skip : null,
                            icon: const Icon(Icons.skip_next_rounded),
                          ),
                          Semantics(
                            label:
                                en
                                    ? 'Welcome, step ${step + 1} of ${GameStore.welcomeStepCount}'
                                    : 'Karşılama, ${GameStore.welcomeStepCount} adımın ${step + 1}. adımı',
                            child: ExcludeSemantics(
                              child: Text(
                                '${step + 1} / ${GameStore.welcomeStepCount}',
                                key: const ValueKey('welcome-progress'),
                                style: BattleTokens.caption.copyWith(
                                  color: BattleTokens.gold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        key: ValueKey('welcome-content-$step'),
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Semantics(
                              header: true,
                              child: Text(
                                title,
                                key: ValueKey('welcome-title-$step'),
                                style: LunoType.displayMedium,
                              ),
                            ),
                            const SizedBox(height: 16),
                            TutorialCoach(
                              cue: 'welcome-$_ownerRevision-$step',
                              text: greeting,
                            ),
                            const SizedBox(height: 20),
                            ..._lesson(l, step),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: BattleCommand(
                        key: const ValueKey('welcome-next'),
                        label: cta,
                        icon:
                            step == 2
                                ? Icons.play_arrow_rounded
                                : Icons.arrow_forward_rounded,
                        primary: true,
                        loading: _advancing,
                        onPressed:
                            _active && !_advancing
                                ? () => _advance(step)
                                : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  List<Widget> _lesson(LunoLocalizations l, int step) {
    final en = l.isEnglish;
    if (step == 0) {
      return [
        _WelcomePoint(
          key: const ValueKey('welcome-objective'),
          leading: const SizedBox.square(
            dimension: 48,
            child: BattleArt('piece-w-king'),
          ),
          title: en ? 'Your goal: checkmate' : 'Hedefin: şah mat',
          text:
              en
                  ? 'Checkmate the opposing king. Cards add new options to your plan on the board.'
                  : 'Rakibin şahını mat et. Kartlar tahtadaki planına yeni seçenekler katar.',
        ),
      ];
    }
    if (step == 1) {
      final card = cardDefinitions[CardId.shelter]!;
      return [
        Container(
          key: const ValueKey('welcome-card-preview'),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: BattleTokens.surface,
            borderRadius: BorderRadius.circular(BattleTokens.radius),
            border: Border.all(color: BattleTokens.border),
          ),
          child: Row(
            children: [
              SizedBox.square(
                dimension: 72,
                child: BattleCardArt(card: card.id),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.battleCardName(card.id), style: BattleTokens.title),
                    const SizedBox(height: 4),
                    Text(
                      '${card.cost} mana',
                      key: const ValueKey('welcome-card-cost'),
                      style: BattleTokens.card.copyWith(
                        color: BattleTokens.mana,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      en ? 'Mana cost' : 'Mana bedeli',
                      style: BattleTokens.body,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _WelcomePoint(
          key: const ValueKey('welcome-card-phase'),
          icon: Icons.style_rounded,
          title: en ? 'Your card choice' : 'Kart seçimin',
          text:
              en
                  ? 'Play, discard or skip a card. Then move a chess piece.'
                  : 'Kart oyna, feda et veya geç. Sonra taş hamleni yap.',
        ),
        const SizedBox(height: 12),
        _WelcomePoint(
          key: const ValueKey('welcome-mana-rule'),
          leading: const BattleManaGlyph(size: 28),
          title: 'Mana',
          text:
              en
                  ? 'Start with 1. From your second own turn, gain +1 per turn, up to 6. Pay the cost shown on your card.'
                  : '1 ile başla. İkinci kendi turundan itibaren +1 gelir; sınır 6. Karttaki sayı kadar mana ödersin.',
        ),
        const SizedBox(height: 12),
        _WelcomePoint(
          key: const ValueKey('welcome-discard-rule'),
          icon: Icons.delete_outline_rounded,
          title: en ? 'Discard to make space' : 'Feda: elinde yer aç',
          text:
              en
                  ? 'No mana gained. You still make your chess move.'
                  : 'Mana kazandırmaz. Taş hamleni yine yaparsın.',
        ),
      ];
    }
    return [
      _WelcomePoint(
        key: const ValueKey('welcome-opponent'),
        leading: BattleMentor(
          cue: 'welcome-baby-$_ownerRevision',
          width: 72,
          height: 88,
          child: Image.asset(
            LunoAssets.aiBebek,
            cacheWidth: 192,
            fit: BoxFit.contain,
          ),
        ),
        title: en ? 'Baby Luno' : 'Bebek Luno',
        text: en ? 'Your first opponent.' : 'İlk rakibin.',
      ),
      const SizedBox(height: 12),
      _WelcomePoint(
        key: const ValueKey('welcome-clock'),
        icon: Icons.schedule_rounded,
        title: en ? 'Your turn, your clock' : 'Sıra sende, saat sende',
        text:
            en
                ? 'The clock is stopped in training. In normal matches, your time runs on your turn, even while choosing a card.'
                : 'Eğitimde saat durur. Normal maçta sıra sendeyken süren akar; kart seçerken de durmaz.',
      ),
      const SizedBox(height: 16),
      _WelcomePoint(
        key: const ValueKey('welcome-coaching'),
        icon: Icons.style_rounded,
        title:
            en
                ? 'A little help when you need it'
                : 'İhtiyacın olduğunda yardım',
        text:
            en
                ? 'I will point to legal moves and useful card targets. Your completed exercises are saved.'
                : 'Yasal hamleleri ve uygun kart hedeflerini işaret edeceğim. Tamamladığın alıştırmalar saklanır.',
      ),
      const SizedBox(height: 12),
      _WelcomePoint(
        key: const ValueKey('welcome-free-play'),
        icon: Icons.open_with_rounded,
        title: en ? 'The choices are yours' : 'Seçimler senin',
        text:
            en
                ? 'Try four chess moves, a targeted card and a discard. Use Skip Card too, then continue without finishing a full match.'
                : 'Dört taş hamlesi, hedefli kart ve feda dene. Kartı Geç düğmesini de kullan, sonra tam maçı bitirmeden devam edebilirsin.',
      ),
    ];
  }
}

class _WelcomePoint extends StatelessWidget {
  const _WelcomePoint({
    super.key,
    required this.title,
    required this.text,
    this.icon,
    this.leading,
  });

  final String title, text;
  final IconData? icon;
  final Widget? leading;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      ExcludeSemantics(
        child: leading ?? Icon(icon, size: 28, color: BattleTokens.gold),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: BattleTokens.title),
            const SizedBox(height: 4),
            Text(text, style: BattleTokens.body.copyWith(height: 1.35)),
          ],
        ),
      ),
    ],
  );
}
