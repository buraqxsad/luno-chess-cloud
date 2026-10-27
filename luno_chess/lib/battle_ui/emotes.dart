import 'package:flutter/material.dart';
import '../battle_v1/emotes.dart';
import '../theme/luno_assets.dart';
import '../widgets/cosmetic_emote_art.dart';
import '../i18n/battle_learning_copy.dart';
import '../i18n/luno_localizations.dart';
import 'tokens.dart';

String battleEmoteName(LunoLocalizations l, String id) {
  final names = switch (id) {
    'smile' => ('Gülümse', 'Smile'), 'heart' => ('Kalp', 'Heart'),
    'laugh' => ('Kahkaha', 'Laugh'), 'cry' => ('Üzgün', 'Cry'),
    'angry' => ('Kızgın', 'Angry'), 'think' => ('Düşün', 'Think'),
    'fire' => ('Ateş', 'Fire'), 'star' => ('Yıldız', 'Star'),
    'thunder' => ('Şimşek', 'Thunder'), 'bomb' => ('Bomba', 'Bomb'),
    'strat' => ('Strateji', 'Strategy'), 'trophy' => ('Kupa', 'Trophy'),
    'crown' => ('Taç', 'Crown'), 'rainbow' => ('Gökkuşağı', 'Rainbow'),
    _ => ('İfade', 'Emote'),
  };
  return l.learning(names.$1, names.$2);
}

enum BattleEmoteMotion { bounce, nod, shake, rise }
BattleEmoteMotion battleEmoteMotion(String id) => switch (id) {
  'angry' || 'fire' || 'thunder' || 'bomb' => BattleEmoteMotion.shake,
  'laugh' || 'cry' => BattleEmoteMotion.nod,
  'think' || 'strat' || 'trophy' || 'crown' || 'star' => BattleEmoteMotion.rise,
  _ => BattleEmoteMotion.bounce,
};

class BattleEmoteBubble extends StatelessWidget {
  final BattleEmoteEvent? event;
  final String? sender;
  final bool compact;
  const BattleEmoteBubble({super.key, this.event, this.sender, this.compact = false});
  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration:
        MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 260),
    child:
        event == null
            ? const SizedBox.shrink()
            : Semantics(
              label: '${sender ?? ''} ${battleEmoteName(LunoLocalizations.of(context), event!.emojiId)}',
              liveRegion: true,
              child: SizedBox(
                key: ValueKey('${event!.side}-${event!.sequence}'),
                width: compact ? 54 : 70,
                height: compact ? 48 : 64,
                child: Column(
                    children: [
                      Expanded(
                        child: LayoutBuilder(builder: (context, box) => Center(
                          child: CosmeticEmoteArt(
                            key: ValueKey('battle-emote-${event!.side}-${event!.sequence}'),
                            id: event!.emojiId,
                            size: box.maxWidth < box.maxHeight ? box.maxWidth : box.maxHeight,
                          ),
                        )),
                      ),
                      if (sender != null)
                        Text(
                          sender!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: BattleTokens.caption.copyWith(fontSize: 10),
                        ),
                    ],
                ),
              ),
            ),
  );
}

class BattleEmotePicker extends StatelessWidget {
  final BattleEmoteChannel channel;
  final List<String> ids;
  final ValueChanged<String> onSend;
  const BattleEmotePicker({
    super.key,
    required this.channel,
    required this.ids,
    required this.onSend,
  });
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: channel,
    builder: (context, _) {
      final l = LunoLocalizations.of(context);
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final id in ids)
                SizedBox.square(
                  dimension: 72,
                  child: IconButton(
                    key: ValueKey('send-emote-$id'),
                    tooltip: '${l.learning('Gönder', 'Send')}: ${battleEmoteName(l, id)}',
                    onPressed: channel.canSend ? () => onSend(id) : null,
                    icon: Opacity(
                      opacity: channel.canSend ? 1 : .45,
                      child: Image.asset(LunoAssets.emoji(id), cacheWidth: 192),
                    ),
                  ),
                ),
            ],
          ),
          if (ids.isEmpty)
            Text(
              l.learning('Henüz açılmış ifade yok.', 'No unlocked emotes yet.'),
              style: BattleTokens.body,
            ),
          if (!channel.canSend)
            Text(
              l.learning(
                'Tekrar göndermeden önce 3 saniye bekle.',
                'Wait 3 seconds between emotes.',
              ),
              style: BattleTokens.caption,
            ),
          if (channel.failed)
            Text(
              l.learning(
                'İfade gönderilemedi. Maçın devam ediyor.',
                'Emote could not be sent. Your match continues.',
              ),
              style: BattleTokens.caption,
            ),
          SwitchListTile(
            title: Text(
              l.learning('İfadeleri sessize al', 'Mute emotes'),
              style: BattleTokens.body,
            ),
            value: channel.muted,
            onChanged: channel.setMuted,
          ),
        ],
      );
    },
  );
}
