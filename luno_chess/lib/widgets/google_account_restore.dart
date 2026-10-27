import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../i18n/luno_localizations.dart';
import '../navigation/luno_account_modal.dart';
import '../services/luno_online_service.dart';

Future<void> showGoogleAccountRestore({
  required BuildContext context,
  required LunoOnlineService online,
  required bool english,
  ValueChanged<bool>? onBusyChanged,
}) async {
  final owner = (online.user?.uid, online.accountRevision);
  bool current() =>
      context.mounted &&
      ModalRoute.of(context)?.isCurrent == true &&
      owner == (online.user?.uid, online.accountRevision);
  if (!current() || online.accountSignInInProgress) return;
  onBusyChanged?.call(true);
  try {
    final confirmed = await showLunoAccountDialog<bool>(
      context: context,
      service: online,
      builder:
          (dialogContext) => AlertDialog(
            scrollable: true,
            title: Text(
              english
                  ? 'Open your Google-linked account'
                  : 'Google hesabındaki LUNO profilini aç',
            ),
            content: Text(
              english
                  ? 'Your selected Google account\'s server progress will load. This device\'s guest progress will stay separate. Purchases are not transferred between accounts.'
                  : 'Seçtiğin Google hesabının sunucudaki ilerlemesi açılır. Bu cihazdaki misafir ilerlemesi ayrı kalır. Satın almalar hesaplar arasında taşınmaz.',
            ),
            actions: [
              TextButton(
                onPressed: () => dismissLunoAccountModal(dialogContext, false),
                child: Text(
                  english ? 'Stay on this account' : 'Bu hesapta kal',
                ),
              ),
              TextButton(
                key: const ValueKey('google-account-restore-confirm'),
                onPressed: () => dismissLunoAccountModal(dialogContext, true),
                child: Text(
                  english ? 'Choose Google account' : 'Google hesabını seç',
                ),
              ),
            ],
          ),
    );
    if (confirmed != true || !context.mounted || !current()) return;
    await online.signInGoogle(confirmed: true);
    if (context.mounted && current()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            english ? 'Your account is restored.' : 'Hesabın geri yüklendi.',
          ),
        ),
      );
    }
  } catch (error) {
    if (!context.mounted || !current()) return;
    final canceled =
        error is FirebaseAuthException &&
        const {
          'cancelled',
          'web-context-canceled',
          'popup-closed-by-user',
        }.contains(error.code);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          canceled
              ? (english
                  ? 'Account selection canceled. Your current account is unchanged.'
                  : 'Hesap seçimi iptal edildi. Mevcut hesabın değişmedi.')
              : (english
                  ? 'Your account could not be restored. Check your connection and try again.'
                  : 'Hesabın geri yüklenemedi. Bağlantını kontrol edip tekrar dene.'),
        ),
      ),
    );
  } finally {
    if (context.mounted) onBusyChanged?.call(false);
  }
}

class GoogleAccountRestoreButton extends StatefulWidget {
  const GoogleAccountRestoreButton({
    super.key,
    required this.online,
    this.disabled = false,
    this.english,
    this.onBusyChanged,
  });
  final LunoOnlineService online;
  final bool disabled;
  final bool? english;
  final ValueChanged<bool>? onBusyChanged;

  @override
  State<GoogleAccountRestoreButton> createState() =>
      _GoogleAccountRestoreButtonState();
}

class _GoogleAccountRestoreButtonState
    extends State<GoogleAccountRestoreButton> {
  bool _busy = false;
  @override
  Widget build(BuildContext context) {
    final english = widget.english ?? LunoLocalizations.of(context).isEnglish;
    return ListenableBuilder(
      listenable: widget.online,
      builder:
          (context, _) => TextButton.icon(
            key: const ValueKey('google-account-restore'),
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed:
                _busy || widget.disabled
                    ? null
                    : () => showGoogleAccountRestore(
                      context: context,
                      online: widget.online,
                      english: english,
                      onBusyChanged: (value) {
                        if (!mounted) return;
                        setState(() => _busy = value);
                        widget.onBusyChanged?.call(value);
                      },
                    ),
            icon:
                _busy && widget.online.accountSignInInProgress
                    ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : const Icon(Icons.login_rounded),
            label: Text(
              english
                  ? 'Sign in to my existing account'
                  : 'Mevcut hesabıma giriş yap',
              textAlign: TextAlign.center,
            ),
          ),
    );
  }
}
