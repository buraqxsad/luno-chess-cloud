import 'package:flutter/material.dart';

import '../battle_ui/mentor.dart';
import '../i18n/battle_learning_copy.dart';
import '../i18n/luno_localizations.dart';
import '../models/game_store.dart';
import '../navigation/luno_account_scope.dart';
import '../navigation/luno_route.dart';
import '../theme/luno_assets.dart';
import '../theme/luno_theme.dart';
import '../widgets/living_guide.dart';
import '../widgets/luno_surface.dart';
import 'battle_deck_screen.dart';
import 'battle_practice_campaign.dart';
import 'legacy_parity_screens.dart' show TutorialScreen;

/// Optional learning hub; its examples never reset onboarding or award rewards.
class GuideScreen extends StatefulWidget implements LunoAccountScopedPage {
  const GuideScreen({super.key, this.playerStore});
  final GameStore? playerStore;
  @override
  State<GuideScreen> createState() => _GuideScreenState();
}

class _GuideScreenState extends State<GuideScreen> {
  late final GameStore _ownerStore;
  late final int _ownerRevision;
  int? _selectedLesson = 2;
  int _mentorCue = 0;
  bool _opening = false;
  GameStore get store => widget.playerStore ?? GameStore.instance;
  bool get _active =>
      mounted &&
      identical(store, _ownerStore) &&
      store.accountBindingRevision == _ownerRevision &&
      ModalRoute.of(context)?.isCurrent == true;

  @override
  void initState() {
    super.initState();
    _ownerStore = store;
    _ownerRevision = store.accountBindingRevision;
  }

  Future<void> _open(Widget page) async {
    if (!_active || _opening) return;
    setState(() => _opening = true);
    try {
      await Navigator.of(context).push(lunoRoute(page));
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  void _replayBasics() => _open(
    BattlePracticeCampaign(guidedReplay: true, storeOverride: _ownerStore),
  );
  void _openAcademy() =>
      _open(BattlePracticeCampaign(replay: true, storeOverride: _ownerStore));

  @override
  Widget build(BuildContext context) {
    final l = LunoLocalizations.of(context);
    final lessons = l.battleLessons;
    final enabled = _active && !_opening;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.learning('REHBER', 'GUIDE')),
        actions: [
          IconButton(
            key: const ValueKey('replay-guided-basics'),
            tooltip: l.learning('Temel eğitimi tekrar aç', 'Replay the basics'),
            onPressed: enabled ? _replayBasics : null,
            icon: const Icon(Icons.play_lesson_rounded),
          ),
          IconButton(
            key: const ValueKey('guide-academy-shortcut'),
            tooltip: l.learning('Luno Akademisi', 'Luno Academy'),
            onPressed: enabled ? _openAcademy : null,
            icon: const Icon(Icons.school_rounded),
          ),
        ],
      ),
      body: LunoBackdrop(
        art: 'assets/native_art/guide-scene-v36.png',
        overlay: const Color(0xC5080F18),
        child: ListView(
          key: const ValueKey('guide-hub-scroll'),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _GuideWelcome(cue: _mentorCue),
                    const SizedBox(height: 16),
                    LunoButton(
                      key: const ValueKey('guide-practise-basics'),
                      label: l.learning(
                        'LUNO İLE UYGULAMALI ÖĞREN',
                        'LEARN BY PLAYING WITH LUNO',
                      ),
                      icon: Icons.play_arrow_rounded,
                      onPressed: enabled ? _replayBasics : null,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l.learning(
                        'Taşa dokun, kartını seç, sonucu gör. Kupa ve ödüllerin değişmez.',
                        'Tap a piece, choose a card, see the result. Your trophies and rewards stay the same.',
                      ),
                      style: LunoType.bodyMuted.copyWith(height: 1.4),
                    ),
                    const SizedBox(height: 22),
                    GuideTurnDemo(
                      onCue: () {
                        if (_active) setState(() => _mentorCue++);
                      },
                    ),
                    const SizedBox(height: 26),
                    Text(
                      l.learning(
                        'AKLINDAKİ KONUYU SEÇ',
                        'CHOOSE WHAT TO LEARN',
                      ),
                      style: LunoType.sectionTitle,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l.learning(
                        'Kısa kurallar, sonra gerçek bir deneme.',
                        'A short rule, then a real practice.',
                      ),
                      style: LunoType.bodyMuted,
                    ),
                    const SizedBox(height: 14),
                    for (var i = 0; i < lessons.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _GuideLessonTile(
                          index: i,
                          lesson: lessons[i],
                          selected: _selectedLesson == i,
                          onSelected: () {
                            if (!_active) return;
                            setState(() {
                              _selectedLesson = _selectedLesson == i ? null : i;
                              _mentorCue++;
                            });
                          },
                        ),
                      ),
                    const SizedBox(height: 12),
                    LunoButton(
                      key: const ValueKey('guide-interactive-lessons'),
                      label: l.learning(
                        'DERSLERİ UYGULAMALI DENE',
                        'TRY THE INTERACTIVE LESSONS',
                      ),
                      icon: Icons.touch_app_rounded,
                      kind: LunoButtonKind.secondary,
                      onPressed:
                          enabled
                              ? () => _open(
                                TutorialScreen(
                                  playerStore: _ownerStore,
                                  lessonMode: true,
                                ),
                              )
                              : null,
                    ),
                    const SizedBox(height: 12),
                    LunoButton(
                      key: const ValueKey('guide-academy'),
                      label: l.learning('LUNO AKADEMİSİ', 'LUNO ACADEMY'),
                      icon: Icons.school_rounded,
                      kind: LunoButtonKind.secondary,
                      onPressed: enabled ? _openAcademy : null,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l.learning(
                        'Dört antrenmanla çalış; varsa kaldığın yerden devam et.',
                        'Practise across four stages; resume your saved stage if you have one.',
                      ),
                      style: LunoType.bodyMuted.copyWith(height: 1.4),
                    ),
                    const SizedBox(height: 16),
                    LunoButton(
                      key: const ValueKey('guide-card-catalog'),
                      label: l.learning('SAVAŞ KARTLARI', 'BATTLE CARDS'),
                      icon: Icons.style_rounded,
                      kind: LunoButtonKind.secondary,
                      onPressed:
                          enabled
                              ? () => _open(
                                const BattleDeckScreen(catalogOnly: true),
                              )
                              : null,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GuideWelcome extends StatelessWidget {
  const _GuideWelcome({required this.cue});
  final Object cue;
  @override
  Widget build(BuildContext context) {
    final l = LunoLocalizations.of(context);
    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.learning('KARAR SENDE', 'YOUR NEXT MOVE'),
          style: LunoType.label.copyWith(
            color: LunoColors.cyan,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 9),
        Text(
          l.learning('Tahta. Kart. Karar.', 'Board. Card. Decision.'),
          style: LunoType.displayMedium.copyWith(fontSize: 25, height: 1.2),
        ),
        const SizedBox(height: 10),
        Text(
          l.learning(
            'Ben Luno. Birlikte deneyelim; sonra sıra sende.',
            'I am Luno. Let us try it together, then it is your turn.',
          ),
          style: LunoType.body.copyWith(height: 1.4),
        ),
      ],
    );
    final portrait = RepaintBoundary(
      child: DecoratedBox(
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [Color(0x665E3D93), Color(0x002F2147)],
          ),
        ),
        child: BattleMentor(
          cue: cue,
          width: 90,
          height: 128,
          child: Image.asset(
            LunoAssets.lunoPortrait,
            cacheWidth: 224,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
    return Container(
      key: const ValueKey('guide-mentor-welcome'),
      padding: const EdgeInsets.fromLTRB(18, 20, 10, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF263B48), Color(0xFF1B233C), Color(0xFF2F2147)],
        ),
        border: Border.all(color: LunoColors.gold.withValues(alpha: .7)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 380 &&
              MediaQuery.textScalerOf(context).scale(14) >= 21) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(alignment: Alignment.centerRight, child: portrait),
                const SizedBox(height: 6),
                copy,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: copy),
              const SizedBox(width: 8),
              portrait,
            ],
          );
        },
      ),
    );
  }
}

class _GuideLessonTile extends StatelessWidget {
  const _GuideLessonTile({
    required this.index,
    required this.lesson,
    required this.selected,
    required this.onSelected,
  });
  final int index;
  final BattleLesson lesson;
  final bool selected;
  final VoidCallback onSelected;
  @override
  Widget build(BuildContext context) {
    final l = LunoLocalizations.of(context);
    return Container(
      decoration: BoxDecoration(
        color: LunoColors.bgPanel.withValues(alpha: .96),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color:
              selected
                  ? LunoColors.gold.withValues(alpha: .8)
                  : LunoColors.line,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: selected,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                key: ValueKey('guide-lesson-$index'),
                borderRadius: BorderRadius.circular(14),
                onTap: onSelected,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: LunoColors.gold.withValues(alpha: .13),
                          shape: BoxShape.circle,
                        ),
                        child: ExcludeSemantics(
                          child: Text(
                            '${index + 1}',
                            style: const TextStyle(
                              color: LunoColors.gold,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                            textScaler: TextScaler.noScaling,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          lesson.title,
                          style: LunoType.sectionTitle.copyWith(
                            color:
                                selected ? LunoColors.gold : LunoColors.ivory,
                            height: 1.35,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        selected
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        color: LunoColors.gold,
                        size: 22,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          _GuideLessonReveal(
            child:
                selected
                    ? Padding(
                      key: ValueKey('guide-lesson-copy-$index'),
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Divider(color: LunoColors.line),
                          const SizedBox(height: 6),
                          Text(
                            lesson.body,
                            style: LunoType.body.copyWith(height: 1.5),
                          ),
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: LunoColors.cyan.withValues(alpha: .08),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              lesson.hint,
                              style: LunoType.bodyMuted.copyWith(
                                color: LunoColors.cyan,
                                height: 1.45,
                              ),
                            ),
                          ),
                          if (index == 1) ...[
                            const SizedBox(height: 10),
                            Text(
                              l.learning(
                                'Rok, geçerken alma ve piyon terfisi geçerlidir. Kart etkileri izin verilen hamleleri değiştirebilir; hiçbir hamle kendi şahını tehditte bırakamaz.',
                                'Castling, en passant and pawn promotion apply. Card effects can change available moves; no move may leave your own king in check.',
                              ),
                              style: LunoType.bodyMuted.copyWith(height: 1.4),
                            ),
                          ],
                        ],
                      ),
                    )
                    : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _GuideLessonReveal extends StatelessWidget {
  const _GuideLessonReveal({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    // A zero-duration AnimatedSize can re-dirty itself during layout in this
    // Flutter version. Reduced motion should render the stable panel directly.
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return AnimatedSize(
      duration: LunoMotion.panelEnter,
      alignment: Alignment.topCenter,
      curve: Curves.easeOutCubic,
      child: child,
    );
  }
}
