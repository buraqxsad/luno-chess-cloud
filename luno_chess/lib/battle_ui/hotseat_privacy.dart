import 'package:flutter/material.dart';
import '../engine/piece.dart';
import '../i18n/battle_learning_copy.dart';
import '../i18n/battle_v1_copy.dart';
import '../i18n/luno_localizations.dart';
import 'layout.dart';
import 'tokens.dart';

/// Presentation consent only: never pauses or mutates the match authority.
class BattleHotseatPrivacy extends ChangeNotifier {
  PieceColor? _viewer;
  bool _revealed = false;
  int _epoch = 0;

  bool get revealed => _revealed;
  int get epoch => _epoch;

  bool observe(PieceColor viewer) {
    if (_viewer == viewer) return false;
    _viewer = viewer;
    conceal();
    return true;
  }

  void conceal() {
    _revealed = false;
    _epoch++;
    notifyListeners();
  }

  bool acknowledge(PieceColor viewer, int epoch) {
    if (_revealed || viewer != _viewer || epoch != _epoch) return false;
    _revealed = true;
    notifyListeners();
    return true;
  }

  void reset() {
    _viewer = null;
    conceal();
  }
}

class BattleHotseatCurtain extends StatelessWidget {
  final PieceColor side;
  final int Function() remaining;
  final VoidCallback? onReady, onLeave;

  const BattleHotseatCurtain({
    super.key,
    required this.side,
    required this.remaining,
    required this.onReady,
    required this.onLeave,
  });

  @override
  Widget build(BuildContext context) {
    final l = LunoLocalizations.of(context);
    final sideLabel = l.battle(
      side == PieceColor.white ? BattleCopy.white : BattleCopy.black,
    );
    return Scaffold(
      key: const ValueKey('hotseat-curtain'),
      backgroundColor: BattleTokens.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder:
              (context, constraints) => SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight:
                        (constraints.maxHeight - 48)
                            .clamp(0, double.infinity)
                            .toDouble(),
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const ExcludeSemantics(
                            child: Icon(
                              Icons.privacy_tip_outlined,
                              color: BattleTokens.moon,
                              size: 48,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Semantics(
                            header: true,
                            child: Text(
                              l.learning(
                                'Cihazı diğer oyuncuya ver',
                                'Pass the device',
                              ),
                              textAlign: TextAlign.center,
                              style: BattleTokens.title,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            sideLabel,
                            textAlign: TextAlign.center,
                            style: BattleTokens.title.copyWith(
                              color: BattleTokens.gold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Center(
                            child: BattleClock(
                              key: ValueKey('hotseat-clock-${side.name}'),
                              label: sideLabel,
                              remaining: remaining,
                              active: true,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            l.learning(
                              'Sırası gelen oyuncunun saati işlemeye devam eder.',
                              'The active player\'s clock keeps running.',
                            ),
                            textAlign: TextAlign.center,
                            style: BattleTokens.body,
                          ),
                          const SizedBox(height: 24),
                          FilledButton.icon(
                            key: const ValueKey('hotseat-ready'),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(48, 48),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              backgroundColor: BattleTokens.moon,
                              foregroundColor: BattleTokens.background,
                              textStyle: BattleTokens.title,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            onPressed: onReady,
                            icon: const Icon(Icons.lock_open),
                            label: Text(
                              l.learning('Hazırım', 'I am ready'),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextButton.icon(
                            key: const ValueKey('hotseat-leave'),
                            onPressed: onLeave,
                            icon: const Icon(Icons.home_outlined),
                            label: Text(l.battle(BattleCopy.leave)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
        ),
      ),
    );
  }
}
