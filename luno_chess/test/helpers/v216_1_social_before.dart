// Frozen pre-social-edit owned classes. Do not mirror production fixes.
// Source: qa/v216_1/social-before/source/native_hubs_screen.dart.txt
// Raw source SHA-256: a860b4309e037e1281ac199e13ac1b72bcd5b42ae704c12c97064594a652fcad
// Only class identifiers and import paths are adapted; shared dependencies remain current.
// ignore_for_file: unused_import
import 'package:flutter/material.dart' hide Text;
import 'package:luno_chess/theme/luno_visual_assets.dart';
import 'package:luno_chess/widgets/luno_polish.dart';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:luno_chess/data/card_pool.dart';
import 'package:luno_chess/data/rank_catalog.dart';
import 'package:luno_chess/data/season_clock.dart';
import 'package:luno_chess/data/username.dart';
import 'package:luno_chess/i18n/luno_localizations.dart';
import 'package:luno_chess/i18n/luno_text.dart';
import 'package:luno_chess/models/app_settings.dart';
import 'package:luno_chess/models/game_store.dart';
import 'package:luno_chess/navigation/luno_route.dart';
import 'package:luno_chess/navigation/luno_account_scope.dart';
import 'package:luno_chess/navigation/luno_account_modal.dart';
import 'package:luno_chess/services/luno_online_service.dart';
import 'package:luno_chess/services/initial_stream_timeout.dart';
import 'package:luno_chess/services/screen_request_timeouts.dart';
import 'package:luno_chess/services/account_operation_guard.dart';
import 'package:luno_chess/services/collection_selection_result.dart';
import 'package:luno_chess/services/leaderboard_result.dart';
import 'package:luno_chess/services/player_search_result.dart';
import 'package:luno_chess/screens/public_player_profile_screen.dart';
import 'package:luno_chess/services/direct_message_read_key.dart';
import 'package:luno_chess/services/reward_claim_result.dart';
import 'package:luno_chess/services/profile_update_result.dart';
import 'package:luno_chess/services/ugc_consent.dart';
import 'package:luno_chess/services/ugc_text_safety.dart';
import 'package:luno_chess/services/luno_feedback.dart';
import 'package:luno_chess/theme/luno_assets.dart';
import 'package:luno_chess/theme/luno_theme.dart';
import 'package:luno_chess/widgets/currency_bar.dart';
import 'package:luno_chess/widgets/luno_surface.dart';
import 'package:luno_chess/widgets/card_info.dart';
import 'package:luno_chess/widgets/resource_amount.dart';
import 'package:luno_chess/widgets/social_safety_actions.dart';
import 'package:luno_chess/screens/blocked_players_screen.dart';
import 'package:luno_chess/services/product_privacy_settings.dart';
import 'package:luno_chess/screens/legacy_parity_screens.dart';
import 'package:luno_chess/screens/collection_screens.dart';
import 'package:luno_chess/screens/battle_deck_screen.dart';
import 'package:luno_chess/screens/battle_v1_screen.dart';
import 'package:luno_chess/screens/native_hubs_screen.dart';

class V216BeforeFriendsScreen extends StatefulWidget implements LunoAccountScopedPage {
  static const socialLoadTimeout = Duration(seconds: 12);
  const V216BeforeFriendsScreen({super.key, this.online});

  final LunoOnlineService? online;

  @override
  State<V216BeforeFriendsScreen> createState() => _V216BeforeFriendsScreenState();
}


class _V216BeforeFriendsScreenState extends State<V216BeforeFriendsScreen> {
  final controller = TextEditingController();
  final _requestTimeouts = ScreenRequestTimeouts();
  int tab = 0;
  bool loading = false;
  bool socialLoading = true;
  String? socialError;
  int _socialLoadSerial = 0;
  int _searchSerial = 0;
  String? _activeSearchQuery;
  bool searchActive = false;
  String? searchError;
  List<Map<String, dynamic>> results = const [];
  List<Map<String, dynamic>> friendRows = const [];
  List<Map<String, dynamic>> requestRows = const [];
  final Set<String> friendBusy = <String>{};
  final Set<String> inviteBusy = <String>{};
  StreamSubscription<List<Map<String, dynamic>>>? _friendRequestSubscription;
  bool _friendRequestSnapshotReady = false;
  int _friendRequestVersion = 0;
  Stream<List<Map<String, dynamic>>>? _matchInviteStream;
  late final String? _entryUid;
  late final int _entryRevision;
  LunoOnlineService get _online => widget.online ?? LunoOnlineService.instance;
  bool get _ownsSession =>
      mounted &&
      _online.user?.uid == _entryUid &&
      _online.accountRevision == _entryRevision &&
      _online.accountFailure == null;
  bool get _canAct =>
      _ownsSession && ModalRoute.of(context)?.isCurrent != false;

  @override
  void initState() {
    super.initState();
    _entryUid = _online.user?.uid;
    _entryRevision = _online.accountRevision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_loadSocial());
    });
  }

  @override
  void dispose() {
    _requestTimeouts.dispose();
    _friendRequestSubscription?.cancel();
    controller.dispose();
    super.dispose();
  }

  Future<void> _loadSocial() async {
    if (!_canAct) return;
    final loadSerial = ++_socialLoadSerial;
    if (mounted) {
      setState(() {
        socialLoading = true;
        socialError = null;
      });
    }
    try {
      final online = _online;
      await _requestTimeouts.run(
        online.start(),
        V216BeforeFriendsScreen.socialLoadTimeout,
      );
      if (!_ownsSession || loadSerial != _socialLoadSerial) return;
      final requestVersion = _friendRequestVersion;
      _matchInviteStream ??= online.matchInvitesStream();
      _friendRequestSubscription ??= online.friendRequestsStream().listen(
        _onFriendRequestsChanged,
        onError: (Object error, StackTrace stack) {
          if (_ownsSession) _toast('Arkadaşlık istekleri şu an yenilenemedi.');
        },
      );
      final values = await _requestTimeouts.run(
        Future.wait([online.friends(), online.friendRequests()]),
        V216BeforeFriendsScreen.socialLoadTimeout,
      );
      if (!_ownsSession || loadSerial != _socialLoadSerial) return;
      setState(() {
        friendRows = values[0];
        if (requestVersion == _friendRequestVersion) requestRows = values[1];
        _friendRequestSnapshotReady = true;
      });
    } catch (_) {
      if (_ownsSession && loadSerial == _socialLoadSerial) {
        setState(() {
          socialError =
              LunoLocalizations.of(context).isEnglish
                  ? 'Social information could not be loaded.'
                  : 'Sosyal bilgiler yüklenemedi.';
          friendRows = const [];
          if (!_friendRequestSnapshotReady) requestRows = const [];
        });
        _toast('Sosyal bilgiler şu an yenilenemedi.');
      }
    } finally {
      if (_ownsSession && loadSerial == _socialLoadSerial) {
        setState(() => socialLoading = false);
      }
    }
  }

  void _onFriendRequestsChanged(List<Map<String, dynamic>> requests) {
    if (!_ownsSession) return;
    final known =
        requestRows
            .map((request) => request['fromUid']?.toString() ?? '')
            .where((uid) => uid.isNotEmpty)
            .toSet();
    final hasNewRequest =
        _friendRequestSnapshotReady &&
        requests.any(
          (request) => !known.contains(request['fromUid']?.toString() ?? ''),
        );
    setState(() {
      ++_friendRequestVersion;
      _friendRequestSnapshotReady = true;
      requestRows = requests;
    });
    if (hasNewRequest && tab != 1) {
      _toast('Yeni bir arkadaşlık isteğin var.');
    }
  }

  Future<void> _search() async {
    if (!_canAct) return;
    final query = controller.text.trim().toLowerCase();
    if (query.length < 3) {
      _toast('En az 3 karakter yaz.');
      return;
    }
    if (!RegExp(r'^(?:[a-z0-9_]{3,16}|luno-[a-f0-9]{3,8})$').hasMatch(query)) {
      _toast('Geçerli bir kullanıcı adı veya oyuncu kodu yaz.');
      return;
    }
    if (loading && _activeSearchQuery == query) return;
    final searchSerial = ++_searchSerial;
    _activeSearchQuery = query;
    setState(() {
      loading = true;
      searchActive = true;
      searchError = null;
      results = const [];
      tab = 0;
    });
    try {
      final value = await _online.api('/searchPlayers', {
        'query': query,
        'protocolVersion': 'LUNO_BATTLE_V1',
      });
      final nextResults = parsePlayerSearchResult(value, ownUid: _entryUid);
      if (_ownsSession && searchSerial == _searchSerial) {
        setState(() => results = nextResults);
      }
    } catch (_) {
      if (_ownsSession && searchSerial == _searchSerial) {
        setState(() => searchError = 'Oyuncu araması şu an kullanılamıyor.');
        _toast('Oyuncu araması şu an kullanılamıyor.');
      }
    }
    if (_ownsSession && searchSerial == _searchSerial) {
      setState(() => loading = false);
    }
  }

  void _changeTab(int value) {
    if (!_canAct) return;
    setState(() {
      _searchSerial++;
      loading = false;
      searchActive = false;
      searchError = null;
      tab = value;
      results = const [];
    });
    if (value < 2) _loadSocial();
  }

  Future<void> _addFriend(Map<String, dynamic> player) async {
    if (!_canAct || loading || !searchActive) return;
    final targetUid = player['uid']?.toString() ?? '';
    if (targetUid.isEmpty ||
        friendBusy.contains(targetUid) ||
        !results.any((row) => row['uid']?.toString() == targetUid)) {
      return;
    }
    setState(() => friendBusy.add(targetUid));
    try {
      final status = await _online.sendFriendRequest(targetUid);
      if (!_ownsSession) return;
      _toast(
        status == 'accepted'
            ? 'Arkadaşlık isteği kabul edildi.'
            : status == 'friends'
            ? 'Bu oyuncu zaten arkadaşın.'
            : status == 'pending'
            ? 'Arkadaşlık isteği zaten bekliyor.'
            : 'Arkadaşlık isteği gönderildi.',
      );
      if (_ownsSession) {
        setState(() {
          final index = results.indexWhere(
            (row) => row['uid']?.toString() == targetUid,
          );
          if (index >= 0) {
            results[index] = Map<String, dynamic>.from(results[index])
              ..['relationship'] = switch (status) {
                'sent' => 'outgoing',
                'accepted' => 'friends',
                'pending' => 'outgoing',
                _ => status,
              };
          }
        });
      }
      await _loadSocial();
    } catch (error) {
      _toast(
        error is LunoApiException && error.code == 'user-blocked'
            ? 'Bu oyuncuyla etkileşim kuramazsın.'
            : 'Arkadaşlık isteği gönderilemedi.',
      );
    } finally {
      if (_ownsSession) setState(() => friendBusy.remove(targetUid));
    }
  }

  Future<void> _respond(
    Map<String, dynamic> request, {
    required bool accept,
  }) async {
    if (!_canAct) return;
    final fromUid = request['fromUid']?.toString() ?? '';
    if (fromUid.isEmpty ||
        friendBusy.contains(fromUid) ||
        !requestRows.any((row) => row['fromUid']?.toString() == fromUid)) {
      return;
    }
    setState(() => friendBusy.add(fromUid));
    try {
      await _online.respondFriendRequest(fromUid, accept: accept);
      if (!_ownsSession) return;
      _toast(accept ? 'Arkadaşlık isteği kabul edildi.' : 'İstek reddedildi.');
      await _loadSocial();
    } catch (error) {
      _toast(
        error is LunoApiException && error.code == 'request-not-found'
            ? 'Bu istek artık beklemiyor.'
            : 'İstek güncellenemedi.',
      );
    } finally {
      if (_ownsSession) setState(() => friendBusy.remove(fromUid));
    }
  }

  Future<void> _removeFriend(Map<String, dynamic> player) async {
    if (!_canAct) return;
    final targetUid = player['uid']?.toString() ?? '';
    if (targetUid.isEmpty ||
        friendBusy.contains(targetUid) ||
        !friendRows.any((row) => row['uid']?.toString() == targetUid)) {
      return;
    }
    final confirmed = await showLunoAccountDialog<bool>(
      context: context,
      service: _online,
      builder:
          (dialogContext) => AlertDialog(
            scrollable: true,
            backgroundColor: LunoColors.bgPanel,
            titleTextStyle: LunoType.sectionTitle,
            title: const Text('Arkadaşlıktan çıkarılsın mı?'),
            content: Text(
              '${usernameFromMap(player)} artık arkadaş listende olmayacak.',
            ),
            actions: [
              LunoButton(
                expand: false,
                kind: LunoButtonKind.secondary,
                onPressed: () => dismissLunoAccountModal(dialogContext, false),
                label: 'VAZGEÇ',
              ),
              LunoButton(
                expand: false,
                kind: LunoButtonKind.danger,
                leading: const SizedBox(
                  width: 28,
                  height: 28,
                  child: LunoArt(
                    LunoAssets.friendsActionRemove,
                    width: 28,
                    height: 28,
                  ),
                ),
                onPressed: () => dismissLunoAccountModal(dialogContext, true),
                label: 'ÇIKAR',
              ),
            ],
          ),
    );
    if (confirmed != true ||
        !mounted ||
        !_ownsSession ||
        ModalRoute.of(context)?.isCurrent == false ||
        friendBusy.contains(targetUid) ||
        !friendRows.any((row) => row['uid']?.toString() == targetUid)) {
      return;
    }
    setState(() => friendBusy.add(targetUid));
    try {
      await _online.removeFriend(targetUid);
      if (!_ownsSession) return;
      _toast('Arkadaşlıktan çıkarıldı.');
      await _loadSocial();
    } catch (_) {
      _toast('Arkadaşlık kaldırılamadı.');
    } finally {
      if (_ownsSession) setState(() => friendBusy.remove(targetUid));
    }
  }

  Future<void> _openMessage(Map<String, dynamic> player) async {
    if (!_canAct) return;
    final targetUid = player['uid']?.toString() ?? '';
    if (targetUid.isEmpty) return;
    Navigator.of(context).push(
      lunoRoute(
        V216BeforeDirectMessageScreen(
          targetUid: targetUid,
          targetName: usernameFromMap(player),
          online: _online,
        ),
      ),
    );
  }

  Future<void> _inviteFriend(Map<String, dynamic> player) async {
    if (!_canAct) return;
    final targetUid = player['uid']?.toString() ?? '';
    if (targetUid.isEmpty ||
        inviteBusy.contains(targetUid) ||
        !friendRows.any((row) => row['uid']?.toString() == targetUid)) {
      return;
    }
    setState(() => inviteBusy.add(targetUid));
    try {
      final status = await _online.sendBattleV1Invite(targetUid);
      if (!_ownsSession) return;
      _toast(
        status == 'pending'
            ? 'Bu oyuncuya zaten bekleyen bir davet var.'
            : 'Dostluk maçı daveti gönderildi.',
      );
    } catch (error) {
      final message =
          error is LunoApiException && error.code == 'friend-required'
              ? 'Önce bu oyuncuyla arkadaş olmalısın.'
              : error is LunoApiException &&
                  (error.code == 'match-already-active' ||
                      error.code == 'opponent-busy')
              ? 'Oyunculardan biri şu anda maçta.'
              : 'Dostluk maçı daveti gönderilemedi.';
      _toast(message);
    } finally {
      if (_ownsSession) setState(() => inviteBusy.remove(targetUid));
    }
  }

  Future<void> _respondMatchInvite(
    Map<String, dynamic> invite, {
    required bool accept,
  }) async {
    if (!_canAct) return;
    final fromUid = invite['fromUid']?.toString() ?? '';
    if (fromUid.isEmpty || inviteBusy.contains(fromUid)) return;
    setState(() => inviteBusy.add(fromUid));
    try {
      final result = await _online.respondBattleV1Invite(
        fromUid,
        accept: accept,
      );
      final view = result['view'];
      final matchId =
          result['matchId']?.toString() ??
          (view is Map ? view['matchId']?.toString() ?? '' : '');
      if (!mounted || !_canAct) return;
      if (accept && view is Map && matchId.isNotEmpty) {
        Navigator.of(context).push(
          lunoRoute(
            BattleV1Screen(
              matchId: matchId,
              initialView: Map<String, dynamic>.from(view),
            ),
          ),
        );
      } else {
        _toast(accept ? 'Davet kabul edildi.' : 'Davet reddedildi.');
      }
    } catch (error) {
      _toast(
        error is LunoApiException && error.code == 'invite-expired'
            ? 'Bu davetin süresi dolmuş.'
            : 'Maç daveti güncellenemedi.',
      );
    } finally {
      if (_ownsSession) setState(() => inviteBusy.remove(fromUid));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text('ARKADAŞLAR'),
        actions: [
          IconButton(
            onPressed: socialLoading ? null : _loadSocial,
            tooltip: LunoLocalizations.of(context).translate('Yenile'),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: LunoBackdrop(
        art: LunoAssets.lobbySceneV29,
        overlay: const Color(0xD91C3835),
        focalPoint: const Alignment(0, -.12),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
              child: TextField(
                controller: controller,
                onChanged: (_) {
                  setState(() {
                    _searchSerial++;
                    loading = false;
                    searchActive = false;
                    searchError = null;
                    results = const [];
                  });
                },
                onSubmitted: (_) => _search(),
                scrollPadding: const EdgeInsets.only(bottom: 120),
                decoration: InputDecoration(
                  hintText: LunoLocalizations.of(
                    context,
                  ).translate('Kullanıcı adı veya Luno kodu'),
                  filled: true,
                  fillColor: LunoColors.bgPanel2,
                  prefixIcon: Padding(
                    padding: const EdgeInsets.all(10),
                    child: LunoArt(
                      LunoAssets.friendsSearch,
                      width: 26,
                      height: 26,
                    ),
                  ),
                  suffixIcon: IconButton(
                    onPressed: loading ? null : _search,
                    tooltip: LunoLocalizations.of(context).translate('Ara'),
                    icon: const Icon(Icons.arrow_forward_rounded),
                  ),
                ),
              ),
            ),
            _Tabs(
              labels: const ['ARKADAŞLAR', 'İSTEKLER', 'SIRALAMA'],
              selected: tab,
              onChanged: _changeTab,
            ),
            Expanded(child: _content()),
          ],
        ),
      ),
    );
  }

  Widget _content() {
    if (tab == 0 && searchActive) {
      if (loading) {
        return const Center(
          child: CircularProgressIndicator(color: LunoColors.gold),
        );
      }
      if (searchError != null) return _empty(searchError!);
      if (results.isEmpty) {
        return _empty(
          LunoLocalizations.of(context).isEnglish
              ? 'No players found.'
              : 'Oyuncu bulunamadı.',
        );
      }
      return ListView.builder(
        padding: const EdgeInsets.all(14),
        itemCount: results.length,
        itemBuilder: (_, index) => _player(results[index], searchResult: true),
      );
    }
    if (socialError != null &&
        !socialLoading &&
        (tab != 1 || !_friendRequestSnapshotReady)) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(socialError!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _loadSocial,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(
                  LunoLocalizations.of(context).isEnglish
                      ? 'TRY AGAIN'
                      : 'TEKRAR DENE',
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (tab == 2) {
      if (socialLoading && friendRows.isEmpty) {
        return const Center(
          child: CircularProgressIndicator(color: LunoColors.gold),
        );
      }
      if (friendRows.isEmpty) return _empty('Sıralanacak arkadaşın yok.');
      return ListView.separated(
        padding: const EdgeInsets.all(14),
        itemCount: friendRows.length,
        separatorBuilder: (_, _) => const SizedBox(height: 9),
        itemBuilder: (_, index) => _friendRankRow(friendRows[index], index),
      );
    }
    if (socialLoading && results.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: LunoColors.gold),
      );
    }
    if (tab == 1) {
      if (requestRows.isEmpty) {
        return _empty('Bekleyen istek yok', requests: true);
      }
      return ListView.builder(
        padding: const EdgeInsets.all(14),
        itemCount: requestRows.length,
        itemBuilder: (_, index) => _request(requestRows[index]),
      );
    }
    final rows = results.isNotEmpty ? results : friendRows;
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _matchInviteStream,
      builder: (context, snapshot) {
        final invites = snapshot.data ?? const <Map<String, dynamic>>[];
        if (rows.isEmpty && invites.isEmpty) {
          return _empty('Henüz arkadaşın yok. Kullanıcı adıyla ara.');
        }
        return ListView.builder(
          padding: const EdgeInsets.all(14),
          itemCount: invites.length + rows.length,
          itemBuilder:
              (_, index) =>
                  index < invites.length
                      ? _inviteTile(invites[index])
                      : _player(
                        rows[index - invites.length],
                        searchResult: results.isNotEmpty,
                      ),
        );
      },
    );
  }

  Widget _inviteTile(Map<String, dynamic> invite) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: LunoSurface(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        children: [
          LunoArt(
            LunoAssets.avatar(invite['fromAvatar']?.toString() ?? 'av_pawn'),
            width: 38,
            height: 38,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              '${usernameFromMap(invite, fallback: 'Oyuncu')} seni maça çağırıyor',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          IconButton(
            onPressed:
                inviteBusy.contains(invite['fromUid'])
                    ? null
                    : () => _respondMatchInvite(invite, accept: false),
            tooltip: LunoLocalizations.of(context).translate('Reddet'),
            icon: const LunoArt(
              LunoAssets.friendsActionReject,
              width: 30,
              height: 30,
            ),
          ),
          IconButton(
            onPressed:
                inviteBusy.contains(invite['fromUid'])
                    ? null
                    : () => _respondMatchInvite(invite, accept: true),
            tooltip: LunoLocalizations.of(context).translate('Kabul et'),
            icon: const LunoArt(
              LunoAssets.friendsActionAccept,
              width: 30,
              height: 30,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _empty(String message, {bool requests = false}) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: LunoArt(
              requests
                  ? LunoAssets.friendsRequestsEmpty
                  : 'assets/native_art/friends-welcome-v35.png',
              width: 180,
              height: 180,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: LunoType.body.copyWith(color: LunoColors.ivory),
          ),
        ],
      ),
    ),
  );

  Widget _player(Map<String, dynamic> player, {required bool searchResult}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _openFriendProfile(player),
          child: LunoSurface(
            padding: const EdgeInsets.all(11),
            color: LunoColors.bgPanel,
            borderRadius: BorderRadius.circular(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    LunoArt(
                      LunoAssets.avatar(
                        player['avatarEmoji']?.toString() ?? 'av_pawn',
                      ),
                      width: 44,
                      height: 44,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            usernameFromMap(player),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          Row(
                            children: [
                              const LunoArt(
                                LunoAssets.profileTrophy,
                                width: 28,
                                height: 28,
                              ),
                              const SizedBox(width: 5),
                              Flexible(
                                child: Text(
                                  formatTrophies(
                                    _number(
                                      player['trophies'],
                                    ).clamp(0, 1000000000),
                                  ),
                                  style: const TextStyle(
                                    color: LunoColors.gold,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child:
                      !searchResult
                          ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton.filledTonal(
                                style: IconButton.styleFrom(
                                  backgroundColor: const Color(0xFF315E69),
                                ),
                                onPressed: () {
                                  LunoFeedback.tap();
                                  _openMessage(player);
                                },
                                tooltip: LunoLocalizations.of(
                                  context,
                                ).translate('Mesaj gönder'),
                                icon: const LunoArt(
                                  LunoAssets.friendsActionMessage,
                                  width: 30,
                                  height: 30,
                                ),
                              ),
                              IconButton.filledTonal(
                                style: IconButton.styleFrom(
                                  backgroundColor: const Color(0xFF365C42),
                                ),
                                onPressed:
                                    inviteBusy.contains(player['uid'])
                                        ? null
                                        : () {
                                          LunoFeedback.tap();
                                          _inviteFriend(player);
                                        },
                                tooltip: LunoLocalizations.of(
                                  context,
                                ).translate('Maça davet et'),
                                icon: const LunoArt(
                                  LunoAssets.friendsActionBattle,
                                  width: 30,
                                  height: 30,
                                ),
                              ),
                              IconButton.filledTonal(
                                style: IconButton.styleFrom(
                                  backgroundColor: const Color(0xFF613D42),
                                ),
                                onPressed:
                                    friendBusy.contains(player['uid'])
                                        ? null
                                        : () {
                                          LunoFeedback.tap();
                                          _removeFriend(player);
                                        },
                                tooltip: LunoLocalizations.of(
                                  context,
                                ).translate('Arkadaşlıktan çıkar'),
                                icon: const LunoArt(
                                  LunoAssets.friendsActionRemove,
                                  width: 30,
                                  height: 30,
                                ),
                              ),
                            ],
                          )
                          : _searchAction(player),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _searchAction(Map<String, dynamic> player) {
    final targetUid = player['uid']?.toString() ?? '';
    final relationship = player['relationship']?.toString() ?? 'none';
    if (relationship == 'friends') {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8),
        child: Text(
          'ARKADAŞ',
          style: TextStyle(color: LunoColors.teal, fontWeight: FontWeight.w900),
        ),
      );
    }
    final pending = relationship == 'outgoing';
    return FilledButton.icon(
      onPressed:
          targetUid.isEmpty || pending || friendBusy.contains(targetUid)
              ? null
              : () => _addFriend(player),
      icon: LunoArt(
        pending ? LunoAssets.friendsActionAccept : LunoAssets.friendsActionAdd,
        width: 21,
        height: 21,
      ),
      label: Text(
        relationship == 'incoming'
            ? 'KABUL ET'
            : pending
            ? 'GÖNDERİLDİ'
            : 'EKLE',
      ),
    );
  }

  Widget _friendRankRow(Map<String, dynamic> player, int index) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _openFriendProfile(player),
        child: LunoSurface(
          padding: const EdgeInsets.all(11),
          child: Row(
            children: [
              SizedBox(
                width: 34,
                child: Text(
                  '#${index + 1}',
                  style: TextStyle(
                    color: index < 3 ? LunoColors.gold : LunoColors.textDim,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              LunoArt(
                LunoAssets.avatar(
                  player['avatarEmoji']?.toString() ?? 'av_pawn',
                ),
                width: 42,
                height: 42,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  usernameFromMap(player),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              Text(
                '${_number(player['trophies'])} kupa',
                style: const TextStyle(
                  color: LunoColors.gold,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.chevron_right_rounded,
                color: LunoColors.textDim,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    ),
  );

  void _openFriendProfile(Map<String, dynamic> player) {
    if (!_canAct || loading || socialLoading || tab == 1) return;
    final visibleRows = tab == 0 && searchActive ? results : friendRows;
    final uid = player['uid'];
    if (!visibleRows.contains(player) || uid is! String || uid.trim().isEmpty) {
      return;
    }
    Navigator.of(context).push(
      lunoRoute(
        LunoAccountScope(
          service: _online,
          page: PublicPlayerProfileScreen(targetUid: uid, online: _online),
        ),
      ),
    );
  }

  int _number(dynamic value) {
    if (value is num && !value.isFinite) return 0;
    final result = value is num ? value.toInt() : int.tryParse('$value') ?? 0;
    return result < 0 ? 0 : result;
  }

  Widget _request(Map<String, dynamic> request) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: LunoSurface(
      padding: const EdgeInsets.all(11),
      child: Row(
        children: [
          LunoArt(
            LunoAssets.avatar(request['avatarEmoji']?.toString() ?? 'av_pawn'),
            width: 44,
            height: 44,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              usernameFromMap({
                'username': request['fromUsername'],
                'name': request['fromName'],
              }),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          IconButton(
            onPressed:
                friendBusy.contains(request['fromUid'])
                    ? null
                    : () => _respond(request, accept: false),
            tooltip: LunoLocalizations.of(context).translate('Reddet'),
            color: LunoColors.danger,
            icon: const LunoArt(
              LunoAssets.friendsActionReject,
              width: 30,
              height: 30,
            ),
          ),
          IconButton(
            onPressed:
                friendBusy.contains(request['fromUid'])
                    ? null
                    : () => _respond(request, accept: true),
            tooltip: LunoLocalizations.of(context).translate('Kabul et'),
            color: LunoColors.success,
            icon: const LunoArt(
              LunoAssets.friendsActionAccept,
              width: 30,
              height: 30,
            ),
          ),
        ],
      ),
    ),
  );

  void _toast(String message) {
    if (!_canAct) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}


class V216BeforeInboxScreen extends StatefulWidget implements LunoAccountScopedPage {
  const V216BeforeInboxScreen({super.key, this.online});

  static const connectionTimeout = Duration(seconds: 12);
  final LunoOnlineService? online;

  @override
  State<V216BeforeInboxScreen> createState() => _V216BeforeInboxScreenState();
}


class _V216BeforeInboxScreenState extends State<V216BeforeInboxScreen> {
  final _requestTimeouts = ScreenRequestTimeouts();
  Stream<List<Map<String, dynamic>>>? inboxStream;
  Stream<List<Map<String, dynamic>>>? notificationStream;
  final Set<String> _readOverrides = <String>{};
  int tab = 0;
  bool markingAll = false;
  bool connecting = false;
  bool showingDetails = false;
  String? error;

  LunoOnlineService get _online => widget.online ?? LunoOnlineService.instance;
  late final String? _entryUid;
  late final int _entryRevision;
  bool get _ownsSession =>
      mounted &&
      _online.user?.uid == _entryUid &&
      _online.accountRevision == _entryRevision &&
      _online.accountFailure == null;
  bool get _canAct =>
      _ownsSession && ModalRoute.of(context)?.isCurrent != false;

  @override
  void initState() {
    super.initState();
    _entryUid = _online.user?.uid;
    _entryRevision = _online.accountRevision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_connect());
    });
  }

  @override
  void dispose() {
    _requestTimeouts.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (connecting || !_canAct) return;
    if (mounted) {
      setState(() {
        connecting = true;
        error = null;
      });
    }
    try {
      final online = _online;
      await _requestTimeouts.run(online.start(), V216BeforeInboxScreen.connectionTimeout);
      if (!online.ready || online.user == null) {
        throw const LunoApiException('network-unavailable', 0);
      }
      if (!mounted) return;
      if (!_ownsSession) return;
      setState(() {
        inboxStream = withInitialStreamTimeout(
          online.directMessageInboxStream(),
          V216BeforeInboxScreen.connectionTimeout,
        );
        notificationStream = withInitialStreamTimeout(
          online.notificationsStream(),
          V216BeforeInboxScreen.connectionTimeout,
        );
      });
    } catch (_) {
      if (_ownsSession) {
        setState(() => error = 'connection-failed');
      }
    } finally {
      if (_ownsSession) setState(() => connecting = false);
    }
  }

  Future<void> _markAllNotificationsRead() async {
    final online = _online;
    if (!_canAct || markingAll || online.unreadNotificationCount == 0) return;
    setState(() => markingAll = true);
    try {
      final confirmedIds = await online.markAllNotificationsRead();
      if (_ownsSession) setState(() => _readOverrides.addAll(confirmedIds));
    } catch (_) {
      _toast('Bildirimler şu an işaretlenemedi.');
    } finally {
      if (mounted) setState(() => markingAll = false);
    }
  }

  Future<void> _openNotification(Map<String, dynamic> row) async {
    final id = row['notificationId']?.toString().trim() ?? '';
    if (!_ownsSession || id.isEmpty || _isNotificationRead(row)) return;
    try {
      await _online.markNotificationRead(id);
      if (_ownsSession) setState(() => _readOverrides.add(id));
    } catch (_) {
      if (mounted) _toast('Bildirim okunamadı.');
    }
  }

  bool _isNotificationRead(Map<String, dynamic> row) {
    final id = row['notificationId']?.toString() ?? '';
    return row['read'] == true ||
        _readOverrides.contains(id) ||
        (_ownsSession && _online.notificationIsRead(id));
  }

  void _toast(String message) {
    if (_canAct) showLunoNotice(context, message);
  }

  Future<void> _showNotificationDetails(Map<String, dynamic> row) async {
    if (!_canAct || showingDetails) return;
    showingDetails = true;
    unawaited(_openNotification(row));
    try {
      await showLunoAccountBottomSheet<void>(
        context: context,
        service: _online,
        backgroundColor: LunoColors.bgPanel,
        builder:
            (sheetContext) => SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _notificationTitle(
                      row['type']?.toString() ?? 'general',
                      row,
                    ),
                    style: LunoType.screenTitle,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    row['message']?.toString() ?? '',
                    style: const TextStyle(fontSize: 16, height: 1.45),
                  ),
                  const SizedBox(height: 20),
                  LunoButton(
                    label: 'TAMAM',
                    backgroundArt: LunoAssets.actionSurfaceV27,
                    onPressed: () => dismissLunoAccountModal(sheetContext),
                  ),
                ],
              ),
            ),
      );
    } finally {
      showingDetails = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final online = _online;
    final english = LunoLocalizations.of(context).isEnglish;
    final connectionError =
        english
            ? 'The inbox could not be opened.'
            : 'Mesaj kutusu şu an açılamıyor.';
    return Scaffold(
      appBar: AppBar(
        title: Text(tab == 0 ? 'BİLDİRİMLER' : 'MESAJ KUTUSU'),
        actions: [
          ListenableBuilder(
            listenable: online,
            builder:
                (context, _) =>
                    tab == 0 && online.unreadNotificationCount > 0
                        ? IconButton(
                          onPressed:
                              markingAll ? null : _markAllNotificationsRead,
                          tooltip: LunoLocalizations.of(
                            context,
                          ).translate('Tümünü okundu işaretle'),
                          icon: const Icon(Icons.done_all_rounded),
                        )
                        : const SizedBox.shrink(),
          ),
          IconButton(
            onPressed: connecting ? null : _connect,
            tooltip: english ? 'Refresh' : 'Yenile',
            icon:
                connecting
                    ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: LunoBackdrop(
        art: LunoAssets.inboxSceneV27,
        overlay: const Color(0x40100A24),
        focalPoint: const Alignment(0, -.1),
        child: ListenableBuilder(
          listenable: online,
          builder: (context, _) {
            if (inboxStream == null || notificationStream == null) {
              return Center(
                child:
                    error == null
                        ? const CircularProgressIndicator(
                          color: LunoColors.gold,
                        )
                        : SingleChildScrollView(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                connectionError,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: LunoColors.textDim,
                                ),
                              ),
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                onPressed: _connect,
                                icon: const Icon(Icons.refresh_rounded),
                                label: Text(
                                  english ? 'TRY AGAIN' : 'TEKRAR DENE',
                                ),
                              ),
                            ],
                          ),
                        ),
              );
            }
            return Column(
              children: [
                if (error != null || online.lastError != null)
                  _offlineBanner(
                    error != null ? connectionError : online.lastError!,
                  ),
                _inboxTabs(online),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: LunoMotion.adaptive(
                      context,
                      LunoMotion.panelEnter,
                    ),
                    switchInCurve: Curves.easeOutCubic,
                    child: KeyedSubtree(
                      key: ValueKey(tab),
                      child: tab == 0 ? _notificationsList() : _messagesList(),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _offlineBanner(String message) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
    child: LunoSurface(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: LunoColors.bgPanel2,
      borderRadius: BorderRadius.circular(10),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded, color: Color(0xFFFFB5A7)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Color(0xFFFFD6CC), fontSize: 12),
            ),
          ),
          TextButton(onPressed: _connect, child: const Text('DENE')),
        ],
      ),
    ),
  );

  Widget _inboxTabs(LunoOnlineService online) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
    child: LayoutBuilder(builder: (context, constraints) {
      final l = LunoLocalizations.of(context);
      final painter = TextPainter(
        text: TextSpan(text: l.translate('BİLDİRİMLER'),
          style: const TextStyle(fontFamily: 'Nunito', fontSize: 13,
            fontWeight: FontWeight.w700)),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      final vertical = painter.width > (constraints.maxWidth - 8) / 2 - 22;
      painter.dispose();
      final notifications = _inboxTab(
            id: 'notifications',
            label: 'BİLDİRİMLER',
            art: LunoAssets.settingsNotification,
            selected: tab == 0,
            badge: online.unreadNotificationCount,
            onTap: () => setState(() => tab = 0),
          );
      final messages = _inboxTab(
            id: 'messages',
            label: 'MESAJLAR',
            art: LunoAssets.friendsActionMessage,
            selected: tab == 1,
            badge: online.unreadDirectMessageCount,
            onTap: () => setState(() => tab = 1),
          );
      return vertical
          ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              notifications, const SizedBox(height: 8), messages,
            ])
          : Row(children: [Expanded(child: notifications),
              const SizedBox(width: 8), Expanded(child: messages)]);
    }),
  );

  Widget _inboxTab({
    required String id,
    required String label,
    required String art,
    required bool selected,
    required int badge,
    required VoidCallback onTap,
  }) => Material(
    color: Colors.transparent,
    child: InkWell(
      key: ValueKey('inbox-tab-$id'),
      onTap:
          selected
              ? null
              : () {
                LunoFeedback.tap();
                onTap();
              },
      borderRadius: BorderRadius.circular(11),
      child: AnimatedContainer(
        duration: LunoMotion.adaptive(context, LunoMotion.micro),
        curve: Curves.easeOutCubic,
        constraints: const BoxConstraints(minHeight: 46),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          gradient:
              selected
                  ? const LinearGradient(
                    colors: [Color(0xFF397A80), Color(0xFF24515A)],
                  )
                  : const LinearGradient(
                    colors: [LunoColors.bgPanel2, LunoColors.bgPanel],
                  ),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: selected ? LunoColors.gold : LunoColors.line,
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final stacked =
                constraints.maxWidth < 200 ||
                MediaQuery.textScalerOf(context).scale(13) > 18;
            final title = Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Nunito',
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            );
            final symbol = LunoArt(art, width: 28, height: 28);
            return Semantics(
              selected: selected,
              button: true,
              child:
                  stacked
                      ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              symbol,
                              if (badge > 0) ...[
                                const SizedBox(width: 7),
                                _InboxBadge(value: badge),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          title,
                        ],
                      )
                      : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          symbol,
                          const SizedBox(width: 7),
                          Flexible(child: title),
                          if (badge > 0) ...[
                            const SizedBox(width: 7),
                            _InboxBadge(value: badge),
                          ],
                        ],
                      ),
            );
          },
        ),
      ),
    ),
  );

  Widget _notificationsList() => StreamBuilder<List<Map<String, dynamic>>>(
    stream: notificationStream,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return _streamError(
          LunoLocalizations.of(context).isEnglish
              ? 'Notifications could not be refreshed.'
              : 'Bildirimler yenilenemedi.',
        );
      }
      if (!snapshot.hasData &&
          snapshot.connectionState == ConnectionState.waiting) {
        return const Center(child: CircularProgressIndicator());
      }
      final rows = snapshot.data ?? const [];
      if (rows.isEmpty) return _emptyNotifications();
      return ListView.separated(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
        itemCount: rows.length,
        separatorBuilder: (_, _) => const SizedBox(height: 9),
        itemBuilder: (_, index) => _notificationTile(rows[index]),
      );
    },
  );

  Widget _messagesList() => StreamBuilder<List<Map<String, dynamic>>>(
    stream: inboxStream,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return _streamError(
          LunoLocalizations.of(context).isEnglish
              ? 'The inbox could not be refreshed.'
              : 'Mesaj kutusu yenilenemedi.',
        );
      }
      if (!snapshot.hasData &&
          snapshot.connectionState == ConnectionState.waiting) {
        return const Center(child: CircularProgressIndicator());
      }
      final rows = snapshot.data ?? const [];
      if (rows.isEmpty) return _emptyInbox();
      return ListView.separated(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
        itemCount: rows.length,
        separatorBuilder: (_, _) => const SizedBox(height: 9),
        itemBuilder: (_, index) => _conversationTile(rows[index]),
      );
    },
  );

  Widget _streamError(String message) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: LunoColors.textDim),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: connecting ? null : _connect,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(
              LunoLocalizations.of(context).isEnglish
                  ? 'TRY AGAIN'
                  : 'TEKRAR DENE',
            ),
          ),
        ],
      ),
    ),
  );

  Widget _emptyNotifications() => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const LunoArt(LunoAssets.settingsNotification, width: 64, height: 64),
          const SizedBox(height: 14),
          const Text(
            'Henüz bildirim yok',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          const Text(
            'Arkadaşlık ve maç hareketlerin burada görünecek.',
            textAlign: TextAlign.center,
            style: TextStyle(color: LunoColors.textDim),
          ),
        ],
      ),
    ),
  );

  Widget _notificationTile(Map<String, dynamic> row) {
    final read = _isNotificationRead(row);
    final type = row['type']?.toString() ?? 'general';
    return LunoSurface(
      padding: EdgeInsets.zero,
      color: read ? LunoColors.bgPanel : LunoColors.bgRaised,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: () => _showNotificationDetails(row),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: LunoColors.bgPanel2,
                  shape: BoxShape.circle,
                  border: Border.all(color: LunoColors.line),
                ),
                child: LunoArt(_notificationArt(type), width: 40, height: 40),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _notificationTitle(type, row),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      row['message']?.toString() ?? '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: LunoColors.textDim,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _notificationTime(row['ts']),
                      style: const TextStyle(
                        color: Color(0xFFB5CED0),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              read
                  ? const Icon(Icons.chevron_right_rounded)
                  : const LunoStatusDot(active: true),
            ],
          ),
        ),
      ),
    );
  }

  String _notificationArt(String type) => switch (type) {
    'friend_request' || 'friend_accepted' => LunoAssets.friendsTab,
    'match_invite' || 'match_invite_accepted' => LunoAssets.friendsActionBattle,
    _ => LunoAssets.settingsNotification,
  };

  String _notificationTitle(String type, Map<String, dynamic> row) {
    final name = row['fromName']?.toString().trim();
    final player = name == null || name.isEmpty ? 'Luno oyuncusu' : name;
    return switch (type) {
      'friend_request' => '$player arkadaşlık isteği',
      'friend_accepted' => 'Arkadaşlık isteği kabul edildi',
      'match_invite' => '$player maç daveti',
      'match_invite_accepted' => 'Maç daveti kabul edildi',
      _ => 'Luno bildirimi',
    };
  }

  String _notificationTime(Object? raw) {
    final timestamp = raw is num ? raw.toInt() : int.tryParse('$raw') ?? 0;
    if (timestamp <= 0) return '';
    final age = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(timestamp),
    );
    if (age.inMinutes < 1) return 'Az önce';
    if (age.inHours < 1) return '${age.inMinutes} dk önce';
    if (age.inDays < 1) return '${age.inHours} sa önce';
    if (age.inDays < 7) return '${age.inDays} gün önce';
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
  }

  Widget _emptyInbox() => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const LunoArt(LunoAssets.friendsEmpty, width: 140, height: 140),
          const SizedBox(height: 14),
          const Text(
            'Henüz mesaj yok',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          const Text(
            'Arkadaşlarınla mesajlaştıkça gelen kutun burada dolacak.',
            textAlign: TextAlign.center,
            style: TextStyle(color: LunoColors.textDim),
          ),
        ],
      ),
    ),
  );

  Widget _conversationTile(Map<String, dynamic> row) {
    final targetUid = row['targetUid']?.toString() ?? '';
    return LunoSurface(
      padding: const EdgeInsets.all(11),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const LunoArt(LunoAssets.statusProfile, width: 46, height: 46),
        title: Text(
          usernameFromMap(row),
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        subtitle: Text(
          row['last']?.toString() ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: LunoColors.textDim),
        ),
        trailing:
            row['unread'] == true
                ? const LunoStatusDot(active: true)
                : const Icon(Icons.chevron_right_rounded),
        onTap:
            targetUid.isEmpty
                ? null
                : () {
                  if (!_canAct) return;
                  Navigator.of(context).push(
                    lunoRoute(
                      V216BeforeDirectMessageScreen(
                        targetUid: targetUid,
                        targetName: usernameFromMap(row),
                      ),
                    ),
                  );
                },
      ),
    );
  }
}


class _InboxBadge extends StatelessWidget {
  final int value;

  const _InboxBadge({required this.value});

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
    padding: const EdgeInsets.symmetric(horizontal: 4),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: const Color(0xFFE23A4A),
      shape: value > 9 ? BoxShape.rectangle : BoxShape.circle,
      borderRadius: value > 9 ? BorderRadius.circular(8) : null,
      border: Border.all(color: Colors.white70, width: 1.4),
    ),
    child: Text(
      value > 99
          ? '99+'
          : value > 9
          ? '9+'
          : '$value',
      style: const TextStyle(
        color: Colors.white,
        fontSize: 9,
        fontWeight: FontWeight.w900,
        height: 1,
      ),
    ),
  );
}


class V216BeforeDirectMessageScreen extends StatefulWidget
    implements LunoAccountScopedPage {
  static const initialLoadTimeout = Duration(seconds: 12);
  final String targetUid;
  final String targetName;
  final LunoOnlineService? online;

  const V216BeforeDirectMessageScreen({
    super.key,
    required this.targetUid,
    required this.targetName,
    this.online,
  });

  @override
  State<V216BeforeDirectMessageScreen> createState() => _V216BeforeDirectMessageScreenState();
}


class _V216BeforeDirectMessageScreenState extends State<V216BeforeDirectMessageScreen> {
  final _ugcConsent = UgcConsent();
  final _requestTimeouts = ScreenRequestTimeouts();
  final input = TextEditingController();
  Stream<List<Map<String, dynamic>>>? messagesStream;
  bool sending = false;
  bool opening = false;
  bool _blocked = false;
  String? error;
  Timer? _readTimer;
  String _lastReadKey = '';
  String _scheduledReadKey = '';
  String? _scheduledReadMessageId;
  String _failedReadKey = '';
  int? _readInFlightRevision;
  int _readRetryCount = 0;
  int _conversationRevision = 0;
  late final String? _entryUid;
  late final int _entryRevision;
  LunoOnlineService get _online => widget.online ?? LunoOnlineService.instance;
  bool get _ownsSession =>
      mounted &&
      _online.user?.uid == _entryUid &&
      _online.accountRevision == _entryRevision &&
      _online.accountFailure == null;
  bool get _canAct =>
      _ownsSession && ModalRoute.of(context)?.isCurrent != false;
  bool _ownsConversation(int revision, String uid) =>
      _ownsSession &&
      _conversationRevision == revision &&
      widget.targetUid == uid;

  @override
  void initState() {
    super.initState();
    _entryUid = _online.user?.uid;
    _entryRevision = _online.accountRevision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_open());
    });
  }

  @override
  void didUpdateWidget(covariant V216BeforeDirectMessageScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.targetUid == widget.targetUid) return;
    _requestTimeouts.cancelPending();
    ++_conversationRevision;
    _readTimer?.cancel();
    _readTimer = null;
    _lastReadKey = '';
    _scheduledReadKey = '';
    _scheduledReadMessageId = null;
    _failedReadKey = '';
    _readInFlightRevision = null;
    _readRetryCount = 0;
    messagesStream = null;
    input.clear();
    sending = false;
    opening = false;
    _blocked = false;
    error = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_canAct) unawaited(_open());
    });
  }

  @override
  void dispose() {
    _ugcConsent.dispose();
    _requestTimeouts.dispose();
    _readTimer?.cancel();
    input.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    if (!_canAct || opening || _blocked) {
      return;
    }
    opening = true;
    final revision = _conversationRevision;
    final targetUid = widget.targetUid;
    if (mounted) {
      setState(() {
        messagesStream = null;
        error = null;
      });
    }
    try {
      final online = _online;
      await _requestTimeouts.run(
        online.start(),
        V216BeforeDirectMessageScreen.initialLoadTimeout,
      );
      if (!_ownsConversation(revision, targetUid)) return;
      if (!online.ready || online.user == null) {
        throw const LunoApiException('network-unavailable', 0);
      }
      if (!mounted || !_ownsConversation(revision, targetUid)) return;
      final conversationId = await _ugcConsent.run(
        context: context,
        online: online,
        operation: () => online.openDirectMessage(targetUid),
        isRelevant: () => _ownsConversation(revision, targetUid) && !_blocked,
      );
      if (conversationId == null) {
        if (_ownsConversation(revision, targetUid) && _canAct) {
          setState(
            () =>
                error =
                    LunoLocalizations.of(context).isEnglish
                        ? 'Accept the community rules to start a conversation.'
                        : 'Konuşma başlatmak için topluluk kurallarını kabul et.',
          );
        }
        return;
      }
      if (conversationId.isEmpty) throw StateError('conversation-not-created');
      if (!_ownsConversation(revision, targetUid)) return;
      setState(
        () =>
            messagesStream = withInitialStreamTimeout(
              online.directMessagesStream(targetUid),
              V216BeforeDirectMessageScreen.initialLoadTimeout,
            ),
      );
    } catch (_) {
      if (_ownsConversation(revision, targetUid)) {
        setState(() => error = 'Konuşma açılamadı.');
      }
    } finally {
      if (_ownsConversation(revision, targetUid)) opening = false;
    }
  }

  Future<void> _send() async {
    if (!_canAct || _blocked) return;
    final revision = _conversationRevision;
    final targetUid = widget.targetUid;
    if (input.text.trim().isEmpty || sending || messagesStream == null) return;
    final text = normalizeUgcText(
      input.text,
      maxLength: directMessageMaxLength,
    );
    if (text == null) {
      _toast(
        ugcTextError(
          english: LunoLocalizations.of(context).isEnglish,
          bio: false,
        ),
      );
      return;
    }
    setState(() {
      sending = true;
      error = null;
    });
    try {
      final online = _online;
      final sent = await _ugcConsent.run(
        context: context,
        online: online,
        isRelevant: () => _ownsConversation(revision, targetUid) && !_blocked,
        operation: () async {
          if (!_ownsConversation(revision, targetUid) || !_canAct || _blocked) {
            return false;
          }
          await online.sendDirectMessage(targetUid, text);
          return true;
        },
      );
      if (sent != true) return;
      if (_ownsConversation(revision, targetUid) &&
          normalizeUgcText(input.text, maxLength: directMessageMaxLength) ==
              text) {
        input.clear();
      }
    } catch (_) {
      if (_ownsConversation(revision, targetUid) && _canAct) {
        setState(() => error = 'Mesaj gönderilemedi.');
      }
    } finally {
      if (_ownsConversation(revision, targetUid)) {
        setState(() => sending = false);
      }
    }
  }

  void _scheduleRead(List<Map<String, dynamic>> rows) {
    if (!_canAct) return;
    final key = directMessageReadKey(rows);
    if (key.isEmpty ||
        key == _lastReadKey ||
        key == _scheduledReadKey ||
        key == _failedReadKey) {
      return;
    }
    final messageId = rows.last['messageId'];
    if (messageId is! String ||
        !RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(messageId)) {
      return;
    }
    _scheduledReadKey = key;
    _scheduledReadMessageId = messageId;
    _readRetryCount = 0;
    final revision = _conversationRevision;
    final targetUid = widget.targetUid;
    _readTimer?.cancel();
    _readTimer = null;
    if (_readInFlightRevision == revision) return;
    _readTimer = Timer(const Duration(milliseconds: 250), () {
      _readTimer = null;
      unawaited(_markConversationRead(key, messageId, revision, targetUid));
    });
  }

  Future<void> _markConversationRead(
    String key,
    String messageId,
    int revision,
    String targetUid,
  ) async {
    if (!_ownsConversation(revision, targetUid)) return;
    if (ModalRoute.of(context)?.isCurrent == false) {
      if (_scheduledReadKey == key) {
        _scheduledReadKey = '';
        _scheduledReadMessageId = null;
      }
      return;
    }
    if (_scheduledReadKey != key) return;
    if (_readInFlightRevision == revision) return;
    _readInFlightRevision = revision;
    try {
      await _online.markDirectMessageRead(targetUid, lastMessageId: messageId);
      if (!mounted ||
          !_ownsConversation(revision, targetUid) ||
          _scheduledReadKey != key) {
        return;
      }
      _lastReadKey = key;
      _scheduledReadKey = '';
      _scheduledReadMessageId = null;
      _readRetryCount = 0;
    } catch (_) {
      if (!mounted ||
          !_ownsConversation(revision, targetUid) ||
          _scheduledReadKey != key) {
        return;
      }
      if (ModalRoute.of(context)?.isCurrent == false || _readRetryCount >= 1) {
        if (_readRetryCount >= 1) _failedReadKey = key;
        _scheduledReadKey = '';
        _scheduledReadMessageId = null;
        return;
      }
      _readRetryCount += 1;
      _readTimer?.cancel();
      _readTimer = Timer(const Duration(seconds: 2), () {
        _readTimer = null;
        unawaited(_markConversationRead(key, messageId, revision, targetUid));
      });
    } finally {
      if (_ownsConversation(revision, targetUid) &&
          _readInFlightRevision == revision) {
        _readInFlightRevision = null;
        // Only the latest snapshot remains queued while a receipt is in flight.
        final pendingKey = _scheduledReadKey;
        final pendingMessageId = _scheduledReadMessageId;
        if (pendingKey.isNotEmpty &&
            pendingKey != key &&
            pendingMessageId != null &&
            _canAct) {
          _readTimer?.cancel();
          _readTimer = Timer(const Duration(milliseconds: 250), () {
            _readTimer = null;
            unawaited(
              _markConversationRead(
                pendingKey,
                pendingMessageId,
                revision,
                targetUid,
              ),
            );
          });
        } else if (pendingKey != key && !_canAct) {
          _scheduledReadKey = '';
          _scheduledReadMessageId = null;
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final online = _online;
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: Text(
          widget.targetName,
          localize: false,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          SocialSafetyActions(
            online: online,
            targetUid: widget.targetUid,
            onBlocked: (target) {
              if (!_ownsSession || target != widget.targetUid) return;
              _requestTimeouts.cancelPending();
              ++_conversationRevision;
              _readTimer?.cancel();
              _readTimer = null;
              input.clear();
              setState(() {
                _blocked = true;
                messagesStream = null;
                opening = false;
                sending = false;
                error =
                    LunoLocalizations.of(context).isEnglish
                        ? 'Player blocked. Manage blocked players in Settings.'
                        : 'Oyuncu engellendi. Engellenen oyuncuları ayarlardan yönetebilirsin.';
              });
            },
          ),
        ],
      ),
      body: LunoBackdrop(
        art: LunoAssets.inboxSceneV27,
        overlay: const Color(0xD91C3835),
        focalPoint: const Alignment(0, .25),
        child: Column(
          children: [
            Expanded(
              child:
                  messagesStream == null
                      ? Center(
                        child:
                            error == null
                                ? const CircularProgressIndicator(
                                  color: LunoColors.gold,
                                )
                                : SingleChildScrollView(
                                  child: Padding(
                                    padding: const EdgeInsets.all(18),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          LunoLocalizations.of(
                                                    context,
                                                  ).isEnglish &&
                                                  !_blocked
                                              ? 'The conversation could not be opened.'
                                              : error!,
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            color: LunoColors.textDim,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        if (!_blocked)
                                          OutlinedButton.icon(
                                            onPressed: opening ? null : _open,
                                            icon: const Icon(
                                              Icons.refresh_rounded,
                                            ),
                                            label: Text(
                                              LunoLocalizations.of(
                                                    context,
                                                  ).isEnglish
                                                  ? 'TRY AGAIN'
                                                  : 'YENİDEN DENE',
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                      )
                      : StreamBuilder<List<Map<String, dynamic>>>(
                        stream: messagesStream,
                        builder: (context, snapshot) {
                          final rows = snapshot.data ?? const [];
                          if (snapshot.hasError) {
                            return Center(
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.all(18),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      LunoLocalizations.of(context).isEnglish
                                          ? 'Messages could not be loaded.'
                                          : 'Mesajlar yüklenemedi.',
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 12),
                                    OutlinedButton.icon(
                                      onPressed: opening ? null : _open,
                                      icon: const Icon(Icons.refresh_rounded),
                                      label: Text(
                                        LunoLocalizations.of(context).isEnglish
                                            ? 'TRY AGAIN'
                                            : 'YENİDEN DENE',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }
                          if (!snapshot.hasData &&
                              snapshot.connectionState ==
                                  ConnectionState.waiting) {
                            return const Center(
                              child: CircularProgressIndicator(
                                color: LunoColors.gold,
                              ),
                            );
                          }
                          if (rows.isEmpty) {
                            return Center(
                              child: Text(
                                LunoLocalizations.of(context).isEnglish
                                    ? 'Start the conversation.'
                                    : 'Konuşmayı başlat.',
                                style: const TextStyle(
                                  color: LunoColors.textDim,
                                ),
                              ),
                            );
                          }
                          _scheduleRead(rows);
                          return ListView.builder(
                            padding: const EdgeInsets.all(14),
                            itemCount: rows.length,
                            itemBuilder: (_, index) {
                              final row = rows[index];
                              final mine = row['from'] == online.user?.uid;
                              return Align(
                                alignment:
                                    mine
                                        ? Alignment.centerRight
                                        : Alignment.centerLeft,
                                child: Container(
                                  constraints: const BoxConstraints(
                                    maxWidth: 310,
                                  ),
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 13,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color:
                                        mine
                                            ? LunoColors.bgRaised
                                            : LunoColors.bgPanel2,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        row['text']?.toString() ?? '',
                                        localize: false,
                                        style: const TextStyle(
                                          color: LunoColors.ivory,
                                          fontSize: 15,
                                          height: 1.4,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      if (!mine && row['messageId'] is String)
                                        Align(
                                          alignment: Alignment.centerRight,
                                          child: SocialSafetyActions(
                                            key: ValueKey((
                                              widget.targetUid,
                                              row['messageId'],
                                            )),
                                            online: online,
                                            targetUid: widget.targetUid,
                                            messageId:
                                                row['messageId'] as String,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
            ),
            if (error != null && messagesStream != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Text(
                  error!,
                  style: const TextStyle(color: LunoColors.danger),
                ),
              ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        enabled: !_blocked,
                        controller: input,
                        minLines: 1,
                        maxLines: 3,
                        scrollPadding: const EdgeInsets.only(bottom: 96),
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        decoration: InputDecoration(
                          hintText: LunoLocalizations.of(
                            context,
                          ).translate('Mesaj yaz...'),
                          filled: true,
                          fillColor: LunoColors.bgPanel2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: input,
                      builder:
                          (context, value, _) => IconButton.filled(
                            style: IconButton.styleFrom(
                              backgroundColor: const Color(0xFF397C88),
                              foregroundColor: Colors.white,
                              minimumSize: const Size(48, 48),
                            ),
                            onPressed:
                                sending ||
                                        messagesStream == null ||
                                        value.text.trim().isEmpty
                                    ? null
                                    : () {
                                      LunoFeedback.tap();
                                      _send();
                                    },
                            tooltip: LunoLocalizations.of(
                              context,
                            ).translate('Gönder'),
                            icon:
                                sending
                                    ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: LunoColors.gold,
                                      ),
                                    )
                                    : const Icon(Icons.send_rounded),
                          ),
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

  void _toast(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));
}


class V216BeforeEditProfileScreen extends StatefulWidget
    implements LunoAccountScopedPage {
  const V216BeforeEditProfileScreen({super.key, this.online, this.playerStore});

  final LunoOnlineService? online;
  final GameStore? playerStore;

  @override
  State<V216BeforeEditProfileScreen> createState() => _V216BeforeEditProfileScreenState();
}


class _V216BeforeEditProfileScreenState extends State<V216BeforeEditProfileScreen> {
  final _requestTimeouts = ScreenRequestTimeouts();
  final _ugcConsent = UgcConsent();
  static const countryLabels = <String, String>{
    'TR': 'Türkiye',
    'US': 'United States',
    'GB': 'United Kingdom',
    'DE': 'Deutschland',
    'FR': 'France',
    'IT': 'Italia',
    'ES': 'Espana',
    'NL': 'Nederland',
    'RU': 'Rossiya',
    'JP': 'Japan',
    'CN': 'China',
    'KR': 'South Korea',
    'BR': 'Brasil',
    'AR': 'Argentina',
    'MX': 'Mexico',
    'IN': 'India',
    'AU': 'Australia',
    'CA': 'Canada',
    'PL': 'Polska',
    'SE': 'Sverige',
    'NO': 'Norge',
    'FI': 'Suomi',
    'DK': 'Danmark',
    'GR': 'Ellada',
    'PT': 'Portugal',
    'BE': 'Belgique',
    'CH': 'Schweiz',
    'AT': 'Osterreich',
    'IE': 'Ireland',
    'UA': 'Ukraine',
    'AZ': 'Azerbaijan',
    'SA': 'Saudi Arabia',
    'AE': 'United Arab Emirates',
    'EG': 'Egypt',
    'ZA': 'South Africa',
  };
  late final TextEditingController bio;
  String country = 'TR';
  String avatar = 'av_pawn';
  bool saving = false;
  String? _bioError;
  late final AccountOperationGuard editorOwner;
  GameStore get store => widget.playerStore ?? GameStore.instance;
  LunoOnlineService get online => widget.online ?? LunoOnlineService.instance;

  @override
  void initState() {
    super.initState();
    editorOwner = AccountOperationGuard(store, online);
    bio = TextEditingController(text: store.data.bio);
    final savedCountry = store.data.country.toUpperCase();
    country = countryLabels.containsKey(savedCountry) ? savedCountry : 'TR';
    avatar = store.data.avatarEmoji;
  }

  @override
  void dispose() {
    _ugcConsent.dispose();
    _requestTimeouts.dispose();
    bio.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!mounted || ModalRoute.of(context)?.isCurrent == false || saving) {
      return;
    }
    final english = LunoLocalizations.of(context).isEnglish;
    if (!editorOwner.isCurrent) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            english
                ? 'Your account changed. Reopen the profile editor.'
                : 'Hesabın değişti. Profil düzenleyicisini yeniden aç.',
          ),
        ),
      );
      return;
    }
    final biography = normalizeUgcText(
      bio.text,
      maxLength: bioMaxLength,
      allowEmpty: true,
    );
    if (biography == null) {
      setState(() => _bioError = ugcTextError(english: english, bio: true));
      return;
    }
    final submitted = <String, String>{
      'country': country,
      'avatarEmoji': avatar,
      'bio': biography,
    };
    setState(() {
      saving = true;
      _bioError = null;
    });
    var synced = false;
    var declined = false;
    try {
      await _requestTimeouts.run(online.start(), const Duration(seconds: 12));
      if (!mounted || ModalRoute.of(context)?.isCurrent == false) return;
      editorOwner.check();
      if (online.isOnline) {
        final result = await _ugcConsent.run(
          context: context,
          online: online,
          playerStore: store,
          operation: () => online.updateProfile(submitted),
        );
        if (result == null) {
          declined = true;
        } else {
          editorOwner.check();
          store.applyServerState(
            validateProfileUpdateResult(result, submitted),
          );
          editorOwner.check();
          synced = true;
        }
      }
    } on LunoApiException catch (error) {
      if (error.code == 'invalid-bio' && mounted && editorOwner.isCurrent) {
        setState(() => _bioError = ugcTextError(english: english, bio: true));
      }
    } catch (_) {
      // Do not close the editor when the remote write failed: a local-only
      // bio is not visible to friends and must not look like a completed save.
    } finally {
      if (mounted) setState(() => saving = false);
    }
    if (!mounted) return;
    if (ModalRoute.of(context)?.isCurrent == false) return;
    if (!editorOwner.isCurrent) return;
    if (!synced) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            declined
                ? (english
                    ? 'Accept the community rules before publishing your bio.'
                    : 'Biyografini yayınlamadan önce topluluk kurallarını kabul et.')
                : english
                ? 'Your profile could not be saved. Check your connection and try again.'
                : 'Profil sunucuya kaydedilemedi. Bağlantıyı kontrol edip tekrar dene.',
          ),
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(english ? 'Profile updated.' : 'Profil güncellendi.'),
      ),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    const avatars = [
      'av_pawn',
      'av_knight',
      'av_bishop',
      'av_rook',
      'av_queen',
      'av_king',
      'av_robot',
      'av_robotcrown',
      'av_crown',
      'av_lightning',
      'av_fire',
    ];
    final english = LunoLocalizations.of(context).isEnglish;
    final avatarNames =
        english
            ? const [
              'Pawn',
              'Knight',
              'Bishop',
              'Rook',
              'Queen',
              'King',
              'Robot',
              'Robot King',
              'Crown',
              'Lightning',
              'Flame',
            ]
            : const [
              'Piyon',
              'At',
              'Fil',
              'Kale',
              'Vezir',
              'Şah',
              'Robot',
              'Robot Kral',
              'Taç',
              'Yıldırım',
              'Alev',
            ];
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: Text(english ? 'EDIT PROFILE' : 'PROFİLİ DÜZENLE'),
        actions: [
          IconButton(
            onPressed: saving ? null : _save,
            tooltip: english ? 'Save' : 'Kaydet',
            icon: const Icon(Icons.check_rounded),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            Center(
              child: Container(
                width: 104,
                height: 104,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: LunoColors.bgPanel,
                  shape: BoxShape.circle,
                  border: Border.all(color: LunoColors.gold, width: 2),
                  boxShadow: const [
                    BoxShadow(color: Color(0x66000000), blurRadius: 12),
                  ],
                ),
                child: LunoArt(
                  LunoAssets.avatar(avatar),
                  width: 88,
                  height: 88,
                ),
              ),
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<String>(
              initialValue: country,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: english ? 'Country' : 'Ülke',
              ),
              items:
                  countryLabels.entries
                      .map(
                        (entry) => DropdownMenuItem(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                      )
                      .toList(),
              onChanged:
                  saving
                      ? null
                      : (value) {
                        if (value != null) setState(() => country = value);
                      },
            ),
            const SizedBox(height: 14),
            TextField(
              controller: bio,
              readOnly: saving,
              maxLength: bioMaxLength,
              maxLines: 4,
              scrollPadding: const EdgeInsets.only(bottom: 160),
              decoration: InputDecoration(
                labelText: english ? 'Bio' : 'Biyo',
                errorText: _bioError,
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              english ? 'AVATAR ICON' : 'AVATAR İKONU',
              style: const TextStyle(
                color: LunoColors.gold,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: avatars.length,
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 180,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                mainAxisExtent:
                    96 + MediaQuery.textScalerOf(context).scale(14) * 3.2,
              ),
              itemBuilder: (_, index) {
                final selected = avatar == avatars[index];
                return Semantics(
                  selected: selected,
                  button: true,
                  label: avatarNames[index],
                  child: Material(
                    color: selected ? LunoColors.bgRaised : LunoColors.bgPanel,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(
                        color: selected ? LunoColors.gold : LunoColors.bgPanel2,
                        width: selected ? 2 : 1,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap:
                          saving
                              ? null
                              : () => setState(() => avatar = avatars[index]),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 68,
                              height: 68,
                              child: LunoArt(LunoAssets.avatar(avatars[index])),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              avatarNames[index],
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color:
                                    selected
                                        ? LunoColors.gold
                                        : LunoColors.ivory,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: saving ? null : _save,
              icon: const Icon(Icons.save_rounded),
              label: Text(english ? 'SAVE' : 'KAYDET'),
            ),
          ],
        ),
      ),
    );
  }
}


class _Tabs extends StatelessWidget {
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;
  const _Tabs({
    required this.labels,
    required this.selected,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) {
    final l = LunoLocalizations.of(context);
    final style = DefaultTextStyle.of(
      context,
    ).style.merge(const TextStyle(fontWeight: FontWeight.w700, fontSize: 12));
    var minimumWidth = 48.0;
    for (final label in labels) {
      final painter = TextPainter(
        text: TextSpan(text: l.translate(label), style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      if (painter.width + 12 > minimumWidth) minimumWidth = painter.width + 12;
      painter.dispose();
    }
    return Container(
      color: LunoColors.bgPanel,
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
      child: LayoutBuilder(
        builder: (context, box) {
          final width = (box.maxWidth / labels.length).clamp(
            minimumWidth,
            double.infinity,
          );
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < labels.length; i++)
                  SizedBox(
                    width: width,
                    child: Semantics(
                      selected: selected == i,
                      button: true,
                      child: InkWell(
                        onTap:
                            selected == i
                                ? null
                                : () {
                                  LunoFeedback.tap();
                                  onChanged(i);
                                },
                        borderRadius: BorderRadius.circular(8),
                        child: AnimatedContainer(
                          duration: LunoMotion.adaptive(
                            context,
                            LunoMotion.micro,
                          ),
                          constraints: const BoxConstraints(minHeight: 48),
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(
                            vertical: 10,
                            horizontal: 4,
                          ),
                          decoration: BoxDecoration(
                            color: LunoColors.bgPanel,
                            image: lunoFace(
                              selected == i
                                  ? LunoVisualAssets.selected
                                  : LunoVisualAssets.inactive,
                              button: true,
                              opacity: selected == i ? 1 : .65,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            labels[i],
                            maxLines: 1,
                            softWrap: false,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color:
                                  selected == i
                                      ? LunoColors.gold
                                      : LunoColors.textDim,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
