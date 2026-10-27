import 'dart:async';

import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';

import '../i18n/luno_localizations.dart';
import '../i18n/luno_text.dart';
import '../navigation/luno_account_scope.dart';
import '../navigation/luno_route.dart';
import '../services/luno_online_service.dart';
import '../theme/luno_assets.dart';
import '../theme/luno_theme.dart';
import '../widgets/luno_surface.dart';
import 'battle_v1_screen.dart';

/// Native karşılığı: arkadaşla oynama, oda kodu oluşturma ve katılma akışı.
class FriendlyOnlineScreen extends StatefulWidget
    implements LunoAccountScopedPage {
  final LunoOnlineService? online;
  const FriendlyOnlineScreen({super.key, this.online});

  @override
  State<FriendlyOnlineScreen> createState() => _FriendlyOnlineScreenState();
}

class _FriendlyOnlineScreenState extends State<FriendlyOnlineScreen>
    with WidgetsBindingObserver {
  late final online = widget.online ?? LunoOnlineService.instance;
  late final (String?, int) _owner;
  bool get _ownsAccount => _owner == (online.user?.uid, online.accountRevision);
  void _checkOwner() {
    if (!_ownsAccount) throw const LunoApiException('session-changed', 409);
  }

  Future<T> _ownedRequest<T>(Future<T> Function() request) async {
    _checkOwner();
    final result = await request();
    _checkOwner();
    return result;
  }

  final codeController = TextEditingController();
  Timer? _pollTimer;
  String? roomCode;
  String status = 'Arkadaşınla aynı tahtaya çık.';
  String? error;
  bool busy = false;
  bool _preparing = false;
  bool _cancelling = false;
  bool _polling = false;
  int _flowGeneration = 0;
  int _pollToken = 0;
  int durationMinutes = 5;

  @override
  void initState() {
    super.initState();
    _owner = (online.user?.uid, online.accountRevision);
    WidgetsBinding.instance.addObserver(this);
    online.addListener(_onOnlineChanged);
  }

  @override
  void dispose() {
    online.removeListener(_onOnlineChanged);
    WidgetsBinding.instance.removeObserver(this);
    if (roomCode != null && !_cancelling) {
      unawaited(_cancelRoomAfterExit(roomCode!));
    }
    _flowGeneration++;
    _pollToken++;
    _pollTimer?.cancel();
    codeController.dispose();
    super.dispose();
  }

  void _onOnlineChanged() {
    if (!_ownsAccount) {
      _flowGeneration++;
      _pollToken++;
      _pollTimer?.cancel();
      return;
    }
    if (!mounted || roomCode == null || !online.isOnline || _cancelling) return;
    _startPolling(_flowGeneration);
    unawaited(_pollRoom(_flowGeneration));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (roomCode != null && !_cancelling) {
        _startPolling(_flowGeneration);
        unawaited(_pollRoom(_flowGeneration));
      }
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _pollTimer?.cancel();
      _pollToken++;
      _polling = false;
    }
  }

  Future<void> _cancelRoomAfterExit(String code) async {
    if (!_ownsAccount) return;
    try {
      await _ownedRequest(() => online.cancelBattleV1Room(code));
    } catch (_) {
      // The server remains authoritative if the route is closed mid-request.
    }
  }

  Future<bool> _ensureOnline() async {
    _checkOwner();
    if (online.isOnline) return true;
    try {
      await online.start().timeout(const Duration(seconds: 12));
    } on TimeoutException {
      // Keep the room screen responsive when the device has no network.
    }
    _checkOwner();
    if (!mounted || !online.isOnline) {
      if (mounted) {
        setState(() {
          status = 'Bağlantı gerekli';
          error = 'Arkadaş maçı için internet bağlantını kontrol et.';
        });
      }
      return false;
    }
    return true;
  }

  Future<void> _runAction(Future<void> Function() action) async {
    if (!_ownsAccount ||
        _preparing ||
        busy ||
        roomCode != null ||
        _cancelling) {
      return;
    }
    setState(() => _preparing = true);
    FocusScope.of(context).unfocus();
    try {
      await action();
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Sunucuya bağlanılamadı. Tekrar deneyebilirsin.',
        );
      }
    } finally {
      if (mounted) setState(() => _preparing = false);
    }
  }

  Future<void> _createRoom() => _runAction(_createRoomRequest);

  Future<void> _createRoomRequest() async {
    if (busy || roomCode != null) return;
    if (!await _ensureOnline()) return;
    if (!mounted) return;
    const selectedDuration = 5;
    durationMinutes = selectedDuration;
    final generation = ++_flowGeneration;
    setState(() {
      busy = true;
      error = null;
      status = 'Oda hazırlanıyor';
    });
    try {
      final result = await _ownedRequest(online.createBattleV1Room);
      final code = result['roomCode']?.toString() ?? '';
      if (!mounted || generation != _flowGeneration) {
        if (code.isNotEmpty) unawaited(_cancelRoomAfterExit(code));
        return;
      }
      if (code.isEmpty) {
        setState(() {
          busy = false;
          status = 'Oda oluşturulamadı';
          error = 'Sunucudan geçerli bir oda kodu alınamadı.';
        });
        return;
      }
      setState(() {
        roomCode = code;
        busy = false;
        status = 'Arkadaşın oda kodunu girince maç başlayacak';
      });
      _startPolling(generation);
    } catch (_) {
      if (!mounted || generation != _flowGeneration) return;
      setState(() {
        busy = false;
        status = 'Oda oluşturulamadı';
        error = 'Sunucuya bağlanılamadı. Tekrar deneyebilirsin.';
      });
    }
  }

  void _startPolling(int generation) {
    if (!_ownsAccount) return;
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _pollRoom(generation),
    );
  }

  Future<void> _pollRoom(int generation) async {
    if (!mounted ||
        !_ownsAccount ||
        roomCode == null ||
        busy ||
        _cancelling ||
        generation != _flowGeneration ||
        _polling) {
      return;
    }
    _polling = true;
    final pollToken = ++_pollToken;
    try {
      final result = await _ownedRequest(() => online.getBattleV1(''));
      if (!mounted ||
          generation != _flowGeneration ||
          pollToken != _pollToken) {
        return;
      }
      final view = _viewFrom(result);
      if (view != null) {
        _openMatch(
          result['matchId']?.toString() ?? view['matchId']?.toString() ?? '',
          view,
        );
      }
    } catch (_) {
      if (mounted && generation == _flowGeneration && pollToken == _pollToken) {
        setState(() => error = 'Oda bağlantısı yenileniyor...');
      }
    } finally {
      if (pollToken == _pollToken) _polling = false;
    }
  }

  Future<void> _joinRoom() => _runAction(_joinRoomRequest);

  Future<void> _joinRoomRequest() async {
    if (busy || roomCode != null || _cancelling) return;
    final code = codeController.text.trim().toUpperCase();
    if (!RegExp(r'^[A-Z0-9]{6}$').hasMatch(code)) {
      _toast('6 karakterli oda kodunu gir.');
      return;
    }
    if (!await _ensureOnline() || !mounted) return;
    final generation = ++_flowGeneration;
    setState(() {
      busy = true;
      error = null;
      status = 'Odaya bağlanılıyor';
    });
    try {
      final result = await _ownedRequest(() => online.joinBattleV1Room(code));
      final view = _viewFrom(result);
      if (!mounted || generation != _flowGeneration) return;
      if (view == null) {
        setState(() {
          busy = false;
          status = 'Oda bulunamadı';
          error = 'Kod geçersiz, dolu veya süresi dolmuş olabilir.';
        });
        return;
      }
      _openMatch(
        result['matchId']?.toString() ?? view['matchId']?.toString() ?? '',
        view,
      );
    } catch (_) {
      if (!mounted || generation != _flowGeneration) return;
      setState(() {
        busy = false;
        status = 'Odaya bağlanılamadı';
        error = 'Kod geçersiz, dolu veya süresi dolmuş olabilir.';
      });
    }
  }

  Future<void> _cancelRoom() async {
    if (!_ownsAccount || _cancelling) return;
    final code = roomCode;
    if (code == null) return;
    final generation = ++_flowGeneration;
    _pollToken++;
    _pollTimer?.cancel();
    _polling = false;
    setState(() {
      _cancelling = true;
      busy = true;
      error = null;
      status = 'Oda kapatılıyor';
    });
    var cancelled = false;
    try {
      await _ownedRequest(
        () => online.cancelBattleV1Room(code),
      ).timeout(const Duration(seconds: 8));
      cancelled = true;
      if (!mounted || generation != _flowGeneration) return;
      setState(() {
        roomCode = null;
        busy = false;
        status = 'Oda kapatıldı';
      });
    } on TimeoutException {
      if (mounted && generation == _flowGeneration) {
        setState(() {
          busy = false;
          status = 'Oda açık';
          error = 'Oda kapanışı doğrulanamadı. Durum yeniden denetleniyor.';
        });
      }
    } catch (_) {
      if (mounted && generation == _flowGeneration) {
        setState(() {
          busy = false;
          status = 'Oda açık';
          error = 'Oda kapatılamadı. Bağlantı düzelince tekrar dene.';
        });
      }
    } finally {
      if (mounted && generation == _flowGeneration) {
        setState(() => _cancelling = false);
        if (!cancelled && roomCode != null) _startPolling(generation);
      }
    }
  }

  Map<String, dynamic>? _viewFrom(Map<String, dynamic> result) {
    final raw = result['view'];
    return raw is Map ? Map<String, dynamic>.from(raw) : null;
  }

  void _openMatch(String matchId, Map<String, dynamic> view) {
    if (!mounted || !_ownsAccount) return;
    if (matchId.isEmpty) {
      setState(() {
        busy = false;
        error = 'Sunucudan geçerli bir maç alınamadı. Tekrar deneyebilirsin.';
      });
      return;
    }
    _flowGeneration++;
    _pollToken++;
    _pollTimer?.cancel();
    // The room is consumed by the server when the match is created. Clearing
    // it before replacing the route prevents dispose() from racing a second
    // cancellation request against the newly opened match.
    roomCode = null;
    Navigator.of(context).pushReplacement(
      lunoRoute(BattleV1Screen(matchId: matchId, initialView: view)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final copy = LunoLocalizations.of(context);
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(title: const Text('ARKADAŞLA OYNA')),
      body: LunoBackdrop(
        art: LunoAssets.phase2GameplayAtmosphere,
        overlay: const Color(0xD91C3835),
        focalPoint: const Alignment(0, -.1),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              LunoSurface(
                borderRadius: BorderRadius.circular(8),
                color: LunoColors.bgPanel,
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [
                    const LunoArt(
                      'assets/native_art/friends-welcome-v216.webp',
                      width: 160,
                      height: 160,
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'DOSTLUK MAÇI',
                      style: TextStyle(
                        color: LunoColors.gold,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      status,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: LunoColors.textDim),
                    ),
                    if (roomCode != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: LunoColors.bgDeep,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: LunoColors.goldDeep),
                        ),
                        child: Row(
                          children: [
                            const SizedBox(width: 12),
                            Expanded(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  roomCode!,
                                  style: const TextStyle(
                                    color: LunoColors.gold,
                                    fontSize: 28,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0,
                                  ),
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: copy.translate('Oda kodunu kopyala'),
                              onPressed:
                                  busy || _cancelling ? null : _copyRoomCode,
                              icon: const Icon(
                                Icons.copy_rounded,
                                color: LunoColors.gold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      LunoButton(
                        kind: LunoButtonKind.secondary,
                        loading: _cancelling,
                        onPressed: busy ? null : _cancelRoom,
                        icon: Icons.close_rounded,
                        label: 'Odayı kapat',
                      ),
                    ] else ...[
                      const SizedBox(height: 18),
                      LunoButton(
                        onPressed: busy || _preparing ? null : _createRoom,
                        loading: busy || _preparing,
                        icon: Icons.add_link_rounded,
                        label: copy.friendlyRoomCreate,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        copy.friendlyRoomDuration(durationMinutes),
                        textAlign: TextAlign.center,
                        style: LunoType.bodyMuted,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
              LunoSurface(
                borderRadius: BorderRadius.circular(8),
                color: LunoColors.bgPanel,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ODA KODUYLA KATIL',
                      style: TextStyle(
                        color: LunoColors.gold,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: codeController,
                            enabled: !busy && !_preparing && roomCode == null,
                            autocorrect: false,
                            enableSuggestions: false,
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[a-zA-Z0-9]'),
                              ),
                            ],
                            textInputAction: TextInputAction.go,
                            onSubmitted: (_) => _joinRoom(),
                            maxLength: 6,
                            textCapitalization: TextCapitalization.characters,
                            scrollPadding: const EdgeInsets.only(bottom: 120),
                            decoration: InputDecoration(
                              hintText: copy.translate('Örn. LK7X9M'),
                              counterText: '',
                              filled: true,
                              fillColor: LunoColors.bgPanel2,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          style: IconButton.styleFrom(
                            foregroundColor: LunoColors.bgRaised,
                            backgroundColor: LunoColors.gold,
                          ),
                          onPressed:
                              busy || _preparing || roomCode != null
                                  ? null
                                  : _joinRoom,
                          tooltip: copy.translate('Katıl'),
                          icon: const Icon(Icons.login_rounded),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(
                  error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: LunoColors.danger),
                ),
              ],
              const SizedBox(height: 14),
              const LunoSurface(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.shield_rounded, color: LunoColors.gold),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Dostluk maçında da hamleler sunucu tarafından doğrulanır. Oda kodları kısa süreli ve tek kullanımlıktır.',
                        style: TextStyle(
                          color: LunoColors.textDim,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _toast(String message) {
    if (!mounted) return;
    showLunoNotice(context, message);
  }

  Future<void> _copyRoomCode() async {
    final code = roomCode;
    if (!mounted || code == null || busy || _cancelling) return;
    try {
      await Clipboard.setData(ClipboardData(text: code));
      if (mounted && roomCode == code) _toast('Oda kodu kopyalandı.');
    } catch (_) {
      if (mounted && roomCode == code) {
        _toast('Kod kopyalanamadı. Tekrar dene.');
      }
    }
  }
}
