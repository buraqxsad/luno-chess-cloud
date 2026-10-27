import 'dart:async';

import 'package:flutter/material.dart' hide Text;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'data/username.dart';
import 'screens/home_screen.dart';
import 'screens/battle_practice_campaign.dart';
import 'models/game_store.dart';
import 'models/app_settings.dart';
import 'services/luno_online_service.dart';
import 'services/luno_audio_service.dart';
import 'services/account_operation_guard.dart';
import 'services/profile_update_result.dart';
import 'services/product_telemetry.dart';
import 'services/luno_billing_service.dart';
import 'services/ugc_consent.dart';
import 'i18n/luno_localizations.dart';
import 'i18n/luno_text.dart';
import 'i18n/battle_learning_copy.dart';
import 'theme/luno_assets.dart';
import 'theme/luno_theme.dart';
import 'widgets/luno_surface.dart';
import 'widgets/google_account_restore.dart';

class LunoAppShell extends StatefulWidget {
  const LunoAppShell({super.key});

  @override
  State<LunoAppShell> createState() => _LunoAppShellState();
}

class _LunoAppShellState extends State<LunoAppShell>
    with WidgetsBindingObserver {
  (String, int, int)? _measurementOwner;
  bool _measurementScheduled = false;
  StreamSubscription<LunoBillingSnapshot>? _billingSnapshots;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    GameStore.instance.addListener(_scheduleMeasurementBinding);
    LunoOnlineService.instance.addListener(_scheduleMeasurementBinding);
    _billingSnapshots = LunoBillingService.instance.snapshots.listen((
      snapshot,
    ) {
      final store = GameStore.instance;
      if (mounted &&
          LunoBillingService.instance.isCurrent(snapshot.owner) &&
          store.accountUid == snapshot.owner.uid) {
        store.applyServerState(Map<String, dynamic>.from(snapshot.state));
      }
    });
    _scheduleMeasurementBinding();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    GameStore.instance.removeListener(_scheduleMeasurementBinding);
    LunoOnlineService.instance.removeListener(_scheduleMeasurementBinding);
    ProductTelemetry.instance.unbind();
    unawaited(_billingSnapshots?.cancel());
    unawaited(LunoBillingService.instance.stop());
    super.dispose();
  }

  void _scheduleMeasurementBinding() {
    if (_measurementScheduled || !mounted) return;
    _measurementScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measurementScheduled = false;
      if (!mounted) return;
      final store = GameStore.instance, online = LunoOnlineService.instance;
      final uid = online.user?.uid;
      if (!online.ready ||
          uid == null ||
          store.accountUid != uid ||
          online.accountFailure != null) {
        if (_measurementOwner != null) ProductTelemetry.instance.unbind();
        _measurementOwner = null;
        if (LunoBillingService.instance.owner != null) {
          unawaited(LunoBillingService.instance.stop());
        }
        return;
      }
      final owner = (uid, store.accountBindingRevision, online.accountRevision);
      if (_measurementOwner == owner &&
          ProductTelemetry.instance.hasCurrentBinding) {
        return;
      }
      _measurementOwner = owner;
      unawaited(ProductTelemetry.instance.bind(store: store, online: online));
      unawaited(LunoBillingService.instance.start().catchError((Object _) {}));
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Immersive mode can be reset by Android after an external activity or
      // an interruption. Restore it only after Flutter is visible again.
      unawaited(
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
      );
      _measurementOwner = null;
      _scheduleMeasurementBinding();
      return;
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      // These are intentionally fire-and-waitable: the store coalesces writes,
      // and the returned futures keep the latest snapshot alive during the
      // short window before Android backgrounds or kills the process.
      unawaited(GameStore.instance.flush());
      unawaited(LunoSettings.instance.flush());
      unawaited(ProductTelemetry.instance.flush());
    }
  }

  @override
  void didHaveMemoryPressure() {
    // Release decoded images that are no longer displayed. Live board and
    // currently visible UI images remain cached, preventing a visual reload.
    PaintingBinding.instance.imageCache.clearLiveImages();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: LunoSettings.instance,
      builder: (context, _) {
        final settings = LunoSettings.instance;
        return MaterialApp(
          title: 'Luno Chess',
          debugShowCheckedModeBanner: false,
          locale: Locale(settings.languageCode),
          supportedLocales: LunoLocalizations.supportedLocales,
          localizationsDelegates: const [
            LunoLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: LunoTheme.darkFor(settings.language),
          home: const _StartupGate(),
        );
      },
    );
  }
}

/// Native equivalent of the final HTML loader. It keeps the first frame
/// visually stable while local progress and the Firebase boot happen in the
/// background, then hands off to the real native menu.
class _StartupGate extends StatefulWidget {
  const _StartupGate();

  @override
  State<_StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<_StartupGate>
    with WidgetsBindingObserver {
  static const _minimumArtworkTime = Duration(milliseconds: 1500);
  final _artworkTime = Stopwatch();
  Timer? _loadingTimer;
  bool _artworkShown = false;
  bool _foreground = true;
  bool ready = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // System UI calls happen after the first frame so Android launch cannot
      // wait on platform-channel work before showing the Luno loader.
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      unawaited(LunoAudioService.instance.setScene(LunoMusicScene.menu));
    });
  }

  void _onArtworkShown() {
    if (!mounted || _artworkShown) return;
    _artworkShown = true;
    _scheduleHandoff();
  }

  void _scheduleHandoff() {
    _loadingTimer?.cancel();
    if (!mounted || ready || !_foreground || !_artworkShown) return;
    _artworkTime.start();
    final remaining = _minimumArtworkTime - _artworkTime.elapsed;
    _loadingTimer = Timer(remaining.isNegative ? Duration.zero : remaining, () {
      if (!mounted || !_foreground) return;
      _artworkTime.stop();
      setState(() => ready = true);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _loadingTimer?.cancel();
      _artworkTime.stop();
    } else {
      _scheduleHandoff();
    }
  }

  @override
  void dispose() {
    _loadingTimer?.cancel();
    _artworkTime.stop();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: GameStore.instance,
      builder: (context, _) {
        final needsUsername =
            ready &&
            GameStore.instance.loaded &&
            GameStore.instance.firstSessionMatchCompleted &&
            !GameStore.instance.hasChosenUsername;
        final needsTutorial =
            ready &&
            GameStore.instance.loaded &&
            !GameStore.instance.hasCompletedTutorial;
        final screen =
            !ready || !GameStore.instance.loaded
                ? LunoLoadingArtwork(
                  key: const ValueKey('loading'),
                  onShown: _onArtworkShown,
                )
                : needsTutorial
                ? const BattlePracticeCampaign(
                  key: ValueKey('tutorial-onboarding'),
                  onboarding: true,
                )
                : needsUsername
                ? const UsernameSetupScreen(key: ValueKey('username-setup'))
                : const HomeScreen(key: ValueKey('home'));
        return AnimatedSwitcher(
          duration: LunoMotion.adaptive(
            context,
            const Duration(milliseconds: 360),
          ),
          switchInCurve: LunoMotion.screenCurve,
          switchOutCurve: LunoMotion.screenExitCurve,
          child: KeyedSubtree(
            key: ValueKey((
              screen.key,
              GameStore.instance.accountBindingRevision,
            )),
            child: screen,
          ),
        );
      },
    );
  }
}

class UsernameSetupScreen extends StatefulWidget {
  const UsernameSetupScreen({super.key, this.store, this.online});
  final GameStore? store;
  final LunoOnlineService? online;

  @override
  State<UsernameSetupScreen> createState() => _UsernameSetupState();
}

class _UsernameSetupState extends State<UsernameSetupScreen> {
  GameStore get store => widget.store ?? GameStore.instance;
  LunoOnlineService get online => widget.online ?? LunoOnlineService.instance;
  late final TextEditingController _controller;
  final _ugcConsent = UgcConsent();
  String? _error;
  bool _saving = false;
  bool _restoringAccount = false;

  bool get _active => mounted && ModalRoute.of(context)?.isCurrent == true;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: store.pendingUsernameDraft);
  }

  @override
  void dispose() {
    _ugcConsent.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_active || _saving || _restoringAccount || store.hasChosenUsername) {
      return;
    }
    final value = normalizeUsernameValue(_controller.text);
    final l10n = LunoLocalizations.of(context);
    if (!isUsernameShapeValid(value)) {
      setState(() => _error = l10n.usernameInvalid);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    // A fresh anonymous bootstrap may bind the first account. Once identity
    // already exists, bootstrap must not silently move this edit to another one.
    final startingOwner =
        store.accountUid != null || online.user != null
            ? AccountOperationGuard(store, online)
            : null;
    try {
      // The first username is the identity used by friends, search and
      // matchmaking. Do not mark onboarding complete until the server has
      // accepted it; otherwise the app can look saved while the public
      // profile still contains the generated fallback name.
      await online.start().timeout(const Duration(seconds: 12));
      if (!_active) return;
      startingOwner?.check();
      if (!online.isOnline) {
        throw const LunoApiException('online-unavailable', 0);
      }
      final guard = AccountOperationGuard(store, online);
      if (!mounted) return;
      final result = await _ugcConsent.run(
        context: context,
        online: online,
        playerStore: store,
        operation: () => online.changeUsername(value),
      );
      if (result == null) return;
      if (!_active || !guard.isCurrent) return;
      final state = validateProfileUpdateResult(result, {'username': value});
      store.applyServerState(state);
      await store.chooseUsername(value);
    } catch (error) {
      if (!_active || startingOwner?.isCurrent == false) return;
      setState(() {
        _error = _usernameSyncError(error);
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _usernameSyncError(Object error) {
    final l10n = LunoLocalizations.of(context);
    if (error is LunoApiException &&
        (error.code == 'username-taken' ||
            error.code == 'profile-exists' ||
            error.code == 'username-not-allowed')) {
      return l10n.usernameTaken;
    }
    if (error is LunoApiException && error.code == 'username-change-busy') {
      return l10n.usernameBusy;
    }
    if (error is LunoApiException && error.code == 'online-unavailable') {
      return l10n.usernameOffline;
    }
    return l10n.usernameSaveFailed;
  }

  Future<void> _continueOffline() async {
    if (!_active || _saving || _restoringAccount || store.hasChosenUsername) {
      return;
    }
    final value = normalizeUsernameValue(_controller.text);
    final l10n = LunoLocalizations.of(context);
    if (!isUsernameShapeValid(value)) {
      setState(() => _error = l10n.usernameChooseFirst);
      return;
    }
    setState(() => _saving = true);
    try {
      await store.chooseUsername(value);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = LunoLocalizations.of(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        const LunoArt(LunoAssets.menuScene, fit: BoxFit.cover),
        const ModalBarrier(color: Color(0xC9000612), dismissible: false),
        Material(
          type: MaterialType.transparency,
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 18,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: LunoSurface(
                    padding: const EdgeInsets.all(22),
                    color: LunoColors.bgPanel,
                    child: DefaultTextStyle.merge(
                      style: const TextStyle(decoration: TextDecoration.none),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          LunoArt(
                            LunoAssets.lunoPortrait,
                            width: 88,
                            height: 96,
                            fit: BoxFit.contain,
                          ),
                          const SizedBox(height: 14),
                          Text(
                            l10n.usernameTitle,
                            textAlign: TextAlign.center,
                            style: LunoType.screenTitle.copyWith(fontSize: 22),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            l10n.usernameDescription,
                            textAlign: TextAlign.center,
                            style: LunoType.bodyMuted,
                          ),
                          const SizedBox(height: 22),
                          TextField(
                            controller: _controller,
                            enabled: !_saving && !_restoringAccount,
                            maxLength: 16,
                            scrollPadding: const EdgeInsets.only(bottom: 144),
                            style: const TextStyle(
                              color: LunoColors.ivory,
                              fontFamily: 'Nunito',
                              fontSize: 20,
                              decoration: TextDecoration.none,
                            ),
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _submit(),
                            decoration: InputDecoration(
                              counterText: '',
                              prefixIcon: const Icon(
                                Icons.alternate_email_rounded,
                                color: LunoColors.gold,
                                size: 24,
                              ),
                              filled: true,
                              fillColor: LunoColors.bgDeep,
                              hintText: l10n.usernameHint,
                              hintStyle: const TextStyle(
                                color: LunoColors.textDim,
                              ),
                              errorText: _error,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 20,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                  color: LunoColors.cyan,
                                  width: 2,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                  color: LunoColors.gold,
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 7),
                          Text(l10n.usernameRule, style: LunoType.bodyMuted),
                          const SizedBox(height: 24),
                          LunoButton(
                            onPressed:
                                _saving || _restoringAccount ? null : _submit,
                            loading: _saving,
                            icon: Icons.check_rounded,
                            label: _saving ? l10n.usernameSaving : l10n.confirm,
                          ),
                          const SizedBox(height: 10),
                          TextButton(
                            onPressed:
                                _saving || _restoringAccount
                                    ? null
                                    : _continueOffline,
                            child: Text(l10n.continueOffline),
                          ),
                          GoogleAccountRestoreButton(
                            online: online,
                            disabled: _saving,
                            onBusyChanged: (value) {
                              if (mounted) {
                                setState(() => _restoringAccount = value);
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class LunoLoadingArtwork extends StatelessWidget {
  final VoidCallback? onShown;
  const LunoLoadingArtwork({super.key, this.onShown});

  @override
  Widget build(BuildContext context) {
    final l = LunoLocalizations.of(context);
    return ColoredBox(
      color: LunoColors.bgDeep,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final dpr = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 3.0);
          // Loading art is shown full-screen, but decoding the source at the
          // device's maximum width stalls the very first raster frame on
          // slower phones. This keeps the same composition with a bounded,
          // visually clean decode size.
          final cacheWidth = (constraints.maxWidth * dpr).ceil().clamp(1, 640);
          final landscape = constraints.maxWidth > constraints.maxHeight;
          final artWidth =
              landscape ? constraints.maxHeight * 2 / 3 : constraints.maxWidth;
          return Stack(
            fit: StackFit.expand,
            children: [
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: artWidth,
                child: Image.asset(
                  LunoAssets.loadingScene,
                  fit: BoxFit.cover,
                  cacheWidth: cacheWidth,
                  filterQuality: FilterQuality.medium,
                  frameBuilder: (context, child, frame, synchronous) {
                    if (frame != null || synchronous) {
                      WidgetsBinding.instance.addPostFrameCallback(
                        (_) => onShown?.call(),
                      );
                    }
                    return child;
                  },
                  errorBuilder: (context, error, stack) {
                    WidgetsBinding.instance.addPostFrameCallback(
                      (_) => onShown?.call(),
                    );
                    return const Center(child: CircularProgressIndicator());
                  },
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: EdgeInsets.only(left: landscape ? artWidth : 0),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                        child: Text(
                          'LUNO CHESS',
                          textAlign: TextAlign.center,
                          style: LunoType.screenTitle.copyWith(
                            fontFamily: 'Nunito',
                            fontSize: 32,
                            color: const Color(0xFFFFD889),
                            letterSpacing: 0,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Container(
                        width: double.infinity,
                        color: LunoColors.bgDeep.withValues(alpha: .88),
                        padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              l.learning(
                                'Tahtan hazırlanıyor…',
                                'Preparing your board…',
                              ),
                              style: LunoType.body.copyWith(fontSize: 16),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            const LinearProgressIndicator(
                              minHeight: 4,
                              color: Color(0xFFFFD889),
                              backgroundColor: Color(0xFF1C5557),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              l.learning(
                                '24 kart · 9 arena · Her hamlede yeni bir plan',
                                '24 cards · 9 arenas · A new plan every move',
                              ),
                              style: LunoType.bodyMuted.copyWith(
                                color: const Color(0xFFBFE0D7),
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// Keep the original public test/embedding name while the shell owns the app root.
typedef LunoApp = LunoAppShell;
