const {test}=require('node:test');
const assert=require('node:assert/strict');
const {createServer}=require('node:http');
const {randomUUID,randomBytes,generateKeyPairSync,createPublicKey,diffieHellman,createHmac}=require('node:crypto');
const WebSocket=require('ws');
const {hashCredential,verifyCredential,tokenHash}=require('../dist/session');

test('credentials are salted, verified and reject legacy plaintext',()=>{
  const one=hashCredential('proof'),two=hashCredential('proof');
  assert.notEqual(one,two);
  assert.equal(verifyCredential('proof',one),true);
  assert.equal(verifyCredential('wrong',one),false);
  assert.equal(verifyCredential('proof','proof'),false);
  const pinOne=hashCredential('1234'),pinTwo=hashCredential('1234');
  assert.notEqual(pinOne,pinTwo);
  assert.equal(verifyCredential('1234',pinOne),true);
  assert.ok(pinOne.length>64);
  assert.equal(tokenHash('token').length,64);
});

test('shared API rate limiter hashes identities and enforces fixed-window decisions',async()=>{
  const {consumeIpRateLimit}=require('../dist/rate-limit');
  const calls=[];
  const runQuery=async(sql,params)=>{
    calls.push({sql,params});
    return {rows:[{count:String(calls.length===1?2:3),retry_after:'41'}]};
  };
  const allowed=await consumeIpRateLimit('192.0.2.7',2,60,runQuery);
  const limited=await consumeIpRateLimit('192.0.2.7',2,60,runQuery);
  assert.equal(allowed.allowed,true);
  assert.equal(limited.allowed,false);
  assert.equal(limited.retryAfterSeconds,41);
  assert.match(calls[0].sql,/ON CONFLICT \(key\) DO UPDATE/);
  assert.match(calls[0].sql,/INTERVAL '1 second'/);
  assert.notEqual(calls[0].params[0],'192.0.2.7');
  assert.match(calls[0].params[0],/^api:[0-9a-f]{64}$/);
});

test('Postgres rate-limit buckets expire and reset atomically',
  {skip:!process.env.DATABASE_URL},async()=>{
  const {initDb,closeDb}=require('../dist/db');
  const {consumeIpRateLimit}=require('../dist/rate-limit');
  const identity=`test-${randomUUID()}`;
  await initDb();
  try {
    assert.equal((await consumeIpRateLimit(identity,1,1)).allowed,true);
    const limited=await consumeIpRateLimit(identity,1,1);
    assert.equal(limited.allowed,false);
    assert.ok(limited.retryAfterSeconds>=1 && limited.retryAfterSeconds<=1);
    await new Promise(resolve=>setTimeout(resolve,1100));
    assert.equal((await consumeIpRateLimit(identity,1,1)).allowed,true);
  } finally {
    await closeDb();
  }
});

test('identity challenge binds proof to client private key and transcript',()=>{
  const {createIdentityChallenge}=require('../dist/identity-proof');
  const pair=generateKeyPairSync('x25519');
  const publicKey=Buffer.from(pair.publicKey.export({format:'jwk'}).x,'base64url').toString('hex');
  const challenge=createIdentityChallenge(publicKey,randomUUID(),'register');
  const peer=createPublicKey({key:{kty:'OKP',crv:'X25519',x:Buffer.from(challenge.serverPublicKey,'hex').toString('base64url')},format:'jwk'});
  const shared=diffieHellman({privateKey:pair.privateKey,publicKey:peer});
  const proof=createHmac('sha256',shared).update(challenge.context).digest('hex');
  assert.equal(tokenHash(proof),challenge.proofHash);
  assert.throws(()=>createIdentityChallenge('00'.repeat(32),randomUUID(),'register'));
  shared.fill(0);
});

test('call signaling can share the public HTTP listener at /signaling',async()=>{
  const {startSignalingServer,stopSignalingServer}=require('../dist/signaling');
  const server=createServer();
  const signaling=startSignalingServer(server);
  server.listen(0,'127.0.0.1');
  await new Promise(resolve=>server.once('listening',resolve));
  const address=server.address();
  const socket=new WebSocket(`ws://127.0.0.1:${address.port}/signaling`);
  try {
    await new Promise((resolve,reject)=>{socket.once('open',resolve);socket.once('error',reject);});
    assert.equal(socket.readyState,WebSocket.OPEN);
  } finally {
    const socketClosed=new Promise(resolve=>socket.once('close',resolve));
    await stopSignalingServer(signaling);
    await socketClosed;
    await new Promise(resolve=>server.close(resolve));
  }
});

test('real API: registration, authentication, conversations, messages, isolation and revocation',
  {skip:!process.env.DATABASE_URL},async()=>{
  const {initDb,closeDb,query}=require('../dist/db');
  const {app}=require('../dist/index');
  await initDb();
  const server=app.listen(0,'127.0.0.1');
  await new Promise(resolve=>server.once('listening',resolve));
  const base=`http://127.0.0.1:${server.address().port}/api/v1`;
  const health=await fetch(`http://127.0.0.1:${server.address().port}/health`);
  assert.equal(health.status,200);
  assert.equal((await health.json()).database,'ready');
  const accounts=[];
  const sockets=[];
  let signaling;
  const waitMessage=(socket,predicate)=>new Promise((resolve,reject)=>{
    const timeout=setTimeout(()=>{socket.off('message',handler);reject(new Error('signaling timeout'));},3000);
    function handler(data){const msg=JSON.parse(data.toString());if(predicate(msg)){clearTimeout(timeout);socket.off('message',handler);resolve(msg);}}
    socket.on('message',handler);
  });
  const req=async(method,path,body,token)=>{
    const r=await fetch(base+path,{method,headers:{'Content-Type':'application/json',...(token?{Authorization:`Bearer ${token}`}:{})},body:body?JSON.stringify(body):undefined});
    return {status:r.status,data:await r.json()};
  };
  const claim=async(pair,body,purpose)=>{
    const r=await req('POST','/auth/challenge',{publicKey:body.publicKey,deviceId:body.deviceId,purpose});
    assert.equal(r.status,200);
    const c=r.data;
    const key=createPublicKey({key:{kty:'OKP',crv:'X25519',x:Buffer.from(c.serverPublicKey,'hex').toString('base64url')},format:'jwk'});
    const secret=diffieHellman({privateKey:pair.privateKey,publicKey:key});
    const context=`chhaya-auth-v1|${purpose}|${c.challengeId}|${body.deviceId}|${body.publicKey}|${c.serverPublicKey}|${c.nonce}`;
    const identityProof=createHmac('sha256',secret).update(context).digest('hex');
    secret.fill(0);
    return {challengeId:c.challengeId,identityProof};
  };
  const signup=async()=>{
    const pair=generateKeyPairSync('x25519');
    const publicKey=Buffer.from(pair.publicKey.export({format:'jwk'}).x,'base64url').toString('hex');
    const body={chhayaId:'05'+publicKey,publicKey,displayName:'Test',encryptedPrivateKey:'encrypted-backup',recoveryPhraseHash:randomBytes(32).toString('hex'),deviceId:randomUUID()};
    Object.assign(body,await claim(pair,body,'register'));
    const r=await req('POST','/auth/register',body);
    assert.equal(r.status,201);
    assert.notEqual(r.data.token,r.data.userId);
    accounts.push(r.data.userId);
    return {...r.data,body,pair};
  };
  try{
    const alice=await signup(),bob=await signup(),outsider=await signup();
    // Knowing a public ID and recovery proof is insufficient without its private key.
    const invalidClaim=await claim(outsider.pair,alice.body,'login');
    assert.equal((await req('POST','/auth/login',{...alice.body,...invalidClaim})).status,401);
    const replay=await claim(alice.pair,alice.body,'login');
    assert.equal((await req('POST','/auth/login',{...alice.body,...replay})).status,200);
    assert.equal((await req('POST','/auth/login',{...alice.body,...replay})).status,401);

    assert.equal((await req('GET','/users/me',null,alice.userId)).status,401);
    assert.equal((await req('POST','/auth/login',{...alice.body,...await claim(alice.pair,alice.body,'login'),recoveryPhraseHash:'0'.repeat(64)})).status,401);
    const login=await req('POST','/auth/login',{...alice.body,...await claim(alice.pair,alice.body,'login')});
    assert.equal(login.status,200);
    assert.equal((await req('PUT','/users/me/settings',{pin:'1234',panicPin:'9876'},login.data.token)).status,200);
    const {verifyCredential}=require('../dist/session');
    const storedPins=await query('SELECT pin_hash,panic_pin_hash FROM users WHERE id=$1',[alice.userId]);
    assert.equal(verifyCredential('1234',storedPins.rows[0].pin_hash),true);
    assert.equal(verifyCredential('9876',storedPins.rows[0].panic_pin_hash),true);
    const contact=await req('POST','/contacts',{chhayaId:bob.body.chhayaId,displayName:'Bob'},alice.token);
    assert.equal(contact.status,201);
    const cid=contact.data.conversationId;
    assert.equal((await req('POST','/contacts',{chhayaId:outsider.body.chhayaId,displayName:'Guest'},alice.token)).status,201);
    const createdGroup=await req('POST','/conversations',{type:'group',participantIds:[bob.userId,outsider.userId],name:'Test group'},alice.token);
    assert.equal(createdGroup.status,201);
    const groupId=createdGroup.data.conversationId;
    const groupList=await req('GET','/conversations',null,alice.token);
    const group=groupList.data.find(c=>c.id===groupId);
    assert.equal(group.is_admin,true);
    assert.deepEqual(group.participants.map(p=>p.is_admin).sort(),[false,false,true]);
    assert.equal((await req('PATCH',`/conversations/${groupId}/participants/${alice.userId}`,{isAdmin:false},alice.token)).status,409);
    assert.equal((await req('PATCH',`/conversations/${groupId}/participants/${bob.userId}`,{isAdmin:true},outsider.token)).status,403);
    assert.equal((await req('PATCH',`/conversations/${groupId}/participants/${bob.userId}`,{isAdmin:true},alice.token)).status,200);
    assert.equal((await req('PATCH',`/conversations/${groupId}/participants/${alice.userId}`,{isAdmin:false},alice.token)).status,200);
    assert.equal((await req('DELETE',`/conversations/${groupId}/participants/${outsider.userId}`,null,alice.token)).status,403);
    const groupMessageId=randomUUID();
    const groupEnvelope=JSON.stringify({v:1,kind:'chhaya-group-v1',conversationId:groupId,messageId:groupMessageId,senderId:alice.userId,keys:{[bob.userId]:'bob-wrapper',[outsider.userId]:'guest-wrapper'},body:'opaque-body'});
    assert.equal((await req('POST','/messages',{messageId:groupMessageId,conversationId:groupId,content:groupEnvelope},alice.token)).status,201);
    assert.equal((await req('DELETE',`/conversations/${groupId}/participants/${outsider.userId}`,null,bob.token)).status,200);
    assert.equal((await req('POST','/messages',{messageId:groupMessageId,conversationId:groupId,content:groupEnvelope},alice.token)).status,200);
    const staleId=randomUUID();
    const staleEnvelope=JSON.stringify({v:1,kind:'chhaya-group-v1',conversationId:groupId,messageId:staleId,senderId:alice.userId,keys:{[bob.userId]:'bob-wrapper',[outsider.userId]:'guest-wrapper'},body:'opaque-body'});
    assert.equal((await req('POST','/messages',{messageId:staleId,conversationId:groupId,content:staleEnvelope},alice.token)).status,409);
    assert.equal((await req('GET',`/messages/${groupId}`,null,outsider.token)).status,403);
    const currentId=randomUUID();
    const currentEnvelope=JSON.stringify({v:1,kind:'chhaya-group-v1',conversationId:groupId,messageId:currentId,senderId:alice.userId,keys:{[bob.userId]:'bob-wrapper'},body:'opaque-body'});
    assert.equal((await req('POST','/messages',{messageId:currentId,conversationId:groupId,content:currentEnvelope},alice.token)).status,201);
    assert.equal((await req('DELETE',`/conversations/${groupId}/participants/${bob.userId}`,null,bob.token)).status,409);
    const {startSignalingServer}=require('../dist/signaling');
    const WebSocket=require('ws');
    signaling=startSignalingServer();
    const connect=async(account)=>{
      const ws=new WebSocket('ws://127.0.0.1:8444');sockets.push(ws);
      await new Promise((resolve,reject)=>{ws.once('open',resolve);ws.once('error',reject);});
      const joined=waitMessage(ws,msg=>msg.type==='join');
      ws.send(JSON.stringify({type:'join',payload:{token:account.token,deviceId:account.body.deviceId}}));
      await joined;return ws;
    };
    const aliceSocket=await connect(alice),bobSocket=await connect(bob);
    const relayed=waitMessage(bobSocket,msg=>msg.type==='offer');
    aliceSocket.send(JSON.stringify({type:'offer',to:bob.userId,payload:{conversationId:cid,callId:randomUUID(),envelope:'opaque-encrypted-sdp'}}));
    const offer=await relayed;
    assert.equal(offer.from,alice.userId);
    assert.equal(offer.payload.envelope,'opaque-encrypted-sdp');
    assert.equal((await req('GET','/calls/incoming',null)).status,401);
    const pendingCalls=await req('GET','/calls/incoming',null,bob.token);
    assert.equal(pendingCalls.status,200);
    assert.equal(pendingCalls.data.length,1);
    assert.equal(pendingCalls.data[0].callId,offer.payload.callId);
    assert.equal(pendingCalls.data[0].conversationId,cid);
    assert.equal(pendingCalls.data[0].senderId,alice.userId);
    assert.equal(pendingCalls.data[0].envelope,'opaque-encrypted-sdp');
    assert.equal((await req('GET','/calls/incoming',null,outsider.token)).data.length,0);
    const answerRelayed=waitMessage(aliceSocket,msg=>msg.type==='answer'&&msg.payload.callId===offer.payload.callId);
    bobSocket.send(JSON.stringify({type:'answer',to:alice.userId,payload:{conversationId:cid,callId:offer.payload.callId,envelope:'opaque-encrypted-answer'}}));
    await answerRelayed;
    assert.equal((await req('GET','/calls/incoming',null,bob.token)).data.length,0);

    const sent=await req('POST','/messages',{conversationId:cid,content:'opaque-encrypted-envelope'},alice.token);
    assert.equal(sent.status,201);
    assert.equal(sent.data.conversation_id,cid);
    assert.equal(sent.data.delivered_at,null);
    const retry=await req('POST','/messages',{messageId:sent.data.id,conversationId:cid,content:'opaque-encrypted-envelope'},alice.token);
    assert.equal(retry.status,200);
    assert.equal((await req('POST','/messages',{messageId:sent.data.id,conversationId:cid,content:'changed'},alice.token)).status,409);
    assert.equal((await req('POST','/messages',{messageId:sent.data.id,conversationId:cid,content:'opaque-encrypted-envelope'},bob.token)).status,409);
    const deviceConflict=await req('POST','/auth/login',{...alice.body,deviceId:bob.body.deviceId,
      ...await claim(alice.pair,{...alice.body,deviceId:bob.body.deviceId},'login')});
    assert.equal(deviceConflict.status,409);

    const incoming=await req('GET',`/messages/${cid}`,null,bob.token);
    assert.equal(incoming.status,200);
    assert.equal(incoming.data[0].content,'opaque-encrypted-envelope');
    assert.ok(incoming.data[0].delivered_at);
    assert.equal(incoming.data[0].read_at,null);
    const senderDelivered=await req('GET',`/messages/${cid}`,null,alice.token);
    const deliveredRecord=senderDelivered.data.find(message=>message.id===sent.data.id);
    assert.ok(deliveredRecord.delivered_at);
    assert.equal(deliveredRecord.read_at,null);
    const largeEnvelope='x'.repeat(500000);
    const attachment=await req('POST','/messages',{conversationId:cid,content:largeEnvelope},alice.token);
    assert.equal(attachment.status,201);
    assert.equal(attachment.data.content,largeEnvelope);
    assert.equal((await req('POST','/messages',{conversationId:cid,content:'x'.repeat(768*1024+1)},alice.token)).status,400);
    // Keep pagination fixtures independent of the attachment-size checks.
    await query('DELETE FROM messages WHERE id=$1',[attachment.data.id]);

    // Identical timestamps must not drop records at page boundaries.
    const tiedIds=Array.from({length:4},()=>randomUUID());
    for(const id of tiedIds) await query(
      'INSERT INTO messages (id,conversation_id,sender_id,content,sent_at) VALUES ($1,$2,$3,$4,$5)',
      [id,cid,alice.userId,'pagination','2026-01-01T00:00:00.123456Z']);
    const seen=[]; let cursor;
    for(let page=0;page<6;page++) {
      const response=await req('GET',`/messages/${cid}?limit=1${cursor?'&beforeId='+cursor:''}`,null,bob.token);
      assert.equal(response.status,200);
      if(!response.data.length) break;
      cursor=response.data[0].id; seen.push(cursor);
    }
    assert.equal(seen.length,5);
    assert.equal(new Set(seen).size,5);
    for(const id of tiedIds) assert.ok(seen.includes(id));
    assert.equal((await req('GET',`/messages/${cid}?beforeId=invalid`,null,bob.token)).status,400);
    assert.equal((await req('GET','/conversations',null,alice.token)).status,200);
    assert.equal((await req('GET',`/messages/${cid}`,null,outsider.token)).status,403);
    assert.equal((await req('POST',`/messages/${sent.data.id}/read`,{},outsider.token)).status,403);
    assert.equal((await req('POST',`/messages/${sent.data.id}/read`,{},bob.token)).status,200);
    const senderRead=await req('GET',`/messages/${cid}`,null,alice.token);
    assert.ok(senderRead.data.find(message=>message.id===sent.data.id).read_at);
    assert.equal((await req('POST','/auth/logout',{},alice.token)).status,200);
    assert.equal((await req('GET','/users/me',null,alice.token)).status,401);
  }finally{
    for(const socket of sockets) socket.terminate();
    if(signaling) await new Promise(resolve=>signaling.close(resolve));
    await query('DELETE FROM conversations WHERE created_by=ANY($1::uuid[])',[accounts]);
    await query('DELETE FROM users WHERE id=ANY($1::uuid[])',[accounts]);
    await new Promise(resolve=>server.close(resolve));
    await closeDb();
  }
});
