import assert from 'node:assert/strict';
import vm from 'node:vm';
import {readFileSync} from 'node:fs';
import {runStaffBatch,allowedEndpoint} from './core.mjs';
let checks=0;
function ok(v){assert.ok(v);checks++;}
for(const host of ['fcm.googleapis.com','updates.push.services.mozilla.com','web.push.apple.com','wns2-db5p.notify.windows.com'])ok(allowedEndpoint('https://'+host+'/test'));
for(const url of ['http://fcm.googleapis.com/x','https://fcm.googleapis.com.attacker.test/x','https://user:pass@fcm.googleapis.com/x','https://fcm.googleapis.com:888/x','https://attacker.test/x'])ok(!allowedEndpoint(url));
async function scenario(mode){
 const acks=[];let sends=0;
 const data={payload:{expiresAt:new Date(Date.now()+30000).toISOString()},ttl:300,subscriptions:[{endpoint:'https://fcm.googleapis.com/x'}]};
 if(mode==='expired')data.payload.expiresAt=new Date(Date.now()-1000).toISOString();
 if(mode==='invalidexpiry')data.payload.expiresAt='bad';
 if(mode==='missing')data.subscriptions=[];
 if(mode==='blocked')data.subscriptions=[{endpoint:'https://attacker.test/x'}];
 const result=await runStaffBatch({
 claim:async()=>[{id:'id',lease_token:'token'}],
 delivery:async()=>mode==='cancelled'?null:data,
 send:async(s,p,ttl)=>{sends++;assert.ok(ttl>0&&ttl<=30);if(mode==='permanent')throw {statusCode:410};if(mode==='transient')throw {statusCode:503};},
 ack:async(id,token,status)=>{assert.equal(id,'id');assert.equal(token,'token');if(mode==='ackerror')throw Error('timeout');acks.push(status);}
 });
 return {result,acks,sends};
}
for(const [mode,status,send] of [['success','sent',1],['permanent','failed',1],['transient','retry',1],['expired','cancelled',0],['invalidexpiry','cancelled',0],['missing','retry',0],['blocked','retry',0],['cancelled','cancelled',0],['ackerror','unacknowledged',1]]){
 const r=await scenario(mode);ok(r.result[status]===1);ok(r.sends===send);
}
for(const file of ['../../delivery-app/sw.js','../../shopkeeper-app/sw.js']){
 const handlers={};const notifications=[];
 const ctx={URL,Date,Number,self:{addEventListener:(n,f)=>handlers[n]=f,registration:{showNotification:async(t,n)=>notifications.push({t,n})}}};
 vm.runInNewContext(readFileSync(new URL(file,import.meta.url),'utf8'),ctx);
 async function push(data){let p;handlers.push({data:{json:()=>data},waitUntil:x=>p=x});await p;}
 await push({title:'Expired',expiresAt:new Date(Date.now()-1000).toISOString()});ok(notifications.length===0);
 await push({title:'Malformed',expiresAt:'bad'});ok(notifications.length===0);
 await push({title:'Current',expiresAt:new Date(Date.now()+30000).toISOString(),tag:'stable-job'});ok(notifications.length===1&&notifications[0].n.tag==='stable-job');
 await push({title:'Legacy'});ok(notifications.length===2);
}
console.log('PASS: '+checks+' worker and service-worker assertions');
