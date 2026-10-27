import 'package:flutter/material.dart';

/// Historic skin rights select a decorative rim, separately from full sets.
class BoardFinish {
  const BoardFinish(this.id, this.tr, this.en, this.target, this.color);
  final String id, tr, en;
  final int target;
  final Color color;
  String title(bool english) => english ? en : tr;
}

const boardFinishes = <BoardFinish>[
  BoardFinish('classic', 'Klasik', 'Classic', 20, Color(0xFFB4C3CB)),
  BoardFinish('obsidian', 'Obsidyen', 'Obsidian', 20, Color(0xFF92A2B1)),
  BoardFinish('jade', 'Yeşim', 'Jade', 10, Color(0xFF73D5BA)),
  BoardFinish('ruby', 'Yakut', 'Ruby', 10, Color(0xFFE58E9B)),
  BoardFinish('sapphire', 'Safir', 'Sapphire', 10, Color(0xFF76BDEA)),
  BoardFinish('amethyst', 'Ametist', 'Amethyst', 5, Color(0xFFC5A8E8)),
  BoardFinish('dragon', 'Ejder Mührü', 'Dragon Seal', 5, Color(0xFFE9AE71)),
  BoardFinish('celestial', 'Göksel', 'Celestial', 5, Color(0xFFF1D994)),
];

BoardFinish boardFinish(String id) => boardFinishes.firstWhere(
  (finish) => finish.id == id, orElse: () => boardFinishes.first);

Map<String, int> normalizeSkinPieces(Object? value) {
  if (value is! Map) return {};
  return {
    for (final finish in boardFinishes)
      if (value[finish.id] case final num amount when amount.isFinite && amount >= 0)
        finish.id: amount.toInt().clamp(0, finish.target),
  };
}
