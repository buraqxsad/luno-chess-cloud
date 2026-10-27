import 'dart:async';
import 'package:flutter/material.dart';
import '../models/game_store.dart';
import '../navigation/luno_account_scope.dart';
import 'battle_v1_screen.dart';
import 'battle_welcome_screen.dart';
import '../services/first_session_telemetry.dart';

class BattlePracticeCampaign extends StatefulWidget
    implements LunoAccountScopedPage {
  final GameStore? storeOverride;
  final bool replay;
  final bool onboarding;
  final bool guidedReplay;
  const BattlePracticeCampaign({
    super.key,
    this.storeOverride,
    this.replay = false,
    this.onboarding = false,
    this.guidedReplay = false,
  }) : assert(!(replay && onboarding)),
       assert(!(guidedReplay && (replay || onboarding)));
  @override
  State<BattlePracticeCampaign> createState() => _BattlePracticeCampaignState();
}

class _BattlePracticeCampaignState extends State<BattlePracticeCampaign> {
  int _stage = 0;
  bool _completing = false;
  late final int _ownerRevision;
  late final GameStore _ownerStore;
  GameStore get store => widget.storeOverride ?? GameStore.instance;

  @override
  void initState() {
    super.initState();
    _ownerStore = store;
    _ownerRevision = store.accountBindingRevision;
    final telemetry = FirstSessionTelemetry.forStore(store);
    if (widget.onboarding) {
      unawaited(telemetry.recordFirstOpen(_ownerRevision));
      telemetry.record(FirstSessionEvent.introStarted, _ownerRevision);
    } else {
      telemetry.record(FirstSessionEvent.academyOpened, _ownerRevision);
    }
    if (widget.replay) {
      final saved = store.practiceStage;
      if (saved != null && saved < 4) _stage = saved;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            identical(store, _ownerStore) &&
            store.accountBindingRevision == _ownerRevision &&
            ModalRoute.of(context)?.isCurrent == true) {
          unawaited(store.beginOptionalAcademy(_ownerRevision));
        }
      });
    }
  }

  Future<void> _completeStage(int stage, int revision) async {
    if (!mounted ||
        _completing ||
        !identical(store, _ownerStore) ||
        store.accountBindingRevision != _ownerRevision ||
        ModalRoute.of(context)?.isCurrent != true ||
        (widget.replay && _stage != stage)) {
      return;
    }
    _completing = true;
    try {
      if (widget.onboarding) {
        await store.completeGuidedOnboarding(revision);
      } else if (widget.guidedReplay) {
        Navigator.of(context).pop();
        return;
      } else {
        await store.completePracticeStage(stage, revision);
      }
      if (!mounted ||
          !identical(store, _ownerStore) ||
          store.accountBindingRevision != _ownerRevision ||
          ModalRoute.of(context)?.isCurrent != true ||
          !widget.replay ||
          _stage != stage) {
        return;
      }
      if (stage < 3) {
        setState(() => _stage++);
      } else {
        Navigator.of(context).pop();
      }
    } finally {
      _completing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (_, _) {
        final stage =
            widget.onboarding || widget.guidedReplay
                ? 0
                : widget.replay
                ? _stage
                : store.practiceStage;
        final revision = store.accountBindingRevision;
        if (!identical(store, _ownerStore) || revision != _ownerRevision) {
          return const SizedBox.shrink();
        }
        if (stage == null ||
            stage >=
                (widget.onboarding ? GameStore.onboardingBattleCount : 4) ||
            (widget.onboarding && store.hasCompletedTutorial)) {
          return const SizedBox.shrink();
        }
        if (widget.onboarding &&
            store.onboardingBattleStage == 0 &&
            store.welcomeStep < GameStore.welcomeStepCount) {
          return BattleWelcomeScreen(
            key: ValueKey('welcome-$revision'),
            playerStore: store,
          );
        }
        return BattleV1Screen(
          key: ValueKey('practice-$revision-$stage'),
          practiceStage: stage,
          practiceOnboarding: widget.onboarding || widget.guidedReplay,
          guidedFirstMatch: widget.onboarding || widget.guidedReplay,
          practiceCanExit: widget.replay || widget.guidedReplay,
          practiceCheckpoint: widget.onboarding ? store.guidedLearning : null,
          onPracticeProgress:
              widget.onboarding
                  ? (checkpoint) =>
                      store.saveGuidedLearning(checkpoint, revision)
                  : null,
          onPracticeSkip:
              widget.onboarding
                  ? () => store.skipGuidedOnboarding(revision)
                  : null,
          onPracticeComplete: () => _completeStage(stage, revision),
        );
      },
    );
  }
}
