const {test}=require('node:test');
const assert=require('node:assert/strict');
const {randomUUID,randomBytes}=require('node:crypto');
const {hashCredential,verifyCredential,tokenHash}=require('../dist/session');

test('credentials are salted, verified and reject legacy plaintext',()=>{
  const one=hashCredential('proof'),two=hashCredential('proof');
  assert.notEqual(one,two);
  assert.equal(verifyCredential('proof',one),true);
  assert.equal(verifyCredential('wrong',one),false);
  assert.equal(verifyCredential('proof','proof'),false);
  assert.equal(tokenHash('token').length,64);
});

test('real API: registration, authentication, conversations, messages, isolation and revocation',
  {skip:!process.env.DATABASE_URL},async()=>{
  const {initDb,closeDb,query}=require('../dist/db');
  const {app}=require('../dist/index');
  await initDb();
  const server=app.listen(0,'127.0.0.1');
  await new Promise(resolve=>server.once('listening',resolve));
  const base=`http://127.0.0.1:${server.address().port}/api/v1`;
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
  const signup=async()=>{
    const publicKey=randomBytes(32).toString('hex');
    const body={chhayaId:'05'+publicKey,publicKey,displayName:'Test',encryptedPrivateKey:'encrypted-backup',recoveryPhraseHash:randomBytes(32).toString('hex'),deviceId:randomUUID()};
    const r=await req('POST','/auth/register',body);
    assert.equal(r.status,201);
    assert.notEqual(r.data.token,r.data.userId);
    accounts.push(r.data.userId);
    return {...r.data,body};
  };
  try{
    const alice=await signup(),bob=await signup(),outsider=await signup();
    assert.equal((await req('GET','/users/me',null,alice.userId)).status,401);
    assert.equal((await req('POST','/auth/login',{...alice.body,recoveryPhraseHash:'0'.repeat(64)})).status,401);
    const login=await req('POST','/auth/login',alice.body);
    assert.equal(login.status,200);
    const contact=await req('POST','/contacts',{chhayaId:bob.body.chhayaId,displayName:'Bob'},alice.token);
    assert.equal(contact.status,201);
    const cid=contact.data.conversationId;
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

    const sent=await req('POST','/messages',{conversationId:cid,content:'opaque-encrypted-envelope'},alice.token);
    assert.equal(sent.status,201);
    assert.equal(sent.data.conversation_id,cid);
    const incoming=await req('GET',`/messages/${cid}`,null,bob.token);
    assert.equal(incoming.status,200);
    assert.equal(incoming.data[0].content,'opaque-encrypted-envelope');
    assert.equal((await req('GET','/conversations',null,alice.token)).status,200);
    assert.equal((await req('GET',`/messages/${cid}`,null,outsider.token)).status,403);
    assert.equal((await req('POST',`/messages/${sent.data.id}/read`,{},outsider.token)).status,403);
    assert.equal((await req('POST',`/messages/${sent.data.id}/read`,{},bob.token)).status,200);
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
