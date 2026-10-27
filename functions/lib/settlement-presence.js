'use strict';

// A settlement retry must never erase the next match or a new queue presence.
async function settlePlayerPresence(db,uid,matchId,status){
  await db.ref(`rankedState/activeByUser/${uid}`).transaction(function(current){
    if(current===null)return null;
    return current===matchId?null:undefined;
  },undefined,false);
  await db.ref(`rankedPlayers/${uid}`).transaction(function(current){
    if(current===null)return null;
    if(!current||current.matchId!==matchId)return;
    return status;
  },undefined,false);
}

module.exports={settlePlayerPresence};
