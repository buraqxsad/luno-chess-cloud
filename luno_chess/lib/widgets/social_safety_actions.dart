import 'package:flutter/material.dart';

import '../i18n/luno_localizations.dart';
import '../navigation/luno_account_modal.dart';
import '../services/luno_online_service.dart';
import '../services/public_player_profile.dart';
import '../services/social_safety_result.dart';

enum _SafetyAction { block, report }

class SocialSafetyActions extends StatefulWidget {
  const SocialSafetyActions({
    super.key,
    required this.online,
    required this.targetUid,
    this.messageId,
    this.onBlocked,
  });

  final LunoOnlineService online;
  final String targetUid;
  final String? messageId;
  final ValueChanged<String>? onBlocked;

  @override
  State<SocialSafetyActions> createState() => _SocialSafetyActionsState();
}

class _SocialSafetyActionsState extends State<SocialSafetyActions> {
  late String? _owner;
  late int _accountRevision;
  int _targetRevision = 0;
  bool _active = false;
  bool _sending = false;
  bool _blocked = false;

  bool get _ownsAccount =>
      mounted &&
      widget.online.user?.uid == _owner &&
      widget.online.accountRevision == _accountRevision &&
      widget.online.accountFailure == null;
  bool get _canAct =>
      _ownsAccount && ModalRoute.of(context)?.isCurrent != false;

  void _capture() {
    _owner = widget.online.user?.uid;
    _accountRevision = widget.online.accountRevision;
  }

  @override
  void initState() {
    super.initState();
    _capture();
  }

  @override
  void didUpdateWidget(covariant SocialSafetyActions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.online != widget.online ||
        oldWidget.targetUid != widget.targetUid ||
        oldWidget.messageId != widget.messageId) {
      ++_targetRevision;
      _active = false;
      _sending = false;
      _blocked = false;
      _capture();
    }
  }

  Future<void> _act() async {
    if (!_canAct || _active || _blocked) return;
    final revision = _targetRevision;
    final target = widget.targetUid;
    final message = widget.messageId;
    final online = widget.online;
    final english = LunoLocalizations.of(context).isEnglish;
    bool owned() => _ownsAccount && revision == _targetRevision;
    bool current() => _canAct && owned();
    setState(() => _active = true);
    try {
      final action =
          message != null
              ? _SafetyAction.report
              : await showLunoAccountBottomSheet<_SafetyAction>(
                context: context,
                service: online,
                builder:
                    (sheetContext) => Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(
                          leading: const Icon(Icons.flag_outlined),
                          title: Text(
                            english ? 'Report player' : 'Oyuncuyu şikâyet et',
                          ),
                          onTap:
                              () => dismissLunoAccountModal(
                                sheetContext,
                                _SafetyAction.report,
                              ),
                        ),
                        ListTile(
                          leading: const Icon(Icons.block_rounded),
                          title: Text(
                            english ? 'Block player' : 'Oyuncuyu engelle',
                          ),
                          onTap:
                              () => dismissLunoAccountModal(
                                sheetContext,
                                _SafetyAction.block,
                              ),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
              );
      if (!mounted || !current() || action == null) return;
      if (action == _SafetyAction.block) {
        final confirmed = await showLunoAccountDialog<bool>(
          context: context,
          service: online,
          builder:
              (dialogContext) => AlertDialog(
                title: Text(english ? 'Block player?' : 'Oyuncuyu engelle?'),
                content: Text(
                  english
                      ? 'Messages, friend requests and match invitations between you will be blocked. Your friendship will be removed.'
                      : 'Aranızdaki mesajlar, arkadaşlık istekleri ve maç davetleri engellenecek. Arkadaşlığınız kaldırılacak.',
                ),
                actions: [
                  TextButton(
                    onPressed:
                        () => dismissLunoAccountModal(dialogContext, false),
                    child: Text(english ? 'Cancel' : 'Vazgeç'),
                  ),
                  FilledButton(
                    onPressed:
                        () => dismissLunoAccountModal(dialogContext, true),
                    child: Text(english ? 'Block' : 'Engelle'),
                  ),
                ],
              ),
        );
        if (!current() || confirmed != true) return;
        setState(() => _sending = true);
        await online.blockPlayer(target);
        if (!owned()) return;
        setState(() => _blocked = true);
        widget.onBlocked?.call(target);
        if (current()) {
          _notice(english ? 'Player blocked.' : 'Oyuncu engellendi.');
        }
      } else {
        final reason = await showLunoAccountDialog<SocialReportReason>(
          context: context,
          service: online,
          builder:
              (dialogContext) => _ReportReasonDialog(message: message != null),
        );
        if (!current() || reason == null) return;
        setState(() => _sending = true);
        if (message == null) {
          await online.reportPlayer(target, reason);
        } else {
          await online.reportDirectMessage(target, message, reason);
        }
        if (current()) {
          _notice(
            english
                ? 'Report submitted for review.'
                : 'Şikâyetin incelemeye gönderildi.',
          );
        }
      }
    } catch (error) {
      if (!current()) return;
      final limited = error is LunoApiException && error.status == 429;
      _notice(
        english
            ? (limited
                ? 'Too many requests. Please try again later.'
                : 'The action could not be completed. Please try again.')
            : (limited
                ? 'Çok fazla istek. Bir süre sonra tekrar dene.'
                : 'İşlem tamamlanamadı. Lütfen tekrar dene.'),
      );
    } finally {
      if (_ownsAccount && revision == _targetRevision) {
        setState(() {
          _active = false;
          _sending = false;
        });
      }
    }
  }

  void _notice(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    if (_owner == null ||
        widget.targetUid == _owner ||
        !isPublicPlayerUidValid(widget.targetUid) ||
        (widget.messageId != null &&
            !isPublicPlayerUidValid(widget.messageId!))) {
      return const SizedBox.shrink();
    }
    final english = LunoLocalizations.of(context).isEnglish;
    final targetRevision = _targetRevision;
    return IconButton(
      tooltip:
          widget.messageId != null
              ? (english ? 'Report message' : 'Mesajı şikâyet et')
              : (english ? 'Player safety' : 'Oyuncu güvenliği'),
      onPressed:
          _active || _blocked || !_ownsAccount
              ? null
              : () {
                if (targetRevision == _targetRevision) _act();
              },
      icon:
          _sending
              ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
              : Icon(
                widget.messageId != null
                    ? Icons.flag_outlined
                    : Icons.more_vert_rounded,
              ),
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
    );
  }
}

class _ReportReasonDialog extends StatefulWidget {
  const _ReportReasonDialog({required this.message});
  final bool message;
  @override
  State<_ReportReasonDialog> createState() => _ReportReasonDialogState();
}

class _ReportReasonDialogState extends State<_ReportReasonDialog> {
  SocialReportReason? _reason;
  @override
  Widget build(BuildContext context) {
    final english = LunoLocalizations.of(context).isEnglish;
    return AlertDialog(
      scrollable: true,
      title: Text(
        widget.message
            ? (english ? 'Report message' : 'Mesajı şikâyet et')
            : (english ? 'Report player' : 'Oyuncuyu şikâyet et'),
      ),
      content: SizedBox(
        width: 400,
        child: DropdownButtonFormField<SocialReportReason>(
          isExpanded: true,
          decoration: InputDecoration(labelText: english ? 'Reason' : 'Neden'),
          items: [
            for (final reason in SocialReportReason.values)
              DropdownMenuItem(
                value: reason,
                child: Text(reason.label(english)),
              ),
          ],
          onChanged: (value) => setState(() => _reason = value),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => dismissLunoAccountModal(context),
          child: Text(english ? 'Cancel' : 'Vazgeç'),
        ),
        FilledButton(
          onPressed:
              _reason == null
                  ? null
                  : () => dismissLunoAccountModal(context, _reason),
          child: Text(english ? 'Send report' : 'Şikâyeti gönder'),
        ),
      ],
    );
  }
}
