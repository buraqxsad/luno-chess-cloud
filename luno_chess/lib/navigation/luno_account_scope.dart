import 'package:flutter/material.dart';

import '../i18n/luno_localizations.dart';
import '../services/luno_online_service.dart';

/// Pages containing private account-owned state opt into route-level reset.
abstract interface class LunoAccountScopedPage {}

class LunoAccountScope extends StatefulWidget {
  const LunoAccountScope({super.key, required this.page, this.service});

  final Widget page;
  final LunoOnlineService? service;

  @override
  State<LunoAccountScope> createState() => _LunoAccountScopeState();
}

class _LunoAccountScopeState extends State<LunoAccountScope> {
  int? _renderedRevision;

  @override
  Widget build(BuildContext context) {
    final online = widget.service ?? LunoOnlineService.instance;
    return AnimatedBuilder(
      animation: online,
      builder: (context, _) {
        final revision = online.accountRevision;
        final current = ModalRoute.of(context)?.isCurrent != false;
        if (_renderedRevision != revision && !current) {
          return const SizedBox.shrink();
        }
        if (revision > 0 && online.user == null) {
          final english = LunoLocalizations.of(context).isEnglish;
          return Scaffold(
            appBar: AppBar(),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  english
                      ? 'Your session has ended. Reopen this screen after signing in.'
                      : 'Oturumun kapandı. Giriş yaptıktan sonra bu ekranı yeniden aç.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }
        if (online.authTransitioning) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        _renderedRevision = revision;
        return KeyedSubtree(key: ValueKey(revision), child: widget.page);
      },
    );
  }
}
