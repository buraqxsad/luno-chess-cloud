import {CARDS,STARTER,validateDeck,type CardId} from '../model.js';
import {BattleError} from './protocol.js';
export interface V1Migration {migrationVersion:1;deck:CardId[];entitlements:CardId[];fallback:boolean;rating:number;provisionalSkillSeed:number}
export function mappedCard(value:unknown):CardId|null{
  if(typeof value!=='string')return null;
  if(/^radar[123]?$/.test(value))return 'radar';
  return Object.hasOwn(CARDS,value)?value as CardId:null;
}
function earnedCards(profile:Record<string,unknown>):CardId[]{
  // New V1 accounts still carry compatibility defaults for old profile routes.
  // Those defaults are not earned V1 cards; existing migrated rights stay below.
  const unlocked=profile.battleV1MigrationPolicy==='native-v1'?{}:
    profile.unlockedCards&&typeof profile.unlockedCards==='object'&&!Array.isArray(profile.unlockedCards)?profile.unlockedCards as Record<string,unknown>:{};
  const battleUnlocked=profile.battleV1UnlockedCards&&typeof profile.battleV1UnlockedCards==='object'&&!Array.isArray(profile.battleV1UnlockedCards)?profile.battleV1UnlockedCards as Record<string,unknown>:{};
  const earned=new Set<CardId>();
  for(const [raw,owned] of Object.entries(unlocked)){const id=mappedCard(raw);if(owned===true&&id)earned.add(id);}
  for(const [raw,owned] of Object.entries(battleUnlocked)){const id=mappedCard(raw);if(owned===true&&id)earned.add(id);}
  return [...earned];
}
export function migrateLegacy(profile:Record<string,unknown>,existing?:V1Migration|null):V1Migration{
  if(existing?.migrationVersion===1){
    const entitlements=[...new Set([...STARTER,...(Array.isArray(existing.entitlements)?existing.entitlements:[]).filter(c=>Object.hasOwn(CARDS,c)),...earnedCards(profile)])];
    let deck=existing.deck,fallback=existing.fallback;try{validateDeck(deck);if(deck.some(c=>!entitlements.includes(c)))throw new Error();}catch{deck=[...STARTER];fallback=true;}
    return {...existing,deck:[...deck],entitlements,fallback,rating:Number.isSafeInteger(existing.rating)&&existing.rating>=0?existing.rating:0};
  }
  const entitled=new Set<CardId>([...STARTER,...earnedCards(profile)]);
  const mapped=[...new Set((Array.isArray(profile.deck)?profile.deck:[]).map(mappedCard).filter((c):c is CardId=>c!==null&&entitled.has(c)))];
  const fallback=mapped.length!==10;
  const seed=Number.isSafeInteger(profile.trophies)&&Number(profile.trophies)>=0?Number(profile.trophies):0;
  return {migrationVersion:1,deck:fallback?[...STARTER]:mapped,entitlements:[...entitled],fallback,rating:0,provisionalSkillSeed:seed};
}
export function validateOwnedDeck(deck:unknown,account:V1Migration):CardId[]{
  if(!Array.isArray(deck))throw new BattleError('INVALID_DECK',400);
  try{validateDeck(deck as CardId[]);}catch{throw new BattleError('INVALID_DECK',400);}
  if(deck.some(c=>!account.entitlements.includes(c)))throw new BattleError('CARD_NOT_OWNED',403);
  return [...deck] as CardId[];
}
