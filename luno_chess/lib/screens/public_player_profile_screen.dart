import 'dart:async';
import 'package:flutter/material.dart';

import '../i18n/luno_localizations.dart';
import '../navigation/luno_account_scope.dart';
import '../services/luno_online_service.dart';
import '../theme/luno_assets.dart';
import '../widgets/luno_surface.dart';
import '../widgets/social_safety_actions.dart';
import 'parity_extra_screens.dart';

class PublicPlayerProfileScreen extends StatefulWidget
    implements LunoAccountScopedPage {
  const PublicPlayerProfileScreen({
    super.key,
    required this.targetUid,
    this.online,
  });
  final String targetUid;
  final LunoOnlineService? online;

  @override
  State<PublicPlayerProfileScreen> createState() =>
      _PublicPlayerProfileScreenState();
}

class _PublicPlayerProfileScreenState extends State<PublicPlayerProfileScreen> {
  Map<String, dynamic>? _profile;
  bool _loading = false;
  bool _failed = false;
  bool _missing = false;
  int _serial = 0;
  late String? _entryUid;
  late int _entryRevision;
  LunoOnlineService get _online => widget.online ?? LunoOnlineService.instance;
  bool get _ownsSession =>
      mounted &&
      _entryUid == _online.user?.uid &&
      _entryRevision == _online.accountRevision &&
      _online.accountFailure == null;

  void _captureSession() {
    _entryUid = _online.user?.uid;
    _entryRevision = _online.accountRevision;
  }

  @override
  void initState() {
    super.initState();
    _captureSession();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_load());
    });
  }

  @override
  void didUpdateWidget(covariant PublicPlayerProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.targetUid == widget.targetUid &&
        oldWidget.online == widget.online) {
      return;
    }
    ++_serial;
    _profile = null;
    _loading = false;
    _failed = false;
    _missing = false;
    _captureSession();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_load());
    });
  }

  Future<void> _load() async {
    if (!_ownsSession ||
        _loading ||
        ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    final serial = ++_serial;
    final target = widget.targetUid;
    setState(() {
      _loading = true;
      _failed = false;
      _missing = false;
      _profile = null;
    });
    bool current() =>
        _ownsSession && serial == _serial && target == widget.targetUid;
    try {
      final profile = await _online.publicPlayerProfile(target);
      if (!current()) return;
      setState(() {
        _profile = profile;
        _missing = profile == null;
      });
    } catch (_) {
      if (current()) setState(() => _failed = true);
    } finally {
      if (current()) setState(() => _loading = false);
    }
  }

  void _onBlocked(String targetUid) {
    if (!_ownsSession || targetUid != widget.targetUid) return;
    ++_serial;
    setState(() {
      _profile = null;
      _loading = false;
      _failed = false;
      _missing = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_profile != null) {
      return PlayerDetailsScreen.fromPlayer(
        _profile!,
        onRefresh: _load,
        safetyAction: SocialSafetyActions(
          online: _online,
          targetUid: widget.targetUid,
          onBlocked: _onBlocked,
        ),
      );
    }
    final english = LunoLocalizations.of(context).isEnglish;
    return Scaffold(
      appBar: AppBar(
        title: Text(english ? 'PLAYER PROFILE' : 'OYUNCU PROFİLİ'),
      ),
      body: LunoBackdrop(
        art: LunoAssets.profileSceneV29,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_loading)
                    const CircularProgressIndicator()
                  else ...[
                    Text(
                      _missing
                          ? (english
                              ? 'This player profile is no longer available.'
                              : 'Bu oyuncunun profili artık mevcut değil.')
                          : _failed
                          ? (english
                              ? 'The player profile could not be loaded.'
                              : 'Oyuncu profili yüklenemedi.')
                          : (english
                              ? 'Preparing player profile.'
                              : 'Oyuncu profili hazırlanıyor.'),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text(english ? 'TRY AGAIN' : 'TEKRAR DENE'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
