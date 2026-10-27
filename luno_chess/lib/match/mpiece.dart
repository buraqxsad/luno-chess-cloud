import '../engine/piece.dart';

/// Maç sırasındaki değişebilir (mutable) taş: tür/renk + tüm kart efekt
/// bayrakları. Saf motorun değişmez Piece'inden ayrıdır (kart katmanı buna ekler).
class MPiece {
  PieceColor color;
  PieceType type;
  bool moved;

  // Kart efektleri (HTML birebir)
  int frozen; // kalan tur (hareket edemez)
  int resist; // alınamaz sayacı
  bool resistLock; // bu tur oynanamaz
  bool barbarian; // kalıcı: 2 ileri
  bool poisoned; // vezir: 1 kare kısıtı
  int poisonedDur;
  int plagueUntil; // Kara Veba: moveCount bu değere gelene kadar piyon kilitli
  int trapped; // hapis sayacı
  bool angryN; // bu tur (±1,3) sıçrar
  bool angryB; // bu tur ek yatay
  bool ghost; // oynanamaz hayalet
  int ghostDur;
  int? linkTo; // tutkal eşi (kare indeksi)
  bool gluePick; // tutkal ilk seçim işareti

  MPiece(
    this.color,
    this.type, {
    this.moved = false,
    this.frozen = 0,
    this.resist = 0,
    this.resistLock = false,
    this.barbarian = false,
    this.poisoned = false,
    this.poisonedDur = 0,
    this.plagueUntil = 0,
    this.trapped = 0,
    this.angryN = false,
    this.angryB = false,
    this.ghost = false,
    this.ghostDur = 0,
    this.linkTo,
    this.gluePick = false,
  });

  MPiece clone() => MPiece(
    color,
    type,
    moved: moved,
    frozen: frozen,
    resist: resist,
    resistLock: resistLock,
    barbarian: barbarian,
    poisoned: poisoned,
    poisonedDur: poisonedDur,
    plagueUntil: plagueUntil,
    trapped: trapped,
    angryN: angryN,
    angryB: angryB,
    ghost: ghost,
    ghostDur: ghostDur,
    linkTo: linkTo,
    gluePick: gluePick,
  );
}
