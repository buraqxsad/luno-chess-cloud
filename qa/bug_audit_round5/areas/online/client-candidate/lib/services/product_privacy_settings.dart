import 'package:flutter/material.dart';

import '../i18n/luno_localizations.dart';
import '../models/game_store.dart';
import '../navigation/luno_account_modal.dart';
import 'account_operation_guard.dart';
import 'legal_link_service.dart';
import 'luno_online_service.dart';
import 'product_telemetry.dart';
import 'ugc_consent.dart';

Future<bool> showProductPrivacySettings({
  required BuildContext context,
  required GameStore store,
  required LunoOnlineService online,
}) async {
  if (!context.mounted || ModalRoute.of(context)?.isCurrent == false) {
    return false;
  }
  final owner = AccountOperationGuard(store, online);
  final route = ModalRoute.of(context);
  await ProductTelemetry.instance.bind(store: store, online: online);
  if (!context.mounted || !owner.isCurrent || route?.isCurrent == false) {
    return false;
  }
  return await showLunoAccountDialog<bool>(
        context: context,
        service: online,
        playerStore: store,
        builder:
            (_) => ProductPrivacyDialog(telemetry: ProductTelemetry.instance),
      ) ==
      true;
}

class ProductPrivacyDialog extends StatefulWidget {
  const ProductPrivacyDialog({super.key, required this.telemetry});
  final ProductTelemetry telemetry;
  @override
  State<ProductPrivacyDialog> createState() => _ProductPrivacyDialogState();
}

class _ProductPrivacyDialogState extends State<ProductPrivacyDialog> {
  late bool analytics = widget.telemetry.consent.analytics;
  late bool diagnostics = widget.telemetry.consent.diagnostics;
  bool error = false;

  Future<void> _save() async {
    if (!mounted ||
        ModalRoute.of(context)?.isCurrent != true ||
        widget.telemetry.saving) {
      return;
    }
    final saved = await widget.telemetry.setConsent(
      analytics: analytics,
      diagnostics: diagnostics,
    );
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
    if (saved) {
      dismissLunoAccountModal(context, true);
    } else {
      setState(() => error = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final en = LunoLocalizations.of(context).isEnglish;
    return ListenableBuilder(
      listenable: widget.telemetry,
      builder: (context, _) {
        final busy = widget.telemetry.saving;
        return AlertDialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          title: Text(
            en ? 'Optional measurements' : 'İsteğe bağlı ölçümler',
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
                    en
                        ? 'Play without sharing. These choices never affect rewards or matchmaking. You can change them here at any time.'
                        : 'Paylaşmadan oynayabilirsin. Bu seçimler ödülleri veya eşleşmeyi etkilemez. İstediğin zaman buradan değiştirebilirsin.',
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: analytics,
                    key: const Key('product-analytics-consent'),
                    onChanged:
                        busy
                            ? null
                            : (value) => setState(() => analytics = value),
                    title: Text(
                      en ? 'Game improvement' : 'Oyunu geliştirme',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: Text(
                      en
                          ? 'Share counts such as tutorial steps and matches. No usernames, messages, board positions or card identities.'
                          : 'Eğitim adımları ve maçlar gibi olay sayılarını paylaş. Kullanıcı adı, mesaj, tahta konumu veya kart kimliği gönderilmez.',
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: diagnostics,
                    key: const Key('product-diagnostics-consent'),
                    onChanged:
                        busy
                            ? null
                            : (value) => setState(() => diagnostics = value),
                    title: Text(
                      en ? 'Error diagnostics' : 'Hata tanılama',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: Text(
                      en
                          ? 'Share coarse error categories, not error text or raw logs. Records expire after 30 days.'
                          : 'Hata metni veya ham günlük yerine yalnızca genel hata sınıflarını paylaş. Kayıtlar 30 gün sonra temizlenir.',
                    ),
                  ),
                  TextButton.icon(
                    onPressed:
                        busy
                            ? null
                            : () async {
                              if (!context.mounted ||
                                  ModalRoute.of(context)?.isCurrent != true) {
                                return;
                              }
                              final opened = await LegalLinkService.instance
                                  .open(ugcPrivacyUrl);
                              if (!context.mounted ||
                                  ModalRoute.of(context)?.isCurrent != true ||
                                  opened) {
                                return;
                              }
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    en
                                        ? 'Could not open the privacy policy.'
                                        : 'Gizlilik politikası açılamadı.',
                                  ),
                                ),
                              );
                            },
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: Text(en ? 'Privacy Policy' : 'Gizlilik Politikası'),
                  ),
                  if (error || !widget.telemetry.confirmed)
                    Text(
                      en
                          ? 'Your choice could not be confirmed. Try again when connected.'
                          : 'Seçimin doğrulanamadı. Bağlanınca tekrar dene.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  if (error || !widget.telemetry.confirmed)
                    TextButton.icon(
                      key: const Key('product-consent-retry'),
                      onPressed:
                          busy || widget.telemetry.loadingConsent
                              ? null
                              : () async {
                                if (!mounted ||
                                    !context.mounted ||
                                    ModalRoute.of(context)?.isCurrent != true) {
                                  return;
                                }
                                await widget.telemetry.retryConsent();
                                if (!mounted ||
                                    !context.mounted ||
                                    ModalRoute.of(context)?.isCurrent != true) {
                                  return;
                                }
                                setState(() {
                                  error = !widget.telemetry.confirmed;
                                  analytics =
                                      widget.telemetry.consent.analytics;
                                  diagnostics =
                                      widget.telemetry.consent.diagnostics;
                                });
                              },
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text(en ? 'Try again' : 'Tekrar dene'),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed:
                  busy ? null : () => dismissLunoAccountModal(context, false),
              child: Text(en ? 'Not now' : 'Şimdi değil'),
            ),
            FilledButton(
              onPressed: busy || !widget.telemetry.confirmed ? null : _save,
              child:
                  busy
                      ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : Text(en ? 'Save choice' : 'Seçimi kaydet'),
            ),
          ],
        );
      },
    );
  }
}
