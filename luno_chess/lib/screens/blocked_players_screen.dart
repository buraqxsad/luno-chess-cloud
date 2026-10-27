import 'dart:async';
import 'package:flutter/material.dart';

import '../i18n/luno_localizations.dart';
import '../navigation/luno_account_modal.dart';
import '../navigation/luno_account_scope.dart';
import '../services/luno_online_service.dart';
import '../services/social_safety_result.dart';
import '../theme/luno_assets.dart';
import '../widgets/luno_surface.dart';

class BlockedPlayersScreen extends StatefulWidget
    implements LunoAccountScopedPage {
  const BlockedPlayersScreen({super.key, required this.online});
  final LunoOnlineService online;
  @override
  State<BlockedPlayersScreen> createState() => _BlockedPlayersScreenState();
}

class _BlockedPlayersScreenState extends State<BlockedPlayersScreen> {
  List<BlockedPlayer> _players = const [];
  bool _loading = true;
  bool _loadInFlight = false;
  bool _failed = false;
  String? _nextPageToken;
  final _seenPageTokens = <String>{};
  final _unavailableUids = <String>{};
  String? _busyUid;
  late String? _owner;
  late int _revision;
  int _serial = 0;
  bool get _ownsAccount =>
      mounted &&
      _owner != null &&
      widget.online.user?.uid == _owner &&
      widget.online.accountRevision == _revision &&
      widget.online.accountFailure == null;
  bool get _canAct =>
      _ownsAccount && ModalRoute.of(context)?.isCurrent != false;

  void _capture() {
    _owner = widget.online.user?.uid;
    _revision = widget.online.accountRevision;
  }

  @override
  void initState() {
    super.initState();
    _capture();
    widget.online.addListener(_checkOwner);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_canAct) unawaited(_load());
    });
  }

  @override
  void didUpdateWidget(covariant BlockedPlayersScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.online == widget.online) return;
    oldWidget.online.removeListener(_checkOwner);
    widget.online.addListener(_checkOwner);
    ++_serial;
    _capture();
    _players = const [];
    _busyUid = null;
    _loading = true;
    _loadInFlight = false;
    _failed = false;
    _nextPageToken = null;
    _seenPageTokens.clear();
    _unavailableUids.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_canAct) unawaited(_load());
    });
  }

  void _checkOwner() {
    if (!mounted || _ownsAccount) return;
    ++_serial;
    setState(() {
      _players = const [];
      _nextPageToken = null;
      _seenPageTokens.clear();
      _unavailableUids.clear();
      _busyUid = null;
      _loading = false;
      _loadInFlight = false;
      _failed = true;
    });
  }

  @override
  void dispose() {
    widget.online.removeListener(_checkOwner);
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    if (!_canAct || _busyUid != null || _loadInFlight) return;
    final token = more ? _nextPageToken : null;
    if (more && token == null) return;
    _loadInFlight = true;
    final serial = ++_serial;
    setState(() {
      _loading = !more;
      _failed = false;
    });
    try {
      final page = await widget.online.blockedPlayersPage(pageToken: token);
      if (!_canAct || serial != _serial) {
        if (_ownsAccount && serial == _serial) _failed = true;
        return;
      }
      final players = more ? [..._players, ...page.players] : page.players;
      if (players.map((player) => player.uid).toSet().length != players.length ||
          (more &&
              page.nextPageToken != null &&
              _seenPageTokens.contains(page.nextPageToken))) {
        throw const FormatException('Blocked-list page did not advance');
      }
      setState(() {
        if (!more) {
          _seenPageTokens.clear();
          _unavailableUids.clear();
        }
        _players = players;
        _nextPageToken = page.nextPageToken;
        if (page.nextPageToken != null) {
          _seenPageTokens.add(page.nextPageToken!);
        }
        _unavailableUids.addAll(page.unavailableUids);
      });
    } catch (_) {
      if (_ownsAccount && serial == _serial) setState(() => _failed = true);
    } finally {
      if (_ownsAccount && serial == _serial) {
        setState(() {
          _loading = false;
          _loadInFlight = false;
        });
      }
    }
  }

  Future<void> _unblock(BlockedPlayer player) async {
    if (!_canAct ||
        _busyUid != null ||
        _loading ||
        _loadInFlight ||
        !_players.any((entry) => entry.uid == player.uid)) {
      return;
    }
    final serial = _serial;
    final english = LunoLocalizations.of(context).isEnglish;
    setState(() => _busyUid = player.uid);
    try {
      final confirmed = await showLunoAccountDialog<bool>(
        context: context,
        service: widget.online,
        builder:
            (dialogContext) => AlertDialog(
              title: Text(english ? 'Unblock player?' : 'Engeli kaldır?'),
              content: Text(
                english
                    ? 'Your friendship will not be restored automatically.'
                    : 'Arkadaşlığınız otomatik olarak geri yüklenmeyecek.',
              ),
              actions: [
                TextButton(
                  onPressed:
                      () => dismissLunoAccountModal(dialogContext, false),
                  child: Text(english ? 'Cancel' : 'Vazgeç'),
                ),
                FilledButton(
                  onPressed: () => dismissLunoAccountModal(dialogContext, true),
                  child: Text(english ? 'Unblock' : 'Engeli kaldır'),
                ),
              ],
            ),
      );
      if (!_canAct || serial != _serial || confirmed != true) return;
      await widget.online.unblockPlayer(player.uid);
      if (!_ownsAccount || serial != _serial) return;
      setState(
        () =>
            _players =
                _players.where((entry) => entry.uid != player.uid).toList(),
      );
    } catch (_) {
      if (mounted && _canAct && serial == _serial) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              english
                  ? 'Could not unblock the player. Please try again.'
                  : 'Engel kaldırılamadı. Lütfen tekrar dene.',
            ),
          ),
        );
      }
    } finally {
      if (_ownsAccount && serial == _serial) setState(() => _busyUid = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final english = LunoLocalizations.of(context).isEnglish;
    return Scaffold(
      appBar: AppBar(
        title: Text(english ? 'BLOCKED PLAYERS' : 'ENGELLENENLER'),
      ),
      body: LunoBackdrop(
        art: LunoAssets.inboxSceneV27,
        child: SafeArea(
          child:
              _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _players.isEmpty
                  ? Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.shield_outlined, size: 48),
                          const SizedBox(height: 16),
                          Text(
                            _failed
                                ? (english
                                    ? 'Blocked players could not be loaded.'
                                    : 'Engellenen oyuncular yüklenemedi.')
                                : _nextPageToken != null
                                ? (english
                                    ? 'There are more blocked entries.'
                                    : 'Engellenenler listesi devam ediyor.')
                                : (english
                                    ? 'You have no blocked players.'
                                    : 'Engellediğin oyuncu yok.'),
                            textAlign: TextAlign.center,
                          ),
                          if (_failed || _nextPageToken != null) ...[
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              key: const Key('blocked-list-load-more'),
                              onPressed:
                                  _loadInFlight
                                      ? null
                                      : () => _load(more: _nextPageToken != null),
                              icon: const Icon(Icons.refresh_rounded),
                              label: Text(
                                _failed
                                    ? (english ? 'Try again' : 'Tekrar dene')
                                    : (english ? 'Load more' : 'Daha fazla'),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  )
                  : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _players.length + (_nextPageToken != null ? 1 : 0),
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      if (index == _players.length) {
                        return Column(
                          children: [
                            if (_failed)
                              Text(
                                english
                                    ? 'More players could not be loaded.'
                                    : 'Diğer oyuncular yüklenemedi.',
                                textAlign: TextAlign.center,
                              ),
                            FilledButton.icon(
                              key: const Key('blocked-list-load-more'),
                              onPressed:
                                  _loadInFlight || _busyUid != null
                                      ? null
                                      : () => _load(more: true),
                              icon:
                                  _loadInFlight
                                      ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                      : const Icon(Icons.expand_more_rounded),
                              label: Text(
                                _failed
                                    ? (english ? 'Try again' : 'Tekrar dene')
                                    : (english ? 'Load more' : 'Daha fazla'),
                              ),
                            ),
                          ],
                        );
                      }
                      final player = _players[index];
                      return LunoSurface(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              _unavailableUids.contains(player.uid)
                                  ? (english
                                      ? 'Unavailable player'
                                      : 'Ulaşılamayan oyuncu')
                                  : player.name,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: OutlinedButton.icon(
                                onPressed:
                                    _busyUid == null && !_loadInFlight
                                        ? () => _unblock(player)
                                        : null,
                                icon:
                                    _busyUid == player.uid
                                        ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                        : const Icon(Icons.lock_open_rounded),
                                label: Text(
                                  english ? 'Unblock' : 'Engeli kaldır',
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
        ),
      ),
    );
  }
}
