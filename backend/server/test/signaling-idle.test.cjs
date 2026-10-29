const {test}=require('node:test');
const assert=require('node:assert/strict');
const {createServer}=require('node:http');
const WebSocket=require('ws');
const {startSignalingServer,stopSignalingServer}=require('../dist/signaling');
test('unauthenticated idle signaling sockets are disconnected',{timeout:22000},async()=>{
 const server=createServer();const wss=startSignalingServer(server);let socket;
 try {
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  socket=new WebSocket(`ws://127.0.0.1:${server.address().port}/signaling`);
  await new Promise((resolve,reject)=>{socket.once('open',resolve);socket.once('error',reject);});
  await new Promise(resolve=>socket.once('close',resolve));
  assert.equal(socket.readyState,WebSocket.CLOSED);
 } finally {
  socket?.terminate();await stopSignalingServer(wss);
  await new Promise(resolve=>server.close(resolve));
 }
});
