import 'package:flutter/material.dart';

/// Presentation metadata only; ownership and prices remain server-authoritative.
enum CosmeticRarity {
  common, rare, legendary, mythic;

  Color get color => switch (this) {
    common => const Color(0xFF8ED5C5),
    rare => const Color(0xFF83C9EF),
    legendary => const Color(0xFFFFBE78),
    mythic => const Color(0xFFF1A7CD),
  };
  String title(bool en) => switch (this) {
    common => en ? 'Common' : 'Sıradan',
    rare => en ? 'Rare' : 'Nadir',
    legendary => en ? 'Legendary' : 'Efsanevi',
    mythic => en ? 'Mythic' : 'Mitik',
  };
}

class CosmeticEmote {
  const CosmeticEmote(this.id, this.tr, this.en, this.rarity,
      {this.passLevel, this.premium = false});
  final String id, tr, en;
  final CosmeticRarity rarity;
  final int? passLevel;
  final bool premium;
  int get piecesRequired => switch (rarity) {
    CosmeticRarity.common => 20,
    CosmeticRarity.rare => 10,
    _ => 5,
  };
  int get goldPrice => switch (rarity) {
    CosmeticRarity.common => 500,
    CosmeticRarity.rare => 1500,
    CosmeticRarity.legendary => 4000,
    CosmeticRarity.mythic => 10000,
  };
  String title(bool english) => english ? en : tr;
  String source(bool english) {
    if (id == 'smile') {
      return english ? 'Included with your account.' : 'Hesabınla birlikte verilir.';
    }
    final chest = english
        ? 'Shop: $goldPrice gold, or collect $piecesRequired chest pieces.'
        : 'Mağaza: $goldPrice altın veya sandıklardan $piecesRequired parça.';
    if (passLevel == null) {
      return chest;
    }
    return '$chest ${english ? 'Or Luno Pass' : 'Veya Luno Pass'} · '
        '${premium ? 'Premium' : (english ? 'Free' : 'Ücretsiz')} '
        '$passLevel.';
  }
}

const cosmeticEmotes = <CosmeticEmote>[
  CosmeticEmote('smile', 'Neşeli Luno', 'Happy Luno', CosmeticRarity.common),
  CosmeticEmote('heart', 'Kalpli Luno', 'Loving Luno', CosmeticRarity.common, passLevel: 24),
  CosmeticEmote('laugh', 'Gülen Luno', 'Laughing Luno', CosmeticRarity.common, passLevel: 4),
  CosmeticEmote('cry', 'Ağlayan Luno', 'Crying Luno', CosmeticRarity.common),
  CosmeticEmote('angry', 'Kızgın Luno', 'Angry Luno', CosmeticRarity.common, passLevel: 10, premium: true),
  CosmeticEmote('think', 'Düşünen Luno', 'Thinking Luno', CosmeticRarity.common),
  CosmeticEmote('fire', 'Alevli Luno', 'Fiery Luno', CosmeticRarity.rare),
  CosmeticEmote('star', 'Yıldız Luno', 'Star Luno', CosmeticRarity.rare),
  CosmeticEmote('thunder', 'Şimşek Luno', 'Thunder Luno', CosmeticRarity.rare),
  CosmeticEmote('bomb', 'Oops Luno', 'Oops Luno', CosmeticRarity.rare),
  CosmeticEmote('strat', 'Stratejist Luno', 'Strategist Luno', CosmeticRarity.rare),
  CosmeticEmote('trophy', 'Kupa Luno', 'Trophy Luno', CosmeticRarity.legendary, passLevel: 12),
  CosmeticEmote('crown', 'Taçlı Luno', 'Crowned Luno', CosmeticRarity.legendary),
  CosmeticEmote('rainbow', 'Gökkuşağı Luno', 'Rainbow Luno', CosmeticRarity.mythic),
];

CosmeticEmote? cosmeticEmote(String id) {
  for (final item in cosmeticEmotes) {
    if (item.id == id) {
      return item;
    }
  }
  return null;
}

String costumeSource(String id, bool en) {
  if (id == 'luno') {
    return en ? 'Included · complete set' : 'Başlangıç · tam set';
  }
  final pass = switch (id) {
    'ottoman' => en ? 'Free Pass 20' : 'Ücretsiz Pass 20',
    'viking' => en ? 'Free Pass 30' : 'Ücretsiz Pass 30',
    'roma' => 'Premium Pass 15',
    'dragon' => 'Premium Pass 25',
    'neon' => 'Premium Pass 30',
    _ => null,
  };
  final shop = en ? 'Shop · complete set' : 'Mağaza · tam set';
  return pass == null ? shop : '$shop / $pass';
}
