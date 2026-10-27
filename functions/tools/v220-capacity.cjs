'use strict';

const {bytes,syntheticConversation,saveJson}=require('./v220-support.cjs');
const api=require('../index')._test;
const sender='v220_sender',recipient='v220_recipient';
const rows=[];
for(const count of [0,100,1000,5000]){
  const conversation=syntheticConversation(api,sender,recipient,count,240);
  const proofs=conversation.sendRequests[api.hash(sender)];
  rows.push({messages:count,conversationJsonBytes:bytes(conversation),messageJsonBytes:bytes(conversation.msgs),
    conversationProofJsonBytes:bytes(conversation.sendRequests),senderBindingsJsonBytes:bytes(proofs),
    persistentProofCopies:count*2,
    minWholeConversationTransactionJsonBytes:bytes(conversation)});
}
const perMessage=(rows[3].conversationJsonBytes-rows[1].conversationJsonBytes)/4900;
const result={kind:'synthetic JSON serialization; no Firebase load, latency, billing or device benchmark',
  assumptions:{textUtf8Bytes:240,pushKeyLength:19,senderUid:sender,hashHexLength:64,
    retention:'All messages/proofs retained; sender binding remains until sender account deletion',
    sdkSingleWriteLimitBytes:16*1024*1024,wireOverhead:'Not modeled; SDK serialization/protocol adds overhead'},
  rows,projectedMessagesAt16MiBConversation:Math.floor((16*1024*1024-rows[0].conversationJsonBytes)/perMessage),
  polling:{players:1000,minutes:60,matchAndEmoteRequestsPerPlayerMinute:60,totalRequests:1000*60*60,
    snapshotBytes:3529,matchPollsPerPlayerMinute:30,uncompressedSnapshotBytes:1000*60*30*3529,
    note:'V219 3529-byte fixture assumption; excludes emote payloads, TLS/HTTP, compression and backend read amplification'},
  retentionProposal:{status:'Decision required; not implemented',
    requestExpiry:'Version new request IDs with server-validated expiry and reject expired requests forever; never turn pruned IDs into fresh sends.',
    legacy:'Existing opaque request IDs cannot be safely TTL-pruned. Keep durable binding/tombstone until sender deletion.',
    indexes:'Maintain durable per-owner conversation-key metadata, independent of inbox/friend/block; reconcile legacy orphan membership before declaring migration complete.',
    transactions:'Separate bounded ownership/lease metadata from retained message/proof trees; preserve collision serialization and atomic message/proof/inbox/binding fanout.'}};
saveJson('capacity.json',result);console.log(JSON.stringify(result,null,2));
