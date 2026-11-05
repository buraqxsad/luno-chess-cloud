import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../i18n/luno_localizations.dart';
import '../models/game_store.dart';
import '../navigation/luno_account_modal.dart';
import 'account_operation_guard.dart';
import 'luno_online_service.dart';
import 'legal_link_service.dart';
import 'legal_urls.dart';
import 'screen_request_timeouts.dart';

export 'legal_urls.dart';

const ugcTermsVersion = 'terms-2026-08-09';
const ugcPrivacyVersion = 'privacy-2026-08-09';
const ugcCommunityVersion = 'community-2026-08-13';

String ugcConsentStorageKey(String uid) =>
    'luno.ugc-consent.v1.${Uri.encodeComponent(uid)}';

Map<String, dynamic>? confirmedUgcConsent(Object? value, String uid) {
  if (value is! Map ||
      value['uid'] != uid ||
      value['accepted'] != true ||
      value['termsVersion'] != ugcTermsVersion ||
      value['privacyVersion'] != ugcPrivacyVersion ||
      value['communityVersion'] != ugcCommunityVersion ||
      value['acceptedAt'] is! int ||
      (value['acceptedAt'] as int) <= 0) {
    return null;
  }
  return {
    'uid': uid,
    'accepted': true,
    'acceptedAt': value['acceptedAt'],
    'termsVersion': ugcTermsVersion,
    'privacyVersion': ugcPrivacyVersion,
    'communityVersion': ugcCommunityVersion,
  };
}

Map<String, dynamic> validateUgcConsentResult(
  Map<String, dynamic> result,
  String uid,
) {
  final state = result['state'];
  final record = confirmedUgcConsent(result['legalConsent'], uid);
  final stateRecord =
      state is Map ? confirmedUgcConsent(state['legalConsent'], uid) : null;
  if (result['ok'] != true ||
      result['accepted'] != true ||
      state is! Map ||
      state['uid'] != uid ||
      record == null ||
      stateRecord == null ||
      record['acceptedAt'] != stateRecord['acceptedAt']) {
    throw const FormatException('Unconfirmed UGC consent');
  }
  return record;
}

/// Local records are a UI acknowledgement cache, never server authorization.
class UgcConsent {
  bool _pending = false;
  bool _disposed = false;
  final _timeouts = ScreenRequestTimeouts();

  void dispose() {
    _disposed = true;
    _timeouts.dispose();
  }

  Future<bool> ensure({
    required BuildContext context,
    required LunoOnlineService online,
    GameStore? playerStore,
    bool force = false,
    bool Function()? isRelevant,
  }) async {
    if (_disposed ||
        _pending ||
        !context.mounted ||
        ModalRoute.of(context)?.isCurrent == false) {
      return false;
    }
    final uid = online.user?.uid;
    if (uid == null || uid.isEmpty || online.accountFailure != null) {
      return false;
    }
    final owner = AccountOperationGuard(
      playerStore ?? GameStore.instance,
      online,
    );
    final route = ModalRoute.of(context);
    bool active() =>
        !_disposed &&
        context.mounted &&
        owner.isCurrent &&
        route?.isCurrent != false &&
        (isRelevant?.call() ?? true);
    _pending = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!active()) return false;
      final key = ugcConsentStorageKey(uid);
      if (force) {
        await prefs.remove(key);
        if (!active()) return false;
      }
      if (!force) {
        final raw = prefs.getString(key);
        try {
          if (raw != null &&
              confirmedUgcConsent(jsonDecode(raw), uid) != null) {
            return true;
          }
        } on FormatException {
          // A damaged acknowledgement is not consent.
        }
      }
      if (!context.mounted) return false;
      final accepted = await showLunoAccountDialog<bool>(
        context: context,
        service: online,
        playerStore: playerStore,
        builder: (_) => const UgcConsentDialog(),
      );
      if (accepted != true || !active()) return false;
      final result = await _timeouts.run(
        online.acceptLegalTerms(),
        const Duration(seconds: 12),
      );
      if (!active()) return false;
      final record = validateUgcConsentResult(result, uid);
      if (!await prefs.setString(key, jsonEncode(record))) {
        throw const FormatException('UGC acknowledgement was not saved');
      }
      return active();
    } catch (_) {
      if (!active()) return false;
      rethrow;
    } finally {
      _timeouts.cancelPending();
      _pending = false;
    }
  }

  /// Retry only after the server refuses an old/missing acknowledgement.
  /// The refused first request cannot create or publish user content.
  Future<T?> run<T>({
    required BuildContext context,
    required LunoOnlineService online,
    required Future<T> Function() operation,
    GameStore? playerStore,
    bool Function()? isRelevant,
  }) async {
    final owner = AccountOperationGuard(
      playerStore ?? GameStore.instance,
      online,
    );
    final route = ModalRoute.of(context);
    bool active() =>
        !_disposed &&
        context.mounted &&
        owner.isCurrent &&
        route?.isCurrent != false &&
        (isRelevant?.call() ?? true);
    if (!active()) return null;
    try {
      return await operation();
    } on LunoApiException catch (error) {
      if (error.code != 'legal-consent-required') rethrow;
      if (!active()) return null;
      if (!context.mounted) return null;
      if (!await ensure(
            context: context,
            online: online,
            playerStore: playerStore,
            force: true,
            isRelevant: isRelevant,
          ) ||
          !active()) {
        return null;
      }
      return await operation();
    }
  }
}

class UgcConsentDialog extends StatefulWidget {
  const UgcConsentDialog({super.key});

  @override
  State<UgcConsentDialog> createState() => _UgcConsentDialogState();
}

class _UgcConsentDialogState extends State<UgcConsentDialog> {
  bool accepted = false;

  @override
  Widget build(BuildContext context) {
    final english = LunoLocalizations.of(context).isEnglish;
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      title: Text(
        english ? 'Community rules' : 'Topluluk kuralları',
        style: const TextStyle(fontSize: 20, height: 1.2),
      ),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                english
                    ? 'Your username, bio and messages are visible to other players. No harassment, threats, hate, sexual content, spam, scams, impersonation or sharing another person\'s private information. You can report or block players from their profile or a conversation.'
                    : 'Kullanıcı adın, biyografin ve mesajların diğer oyunculara görünür. Taciz, tehdit, nefret söylemi, cinsel içerik, spam, dolandırıcılık, taklit ve başkasının özel bilgilerini paylaşmak yasaktır. Oyuncuları profilinden veya konuşmadan raporlayabilir ya da engelleyebilirsin.',
              ),
              const SizedBox(height: 12),
              Text(
                english
                    ? 'Terms and Community Guidelines (section 4)'
                    : 'Kullanım Koşulları ve Topluluk Kuralları (bölüm 4)',
              ),
              _PolicyAddress(url: ugcTermsUrl, english: english),
              Text(english ? 'Privacy Policy' : 'Gizlilik Politikası'),
              _PolicyAddress(url: ugcPrivacyUrl, english: english),
              CheckboxListTile(
                key: const Key('ugc-consent-checkbox'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: accepted,
                onChanged: (value) {
                  if (mounted && ModalRoute.of(context)?.isCurrent == true) {
                    setState(() => accepted = value == true);
                  }
                },
                title: Text(
                  english
                      ? 'I accept the Terms, Privacy Policy and Community Guidelines.'
                      : 'Kullanım Koşulları, Gizlilik Politikası ve Topluluk Kurallarını kabul ediyorum.',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          style: const ButtonStyle(
            minimumSize: WidgetStatePropertyAll(Size(48, 48)),
          ),
          key: const Key('ugc-consent-decline'),
          onPressed: () => dismissLunoAccountModal(context, false),
          child: Text(english ? 'NOT NOW' : 'ŞİMDİ DEĞİL'),
        ),
        FilledButton(
          style: const ButtonStyle(
            minimumSize: WidgetStatePropertyAll(Size(48, 48)),
          ),
          key: const Key('ugc-consent-accept'),
          onPressed:
              accepted ? () => dismissLunoAccountModal(context, true) : null,
          child: Text(english ? 'ACCEPT' : 'KABUL ET'),
        ),
      ],
    );
  }
}

class _PolicyAddress extends StatelessWidget {
  const _PolicyAddress({required this.url, required this.english});
  final String url;
  final bool english;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SelectableText(url, style: const TextStyle(fontSize: 12)),
      Row(
        children: [
          Tooltip(
            message:
                english ? 'Open policy in browser' : 'Politikayı tarayıcıda aç',
            child: TextButton.icon(
              icon: const Icon(Icons.open_in_new_rounded),
              label: Text(english ? 'OPEN' : 'AÇ'),
              onPressed: () async {
                if (!context.mounted ||
                    ModalRoute.of(context)?.isCurrent != true) {
                  return;
                }
                final opened = await LegalLinkService.instance.open(url);
                if (!context.mounted ||
                    ModalRoute.of(context)?.isCurrent != true ||
                    opened) {
                  return;
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      english
                          ? 'Could not open the policy. You can copy the link.'
                          : 'Politika açılamadı. Bağlantıyı kopyalayabilirsin.',
                    ),
                  ),
                );
              },
            ),
          ),
          IconButton(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            tooltip:
                english ? 'Copy policy link' : 'Politika bağlantısını kopyala',
            icon: const Icon(Icons.copy_rounded),
            onPressed: () async {
              if (!context.mounted ||
                  ModalRoute.of(context)?.isCurrent != true) {
                return;
              }
              await Clipboard.setData(ClipboardData(text: url));
            },
          ),
        ],
      ),
    ],
  );
}
