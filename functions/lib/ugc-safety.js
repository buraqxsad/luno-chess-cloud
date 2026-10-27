'use strict';

const BIO_MAX_LENGTH=160;
const MESSAGE_MAX_LENGTH=500;
const UNSAFE_TEXT=/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F-\u009F\u200B\u200E\u200F\u202A-\u202E\u2060-\u206F\uFEFF<>]/u;

function normalizeUgcText(value,maxLength,{allowEmpty=false}={}){
  if(typeof value!=='string'||value.length>4096)return null;
  // Inspect compatibility forms too, but preserve legitimate user spelling.
  if(UNSAFE_TEXT.test(value.normalize('NFKC')))return null;
  const normalized=value.replace(/\s+/gu,' ').trim();
  if((!allowEmpty&&!normalized)||normalized.length>maxLength)return null;
  return normalized;
}

// Legacy unsafe biographies are hidden on public surfaces, not destroyed.
function safePublicBio(value){
  return normalizeUgcText(value,BIO_MAX_LENGTH,{allowEmpty:true})??'';
}

module.exports={BIO_MAX_LENGTH,MESSAGE_MAX_LENGTH,normalizeUgcText,safePublicBio};
