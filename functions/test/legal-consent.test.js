'use strict';

const test=require('node:test');
const assert=require('node:assert/strict');
const {
  starterProfile,LEGAL_TERMS_VERSION,LEGAL_PRIVACY_VERSION,LEGAL_COMMUNITY_VERSION,legalConsentState,assertCurrentLegalConsent
}=require('../index.js')._test;

function acceptedConsent(uid,overrides){
  return Object.assign({
    uid,
    termsVersion:LEGAL_TERMS_VERSION,
    privacyVersion:LEGAL_PRIVACY_VERSION,
    communityVersion:LEGAL_COMMUNITY_VERSION,
    acceptedAt:Date.parse('2026-08-11T12:00:00Z')
  },overrides||{});
}

test('new players have no current legal consent',function(){
  const profile=starterProfile('legal-user-1','legal_one');
  const state=legalConsentState(profile);
  assert.equal(state.accepted,false);
  assert.equal(state.acceptedAt,0);
  assert.equal(state.termsVersion,LEGAL_TERMS_VERSION);
  assert.equal(state.privacyVersion,LEGAL_PRIVACY_VERSION);
});

test('only the current server versions for the same UID are accepted',function(){
  const profile=starterProfile('legal-user-2','legal_two');
  profile.legalConsent=acceptedConsent(profile.uid);
  assert.equal(legalConsentState(profile).accepted,true);
  assert.doesNotThrow(function(){assertCurrentLegalConsent(profile,profile.uid);});

  profile.legalConsent=acceptedConsent('another-user');
  assert.equal(legalConsentState(profile).accepted,false);
  assert.throws(function(){assertCurrentLegalConsent(profile,profile.uid);},{code:'legal-consent-required'});

  profile.legalConsent=acceptedConsent(profile.uid,{termsVersion:'terms-old'});
  assert.equal(legalConsentState(profile).accepted,false);
  profile.legalConsent=acceptedConsent(profile.uid,{privacyVersion:'privacy-old'});
  assert.equal(legalConsentState(profile).accepted,false);
  profile.legalConsent=acceptedConsent(profile.uid,{acceptedAt:0});
  assert.equal(legalConsentState(profile).accepted,false);
});

test('a current consent cannot be reused for another authenticated profile',function(){
  const profile=starterProfile('legal-user-3','legal_three');
  profile.legalConsent=acceptedConsent(profile.uid);
  assert.throws(function(){assertCurrentLegalConsent(profile,'legal-user-4');},{code:'legal-consent-required'});
});
