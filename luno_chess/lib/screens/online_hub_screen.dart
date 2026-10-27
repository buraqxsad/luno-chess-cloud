import 'dart:async';

import 'package:flutter/material.dart' hide Text;

import '../i18n/luno_text.dart';
import '../navigation/luno_account_scope.dart';
import '../navigation/luno_route.dart';
import '../services/luno_online_service.dart';
import '../theme/luno_assets.dart';
import '../theme/luno_theme.dart';
import '../widgets/luno_surface.dart';
import 'battle_v1_screen.dart';

class OnlineHubScreen extends StatefulWidget implements LunoAccountScopedPage {
  final LunoOnlineService? online;
  @visibleForTesting
  final Future<Map<String, dynamic>> Function(String, Map<String, dynamic>)?
  requestOverride;
  @visibleForTesting
  final bool? onlineOverride;

  const OnlineHubScreen({
    super.key,
    this.online,
    this.requestOverride,
    this.onlineOverride,
  });

  @override
  State<OnlineHubScreen> createState() => _OnlineHubScreenState();
}

class _OnlineHubScreenState extends State<OnlineHubScreen>
    with WidgetsBindingObserver {
  late final online = widget.online ?? LunoOnlineService.instance;
  late final (String?, int) _owner;
  bool get _ownsAccount => _owner == (online.user?.uid, online.accountRevision);
  void _checkOwner() {
    if (!_ownsAccount) throw const LunoApiException('session-changed', 409);
  }

  Timer? _pollTimer;
  bool waiting = false;
  bool _preparing = false;
  bool _cancelling = false;
  bool _polling = false;
  bool _accountBlocked = false;
  int _flowGeneration = 0;
  int _pollToken = 0;
  String status = 'Hazır';
  String? error;
  DateTime? joinedAt;

  bool get _isOnline => widget.onlineOverride ?? online.isOnline;
  Future<Map<String, dynamic>> _request(
    String path,
    Map<String, dynamic> body,
  ) async {
    _checkOwner();
    final result =
        await (widget.requestOverride?.call(path, body) ??
            switch (path) {
              '/enqueueRanked' => online.enqueueBattleV1(),
              '/getRankedMatch' => online.getBattleV1(
                body['matchId']?.toString() ?? '',
              ),
              '/cancelRankedQueue' => online.cancelBattleV1Queue(),
              _ => online.api(path, body),
            });
    _checkOwner();
    return result;
  }

  bool _handleAccountFailure(Object cause) {
    if (cause is! LunoApiException || cause.accountAccessMessage == null) {
      return false;
    }
    if (!mounted) return true;
    _pollTimer?.cancel();
    _flowGeneration++;
    _pollToken++;
    setState(() {
      _accountBlocked = true;
      waiting = false;
      _preparing = false;
      _cancelling = false;
      _polling = false;
      joinedAt = null;
      status = 'Online işlemler durduruldu';
      error = cause.accountAccessMessage;
    });
    return true;
  }

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
    if (waiting && !_cancelling) unawaited(_cancelQueueAfterExit());
    _flowGeneration++;
    _pollToken++;
    _pollTimer?.cancel();
    super.dispose();
  }

  void _onOnlineChanged() {
    if (!_ownsAccount) {
      _flowGeneration++;
      _pollToken++;
      _pollTimer?.cancel();
      return;
    }
    if (!mounted || !waiting || !_isOnline || _cancelling) return;
    _startPolling(_flowGeneration);
    unawaited(_poll(_flowGeneration));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (waiting && !_cancelling) {
        _startPolling(_flowGeneration);
        unawaited(_poll(_flowGeneration));
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

  Future<void> _cancelQueueAfterExit() async {
    if (_accountBlocked || !_ownsAccount) return;
    try {
      await _request('/cancelRankedQueue', const {});
    } catch (_) {
      // The server remains authoritative if the route is closed mid-request.
    }
  }

  Future<bool> _ensureOnline() async {
    _checkOwner();
    if (_accountBlocked) return false;
    if (_isOnline) return true;
    try {
      await online.start().timeout(const Duration(seconds: 12));
    } on TimeoutException {
      // The service exposes the same offline state to the shell; this screen
      // only needs to stop the matchmaking action from appearing stuck.
    }
    _checkOwner();
    if (online.accountFailure != null) throw online.accountFailure!;
    if (!mounted || !_isOnline) {
      if (mounted) {
        setState(() {
          waiting = false;
          status = 'Bağlantı gerekli';
          error = 'Eşleşme için internet bağlantını kontrol et.';
        });
      }
      return false;
    }
    return true;
  }

  Future<void> _queue() async {
    if (!_ownsAccount ||
        _accountBlocked ||
        waiting ||
        _cancelling ||
        _preparing) {
      return;
    }
    setState(() => _preparing = true);
    try {
      if (!await _ensureOnline() || !mounted) return;
      await _enqueue();
    } catch (e) {
      if (_handleAccountFailure(e)) return;
      if (mounted) setState(() => error = _message(e));
    } finally {
      if (mounted) setState(() => _preparing = false);
    }
  }

  Future<void> _reconnect() async {
    if (!_ownsAccount ||
        _accountBlocked ||
        _preparing ||
        waiting ||
        _cancelling) {
      return;
    }
    setState(() => _preparing = true);
    try {
      await online.retry().timeout(const Duration(seconds: 12));
      _checkOwner();
      if (online.accountFailure != null) throw online.accountFailure!;
    } catch (e) {
      if (_handleAccountFailure(e)) return;
      if (mounted) setState(() => error = _message(e));
    } finally {
      if (mounted) setState(() => _preparing = false);
    }
  }

  Future<void> _enqueue() async {
    final generation = ++_flowGeneration;
    setState(() {
      waiting = true;
      error = null;
      status = 'Güvenli eşleşme başlatılıyor';
      joinedAt = DateTime.now();
    });
    try {
      final result = await _request('/enqueueRanked', const {});
      if (_accountBlocked) return;
      final view = _viewFrom(result);
      if (!mounted) {
        if (view == null && result['status']?.toString() == 'queued') {
          unawaited(_cancelQueueAfterExit());
        }
        return;
      }
      if (generation != _flowGeneration) {
        if (view != null) {
          _openMatch(
            result['matchId']?.toString() ?? view['matchId']?.toString() ?? '',
            view,
          );
        } else if (result['status']?.toString() == 'queued') {
          try {
            await _request('/cancelRankedQueue', const {});
          } catch (_) {
            // A concurrent match is handled by the normal polling path.
          }
        }
        return;
      }
      if (view != null) {
        _openMatch(
          result['matchId']?.toString() ?? view['matchId']?.toString() ?? '',
          view,
        );
        return;
      }
      setState(() => status = 'Rakip aranıyor');
      _startPolling(generation);
    } catch (e) {
      if (!mounted || generation != _flowGeneration) return;
      if (_handleAccountFailure(e)) return;
      setState(() {
        waiting = false;
        status = 'Bağlantı kurulamadı';
        error = _message(e);
      });
    }
  }

  void _startPolling(int generation) {
    if (_accountBlocked || !_ownsAccount) return;
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _poll(generation),
    );
  }

  Future<void> _poll(int generation) async {
    if (!_ownsAccount ||
        !waiting ||
        !mounted ||
        generation != _flowGeneration ||
        _polling) {
      return;
    }
    _polling = true;
    final pollToken = ++_pollToken;
    try {
      final result = await _request('/getRankedMatch', const {'matchId': ''});
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
      } else if (result['status']?.toString() == 'idle') {
        _pollTimer?.cancel();
        setState(() {
          waiting = false;
          joinedAt = null;
          status = 'Eşleşme iptal edildi';
          error = null;
        });
      }
    } catch (e) {
      if (!mounted ||
          generation != _flowGeneration ||
          pollToken != _pollToken) {
        return;
      }
      if (_handleAccountFailure(e)) return;
      setState(() {
        status = 'Bağlantı yenileniyor';
        error = _message(e);
      });
    } finally {
      if (pollToken == _pollToken) _polling = false;
    }
  }

  Future<void> _cancel() async {
    if (!_ownsAccount || !waiting || _cancelling) return;
    final generation = ++_flowGeneration;
    _pollToken++;
    _pollTimer?.cancel();
    _polling = false;
    _cancelling = true;
    if (mounted) {
      setState(() {
        status = 'Eşleşme iptal ediliyor';
        error = null;
      });
    }
    var cancelled = false;
    try {
      await _request(
        '/cancelRankedQueue',
        const {},
      ).timeout(const Duration(seconds: 8));
      cancelled = true;
      if (!mounted || generation != _flowGeneration) return;
      setState(() {
        waiting = false;
        joinedAt = null;
        status = 'Eşleşme iptal edildi';
      });
    } on TimeoutException {
      if (mounted && generation == _flowGeneration) {
        setState(() {
          status = 'Eşleşme araması sürüyor';
          error =
              'İptal doğrulanamadı. Kuyruk korunuyor; durum yeniden denetleniyor.';
        });
      }
    } catch (e) {
      if (mounted && generation == _flowGeneration) {
        if (_handleAccountFailure(e)) return;
        setState(() {
          status = 'Eşleşme araması sürüyor';
          error = _message(e);
        });
      }
    } finally {
      if (mounted && generation == _flowGeneration) {
        setState(() => _cancelling = false);
        if (!cancelled && waiting) _startPolling(generation);
      }
    }
  }

  void _openMatch(String matchId, Map<String, dynamic> view) {
    if (!mounted || !_ownsAccount || _accountBlocked || matchId.isEmpty) return;
    _flowGeneration++;
    _pollToken++;
    _pollTimer?.cancel();
    setState(() {
      waiting = false;
      status = 'Rakip bulundu';
    });
    Navigator.of(context).pushReplacement(
      lunoRoute(BattleV1Screen(matchId: matchId, initialView: view)),
    );
  }

  Map<String, dynamic>? _viewFrom(Map<String, dynamic> result) {
    final value = result['view'];
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  String _message(Object value) {
    if (value is LunoApiException && value.accountAccessMessage != null) {
      return value.accountAccessMessage!;
    }
    if (value is LunoApiException && value.code == 'profile-not-found') {
      return 'Oyuncu profili hazır değil. Ana menüden bağlantıyı yenile.';
    }
    return 'Sunucuya bağlanılamadı. Tekrar deneyebilirsin.';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: online,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(title: const Text('SIRALI EŞLEŞME')),
          body: LunoBackdrop(
            art: LunoAssets.phase2GameplayAtmosphere,
            overlay: const Color(0xD91C3835),
            focalPoint: const Alignment(0, -.12),
            child: SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  LunoSurface(
                    borderRadius: BorderRadius.circular(8),
                    padding: const EdgeInsets.all(20),
                    color: LunoColors.bgPanel,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const LunoArt(
                              LunoAssets.modeRanked,
                              width: 64,
                              height: 64,
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'ARENA EŞLEŞMESİ',
                                    style: TextStyle(
                                      color: LunoColors.gold,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _accountBlocked
                                        ? 'Online işlemler durduruldu'
                                        : _isOnline
                                        ? 'Sunucu bağlantısı güvenli'
                                        : 'Çevrimdışı görünüyorsun',
                                    style: const TextStyle(
                                      color: LunoColors.textDim,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              !_accountBlocked && _isOnline
                                  ? Icons.wifi_rounded
                                  : Icons.wifi_off_rounded,
                              color:
                                  !_accountBlocked && _isOnline
                                      ? LunoColors.success
                                      : LunoColors.danger,
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Text(
                          !_isOnline && status == 'Hazır'
                              ? 'Bağlantı gerekli'
                              : status,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _accountBlocked
                              ? 'Bu ekrandan güvenle çıkabilirsin.'
                              : waiting
                              ? 'Rakibin bulunduğunda maç başlayacak.'
                              : !_isOnline
                              ? 'İnternet bağlantını kontrol et, ardından yeniden bağlan.'
                              : 'Kupanı koru, gerçek bir rakiple temiz bir maç yap.',
                          style: const TextStyle(
                            color: LunoColors.textDim,
                            height: 1.35,
                          ),
                        ),
                        if (joinedAt != null && waiting) ...[
                          const SizedBox(height: 16),
                          LinearProgressIndicator(
                            value:
                                MediaQuery.disableAnimationsOf(context)
                                    ? .5
                                    : null,
                            minHeight: 5,
                            color: LunoColors.gold,
                            backgroundColor: LunoColors.bgDeep,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (error != null)
                    LunoSurface(
                      borderRadius: BorderRadius.circular(8),
                      color: const Color(0xED4A3032),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.error_outline_rounded,
                            color: LunoColors.danger,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              error!,
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (error != null) const SizedBox(height: 14),
                  if (_accountBlocked)
                    LunoButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: Icons.arrow_back_rounded,
                      label: 'GERİ DÖN',
                    )
                  else if (!waiting)
                    LunoButton(
                      loading: _preparing,
                      onPressed:
                          _preparing
                              ? null
                              : _isOnline
                              ? _queue
                              : _reconnect,
                      icon:
                          _isOnline
                              ? Icons.play_arrow_rounded
                              : Icons.sync_rounded,
                      label:
                          _isOnline ? 'EŞLEŞMEYİ BAŞLAT' : 'BAĞLANTIYI YENİLE',
                    )
                  else
                    LunoButton(
                      kind: LunoButtonKind.danger,
                      loading: _cancelling,
                      onPressed: _cancelling ? null : _cancel,
                      icon: Icons.close_rounded,
                      label: 'ARAMAYI İPTAL ET',
                    ),
                  const SizedBox(height: 14),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'MAÇ GÜVENLİĞİ',
                          style: TextStyle(
                            color: LunoColors.gold,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0,
                          ),
                        ),
                        SizedBox(height: 10),
                        Text(
                          'Her hamle sunucuda doğrulanır. Maç boyunca internet bağlantını açık tut.',
                          style: TextStyle(
                            color: LunoColors.textDim,
                            height: 1.4,
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
      },
    );
  }
}
