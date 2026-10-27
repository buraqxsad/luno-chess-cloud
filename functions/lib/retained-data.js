'use strict';

const record=value=>value!==null&&typeof value==='object'&&!Array.isArray(value);
const timestamp=value=>Number.isSafeInteger(value)&&value>=0&&value<=8640000000000000;
const code=(value,max=80)=>typeof value==='string'&&value.length>0&&value.length<=max&&/^[A-Za-z0-9_-]+$/.test(value);
const digest=value=>typeof value==='string'&&/^[a-f0-9]{64}$/.test(value);
function retiredOwner(value,field,uid,pseudonym,flag){
  return value[field]===uid||value[field]===pseudonym&&(value[flag]===true||timestamp(value.anonymizedAt)&&value.anonymizedAt>0);
}
function anonymizedAt(value,at){return timestamp(value.anonymizedAt)&&value.anonymizedAt>0&&value.anonymizedAt<=at?value.anonymizedAt:at;}
function retainPurchaseClaim(value,uid,pseudonym,at){
  if(!record(value)||!retiredOwner(value,'uid',uid,pseudonym,'accountDeleted'))return undefined;
  const result={uid:pseudonym,accountDeleted:true,active:false,anonymizedAt:anonymizedAt(value,at)};
  if(typeof value.productId==='string'&&/^[A-Za-z0-9._-]{1,80}$/.test(value.productId))result.productId=value.productId;
  for(const field of ['status','kind','entitlementStatus','refundReviewStatus'])if(code(value[field]))result[field]=value[field];
  for(const field of ['verifiedAt','grantedAt','completedAt','lastReconciledAt','expiry','voidedAt'])if(timestamp(value[field]))result[field]=value[field];
  for(const field of ['grantGold','grantGems','voidedReason'])if(Number.isSafeInteger(value[field])&&value[field]>=0&&value[field]<=1000000000)result[field]=value[field];
  for(const field of ['orderIdHash','voidedOrderIdHash'])if(digest(value[field]))result[field]=value[field];
  if(typeof value.voided==='boolean')result.voided=value.voided;
  if(Number.isSafeInteger(value.lastRtdnType)&&value.lastRtdnType>=0&&value.lastRtdnType<=100||value.lastRtdnType==='voided')result.lastRtdnType=value.lastRtdnType;
  return result;
}
function retainModerationReport(value,uid,pseudonym,at){
  if(!record(value))return undefined;
  const reporter=retiredOwner(value,'reporterUid',uid,pseudonym,'reporterDeleted'),target=retiredOwner(value,'targetUid',uid,pseudonym,'targetDeleted');
  if(!reporter&&!target)return undefined;
  const result={anonymizedAt:anonymizedAt(value,at)};
  for(const field of ['reportId','reason','status'])if(code(value[field],80))result[field]=value[field];
  for(const field of ['createdAt','resolvedAt'])if(timestamp(value[field]))result[field]=value[field];
  for(const [field,matched,flag] of [['reporterUid',reporter,'reporterDeleted'],['targetUid',target,'targetDeleted']]){
    if(matched){result[field]=pseudonym;result[flag]=true;}
    else if(typeof value[field]==='string'&&/^[A-Za-z0-9_-]{6,128}$/.test(value[field])){
      result[field]=value[field];if(value[flag]===true)result[flag]=true;
    }
  }
  return result;
}
function purchaseClaimRetired(value){return record(value)&&(value.accountDeleted===true||value.anonymizedAt!=null);}

module.exports={retainPurchaseClaim,retainModerationReport,purchaseClaimRetired};
