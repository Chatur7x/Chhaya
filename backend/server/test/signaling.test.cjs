const {test}=require('node:test');
const assert=require('node:assert/strict');
const {createServer}=require('node:http');
const WebSocket=require('ws');
const db=require('../dist/db');
const session=require('../dist/session');
const {startSignalingServer}=require('../dist/signaling');

const alice='11111111-1111-4111-8111-111111111111';
const bob='22222222-2222-4222-8222-222222222222';
const carol='33333333-3333-4333-8333-333333333333';
const direct='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const group='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const tokens=new Map([['alice-token',alice],['bob-token',bob],['carol-token',carol]]);

function waitFor(socket,predicate,timeoutMs=2000){
  return new Promise((resolve,reject)=>{
    const timeout=setTimeout(()=>{socket.off('message',handler);reject(new Error('signaling timeout'));},timeoutMs);
    function handler(data){
      const message=JSON.parse(data.toString());
      if(predicate(message)){clearTimeout(timeout);socket.off('message',handler);resolve(message);}
    }
    socket.on('message',handler);
  });
}

test('typing is authenticated, direct-only, membership-checked and payload-minimized',async()=>{
  const originalQuery=db.query;
  const originalAuthenticate=session.authenticateToken;
  db.query=async(sql,params)=>{
    if(sql.includes('SELECT id FROM users')) return {rows:[{id:params[0]}],rowCount:1};
    if(sql.includes('SELECT user_id FROM conversation_participants')){
      const members=params[0]===direct?[alice,bob]:params[0]===group?[alice,bob,carol]:[];
      return {rows:members.map(user_id=>({user_id})),rowCount:members.length};
    }
    throw new Error(`Unexpected signaling query: ${sql}`);
  };
  session.authenticateToken=async(token)=>tokens.get(token)||null;

  const server=createServer();
  const signaling=startSignalingServer(server);
  const sockets=[];
  try{
    server.listen(0,'127.0.0.1');
    await new Promise(resolve=>server.once('listening',resolve));
    const address=server.address();
    const connect=async(token)=>{
      const socket=new WebSocket(`ws://127.0.0.1:${address.port}/signaling`);
      sockets.push(socket);
      await new Promise((resolve,reject)=>{socket.once('open',resolve);socket.once('error',reject);});
      const joined=waitFor(socket,message=>message.type==='join');
      socket.send(JSON.stringify({type:'join',payload:{token,deviceId:'device-id'}}));
      await joined;
      return socket;
    };
    const aliceSocket=await connect('alice-token');
    const bobSocket=await connect('bob-token');
    const carolSocket=await connect('carol-token');
    const received=[];
    bobSocket.on('message',data=>{
      const message=JSON.parse(data.toString());
      if(message.type==='typing') received.push(message);
    });
    const carolReceived=[];
    carolSocket.on('message',data=>{
      const message=JSON.parse(data.toString());
      if(message.type==='typing') carolReceived.push(message);
    });

    const unauthenticated=new WebSocket(`ws://127.0.0.1:${address.port}/signaling`);
    sockets.push(unauthenticated);
    await new Promise((resolve,reject)=>{
      unauthenticated.once('open',resolve);
      unauthenticated.once('error',reject);
    });
    unauthenticated.send(JSON.stringify({type:'typing',payload:{conversationId:direct,active:true}}));
    await new Promise(resolve=>setTimeout(resolve,250));
    assert.equal(received.length,0);

    const active=waitFor(bobSocket,message=>message.type==='typing'&&message.payload.active===true);
    aliceSocket.send(JSON.stringify({type:'typing',from:carol,to:carol,payload:{
      conversationId:direct,active:true,secretDraft:'must never be relayed',
    }}));
    const event=await active;
    assert.equal(event.from,alice);
    assert.equal(event.to,bob);
    assert.deepEqual(event.payload,{conversationId:direct,active:true});

    // Repeated active refreshes keep the remote indicator alive, while a
    // per-session server throttle prevents message-rate amplification.
    aliceSocket.send(JSON.stringify({type:'typing',payload:{conversationId:direct,active:true}}));
    await new Promise(resolve=>setTimeout(resolve,550));
    assert.equal(received.length,1);
    const refresh=waitFor(bobSocket,message=>message.type==='typing'&&message.payload.active===true);
    aliceSocket.send(JSON.stringify({type:'typing',payload:{conversationId:direct,active:true}}));
    await refresh;

    await new Promise(resolve=>setTimeout(resolve,250));
    const stopped=waitFor(bobSocket,message=>message.type==='typing'&&message.payload.active===false);
    aliceSocket.send(JSON.stringify({type:'typing',payload:{conversationId:direct,active:false}}));
    await stopped;

    await new Promise(resolve=>setTimeout(resolve,550));
    aliceSocket.send(JSON.stringify({type:'typing',payload:{conversationId:group,active:true}}));
    await new Promise(resolve=>setTimeout(resolve,550));
    aliceSocket.send(JSON.stringify({type:'typing',to:carol,payload:{conversationId:direct,active:true}}));
    await new Promise(resolve=>setTimeout(resolve,250));
    assert.equal(received.filter(message=>message.payload.conversationId===group).length,0);
    assert.equal(received.filter(message=>message.to===carol).length,0);
    assert.equal(carolReceived.length,0);
  }finally{
    await Promise.all(sockets.map(socket=>new Promise(resolve=>{
      if(socket.readyState===WebSocket.CLOSED) return resolve();
      socket.once('close',resolve);
      socket.terminate();
    })));
    await new Promise(resolve=>signaling.close(resolve));
    await new Promise(resolve=>server.close(resolve));
    db.query=originalQuery;
    session.authenticateToken=originalAuthenticate;
  }
});
