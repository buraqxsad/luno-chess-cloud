'use strict';
const {isDeepStrictEqual}=require('node:util');

function playerStateRevision(profile){
  const value=profile&&profile.stateRevision;
  return Number.isSafeInteger(value)&&value>=0?value:0;
}

function advancePlayerStateRevision(profile,previous=playerStateRevision(profile)){
  if(previous>=Number.MAX_SAFE_INTEGER){
    const error=new Error('Player state revision is exhausted.');
    error.code='player-state-revision-invalid';error.status=409;
    throw error;
  }
  profile.stateRevision=previous+1;
}

function finalizePlayerStateRevision(profile,previousProfile){
  const previous=playerStateRevision(previousProfile);
  if(Object.hasOwn(previousProfile,'stateRevision'))profile.stateRevision=previousProfile.stateRevision;
  else delete profile.stateRevision;
  if(!isDeepStrictEqual(profile,previousProfile))advancePlayerStateRevision(profile,previous);
}

module.exports={playerStateRevision,finalizePlayerStateRevision};
