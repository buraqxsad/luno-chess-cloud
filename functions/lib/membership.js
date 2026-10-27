'use strict';

const ENTITLEMENT_VERSION=2;
const LEGACY_PASS_COSTUMES=Object.freeze(['k_crystal','q_crystal','r_ice','b_wizard','n_armor','p_soldier']);
const record=value=>value!==null&&typeof value==='object'&&!Array.isArray(value);
const expiry=value=>Number.isSafeInteger(Number(value))&&Number(value)>0?Number(value):0;

function membershipState(profile,at){
  const expiresAt=expiry(profile?.premiumUntil);
  return {active:expiresAt>at,expiresAt};
}

function ownedCosmeticIds(value){
  if(Array.isArray(value))return value.filter(id=>typeof id==='string');
  if(!record(value))return [];
  return Object.entries(value).flatMap(([key,item])=>item===true?[key]:typeof item==='string'?[item]:[]);
}

function normalizeProductEntitlements(profile){
  if(profile.productEntitlementVersion===ENTITLEMENT_VERSION)return false;
  // The old Pass advertised these shared cosmetic rights. Preserve them as
  // owned items without pretending that a Pass is a subscription membership.
  if(profile.passState?.premium===true){
    if(!record(profile.inventory))profile.inventory={};
    for(const [field,ids] of [
      ['ownedFrames',['premium','crown_elite']],
      ['ownedBioFrames',['premium']],
      ['ownedCostumes',LEGACY_PASS_COSTUMES],
    ]){
      const previous=ownedCosmeticIds(profile.inventory[field]);
      profile.inventory[field]=[...new Set([...previous,...ids])];
    }
    if(profile.passState.premiumSource==='subscription')profile.passState.premiumSource='grandfathered_subscription';
  }
  profile.productEntitlementVersion=ENTITLEMENT_VERSION;
  return true;
}

module.exports={ENTITLEMENT_VERSION,LEGACY_PASS_COSTUMES,membershipState,normalizeProductEntitlements};
