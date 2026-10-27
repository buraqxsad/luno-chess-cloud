import 'package:flutter/material.dart' hide Text;

import '../battle_v1/model.dart';
import '../data/rank_catalog.dart';
import '../i18n/luno_text.dart';
import '../i18n/luno_localizations.dart';
import '../models/game_store.dart';
import '../services/ugc_text_safety.dart';
import '../models/profile_match_stats.dart';
import '../theme/luno_assets.dart';
import '../theme/luno_theme.dart';
import '../navigation/luno_route.dart';
import '../navigation/luno_account_scope.dart';
import 'legacy_parity_screens.dart';
import 'native_hubs_screen.dart';
import 'parity_extra_screens.dart';
import '../widgets/luno_surface.dart';

/// Profil: para, kupa, koleksiyon, istatistikler.
class ProfileScreen extends StatelessWidget implements LunoAccountScopedPage {
  const ProfileScreen({super.key});

  void _open(BuildContext context, Widget page) {
    if (!context.mounted || ModalRoute.of(context)?.isCurrent != true) return;
    Navigator.of(context).push(lunoRoute(page));
  }

  @override
  Widget build(BuildContext context) {
    final store = GameStore.instance;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final d = store.data;
        int nonNegative(int value) => value < 0 ? 0 : value;

        final stats = ProfileMatchStats(
          wins: d.wins,
          losses: d.losses,
          draws: d.draws,
          games: d.gamesPlayed,
        );
        final wins = stats.wins;
        final losses = stats.losses;
        final games = stats.games;
        final draws = stats.draws;
        final winRate = stats.winRate;
        final arenaIndex = arenaIndexForPlayer(
          store.rankTrophies,
          store.rankArenaIdx,
        );
        final arena = arenaForIndex(arenaIndex);
        return Scaffold(
          appBar: AppBar(
            backgroundColor: LunoColors.bgPanel,
            title: const Text('PROFİL'),
            actions: [
              IconButton(
                tooltip: LunoLocalizations.of(
                  context,
                ).translate('Profili düzenle'),
                onPressed: () => _open(context, const EditProfileScreen()),
                icon: const Icon(Icons.edit_rounded),
              ),
              IconButton(
                tooltip: LunoLocalizations.of(context).translate('Ayarlar'),
                onPressed: () => _open(context, const SettingsScreen()),
                icon: const Icon(Icons.settings_rounded),
              ),
            ],
          ),
          body: LunoBackdrop(
            art: LunoAssets.profileSceneV29,
            overlay: const Color(0x631C101A),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  children: [
                    Container(
                      width: 86,
                      height: 86,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [LunoColors.bgRaised, LunoColors.bgPanel],
                        ),
                      ),
                      alignment: Alignment.center,
                      child: LunoArt(
                        LunoAssets.avatar(d.avatarEmoji),
                        width: 78,
                        height: 78,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          InkWell(
                            onTap:
                                () =>
                                    _open(context, const LevelRewardsScreen()),
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 3,
                                vertical: 2,
                              ),
                              child: Text(
                                d.username,
                                localize: false,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          Text(
                            arena.displayName,
                            style: const TextStyle(
                              color: LunoColors.textDim,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            arenaProgressLabel(store.rankTrophies, arenaIndex),
                            style: const TextStyle(
                              color: LunoColors.gold,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Padding(
                            padding: EdgeInsets.zero,
                            child: Wrap(
                              spacing: 7,
                              runSpacing: 5,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF183A48),
                                    borderRadius: BorderRadius.circular(5),
                                    border: Border.all(
                                      color: const Color(0x6685DCD0),
                                    ),
                                  ),
                                  child: Text(
                                    d.country.toUpperCase(),
                                    style: const TextStyle(
                                      color: Color(0xFF9DE8DD),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                                Text(
                                  LunoAssets.countryName(d.country),
                                  style: const TextStyle(
                                    color: LunoColors.textDim,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  '${LunoLocalizations.of(context).isEnglish ? 'Pass Lv' : 'Pass Sv'} ${d.passLevel()}',
                                  style: const TextStyle(
                                    color: LunoColors.gold,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (safePublicBio(d.bio).isNotEmpty) ...[
                  LunoSurface(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
                    color: LunoColors.bgPanel2,
                    borderRadius: BorderRadius.circular(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'HAKKINDA',
                          style: TextStyle(
                            color: LunoColors.gold,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          safePublicBio(d.bio),
                          localize: false,
                          maxLines: 5,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: LunoColors.textDim,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                ],
                Row(
                  children: [
                    _miniStat(
                      LunoAssets.profileTrophy,
                      formatTrophies(store.rankTrophies),
                      'KUPA',
                    ),
                    _miniStat(
                      LunoAssets.profileWins,
                      wins.toString(),
                      'GALİBİYET',
                    ),
                    _miniStat(LunoAssets.profileRate, '$winRate%', 'ORAN'),
                    _miniStat(
                      LunoAssets.profileStreak,
                      nonNegative(d.streak).toString(),
                      'SERİ',
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    _bigStat(
                      const LunoArt(LunoAssets.coin, width: 64, height: 64),
                      d.gold,
                      'Altın',
                    ),
                    _bigStat(
                      const LunoArt(LunoAssets.gem, width: 64, height: 64),
                      d.gems,
                      'Elmas',
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                ColoredBox(
                  color: LunoColors.bgPanel,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'İSTATİSTİKLER',
                          style: TextStyle(
                            color: LunoColors.gold,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _stat('Toplam maç', games.toString()),
                        _stat('Berabere', draws.toString()),
                        _stat('Mağlubiyet', losses.toString()),
                        if (stats.unclassified > 0)
                          _stat(
                            LunoLocalizations.of(context).isEnglish
                                ? 'Result unavailable'
                                : 'Sonucu bilinmeyen',
                            stats.unclassified.toString(),
                          ),
                        _stat(
                          'En iyi seri',
                          nonNegative(d.bestStreak).toString(),
                        ),
                        _stat(
                          'Oynanan kart',
                          nonNegative(d.cardsPlayed).toString(),
                        ),
                        _stat(
                          'Açılan sandık',
                          nonNegative(d.chestsOpened).toString(),
                        ),
                        _stat(
                          LunoLocalizations.of(context).isEnglish
                              ? 'Battle card types'
                              : 'Savaş kartı çeşitleri',
                          CardId.values.length.toString(),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                _profileAction(
                  context,
                  LunoAssets.profileHistory,
                  'MAÇ GEÇMİŞİ',
                  'Oynadığın maçların özetini görüntüle',
                ),
                const SizedBox(height: 9),
                _profileAction(
                  context,
                  LunoAssets.profileAchievements,
                  'BAŞARIMLAR',
                  'İlerlemeni, rozetlerini ve hedeflerini görüntüle',
                  onTap: () => _open(context, const AchievementsScreen()),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _bigStat(Widget icon, int value, String label) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: LunoColors.bgPanel2,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            SizedBox(height: 64, child: icon),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                formatTrophies(value),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                style: const TextStyle(color: LunoColors.textDim, fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: LunoColors.textDim),
            ),
          ),
          const SizedBox(width: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 140),
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _profileAction(
    BuildContext context,
    String art,
    String title,
    String subtitle, {
    VoidCallback? onTap,
  }) {
    return Material(
      color: LunoColors.bgPanel,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap ?? () => _open(context, const MatchHistoryScreen()),
        child: Padding(
          padding: const EdgeInsets.all(11),
          child: Row(
            children: [
              LunoArt(art, width: 44, height: 44),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: LunoColors.textDim,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: LunoColors.gold),
            ],
          ),
        ),
      ),
    );
  }

  Widget _miniStat(String art, String value, String label) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
        decoration: BoxDecoration(
          color: LunoColors.bgPanel2,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: LunoColors.bgPanel2),
        ),
        child: Column(
          children: [
            LunoArt(art, width: 38, height: 38),
            const SizedBox(height: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: const TextStyle(
                  color: LunoColors.gold,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                style: const TextStyle(
                  color: LunoColors.textDim,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
